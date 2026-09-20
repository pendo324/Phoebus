// Renders Icon Composer (.icon) bundles to flat PNGs on Linux: the background
// fill, each layer's artwork (SVG through rsvg-convert, or a bitmap) placed
// and scaled as the manifest says, filled, faded and blended, groups composed
// back to front with their shadows. Glass, translucency and specular light
// are approximated; only Apple's renderer draws them exactly.
//
// Usage:
//
//	lgrender -root . [-apollo-ipa apollo.ipa]   render every icon in Icons/LiquidGlass/icons.json,
//	                                            and extract the standard icons from Apollo's IPA
//	lgrender -icon X.icon -appearance default|dark|clear-light|clear-dark -size 180 -o out.png
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	_ "image/jpeg"
	"image/png"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"

	"github.com/jackmordaunt/icns/v4/appicon"
	xdraw "golang.org/x/image/draw"
)

// The canvas Icon Composer positions layers on, in points.
const canvasPoints = 1024.0

type specialized[T any] struct {
	Appearance string `json:"appearance"`
	Idiom      string `json:"idiom"`
	Value      T      `json:"value"`
}

type rawFill = json.RawMessage

type manifest struct {
	Fill   rawFill                `json:"fill"`
	Fills  []specialized[rawFill] `json:"fill-specializations"`
	Groups []group                `json:"groups"`
}

type group struct {
	Hidden        bool                                `json:"hidden"`
	Layers        []layer                             `json:"layers"`
	Shadow        *appicon.Shadow                     `json:"shadow"`
	Shadows       []specialized[appicon.Shadow]       `json:"shadow-specializations"`
	Translucency  *appicon.Translucency               `json:"translucency"`
	Translucencys []specialized[appicon.Translucency] `json:"translucency-specializations"`
	Specular      *bool                               `json:"specular"`
	Speculars     []specialized[bool]                 `json:"specular-specializations"`
	BlendMode     string                              `json:"blend-mode"`
	BlendModes    []specialized[string]               `json:"blend-mode-specializations"`
	Opacity       *float64                            `json:"opacity"`
	Opacities     []specialized[float64]              `json:"opacity-specializations"`
}

type layer struct {
	Name       string                          `json:"name"`
	Image      string                          `json:"image-name"`
	Hidden     bool                            `json:"hidden"`
	Glass      bool                            `json:"glass"`
	Fill       rawFill                         `json:"fill"`
	Fills      []specialized[rawFill]          `json:"fill-specializations"`
	Opacity    *float64                        `json:"opacity"`
	Opacities  []specialized[float64]          `json:"opacity-specializations"`
	BlendMode  string                          `json:"blend-mode"`
	BlendModes []specialized[string]           `json:"blend-mode-specializations"`
	Position   *appicon.Position               `json:"position"`
	Positions  []specialized[appicon.Position] `json:"position-specializations"`
}

// pick returns the value for the appearance: its own entry, else the
// default entry, else the plain field.
func pick[T any](list []specialized[T], appearance string, plain *T) (T, bool) {
	var zero T
	for _, s := range list {
		if s.Appearance == appearance {
			return s.Value, true
		}
	}
	for _, s := range list {
		if s.Appearance == "" {
			return s.Value, true
		}
	}
	if plain != nil {
		return *plain, true
	}
	return zero, false
}

func hasSpecialization[T any](list []specialized[T], appearance string) bool {
	for _, s := range list {
		if s.Appearance == appearance {
			return true
		}
	}
	return false
}

func pickString(list []specialized[string], appearance, plain string) string {
	if v, ok := pick(list, appearance, nil); ok {
		return v
	}
	return plain
}

func pickFill(list []specialized[rawFill], appearance string, plain rawFill) rawFill {
	if v, ok := pick(list, appearance, nil); ok {
		return v
	}
	return plain
}

// MARK: colour

type rgba struct{ r, g, b, a float64 } // linear-light sRGB, straight alpha

func srgbToLinear(c float64) float64 {
	if c <= 0.04045 {
		return c / 12.92
	}
	return math.Pow((c+0.055)/1.055, 2.4)
}

func linearToSRGB(c float64) float64 {
	if c <= 0.0031308 {
		return c * 12.92
	}
	return 1.055*math.Pow(c, 1/2.4) - 0.055
}

func parseColor(s string) rgba {
	space, values, _ := strings.Cut(s, ":")
	var v []float64
	for _, p := range strings.Split(values, ",") {
		f, _ := strconv.ParseFloat(strings.TrimSpace(p), 64)
		v = append(v, f)
	}
	switch {
	case strings.Contains(space, "gray") && len(v) >= 2:
		l := srgbToLinear(v[0])
		return rgba{l, l, l, v[1]}
	case space == "display-p3" && len(v) >= 4:
		r, g, b := srgbToLinear(v[0]), srgbToLinear(v[1]), srgbToLinear(v[2])
		// Display P3 to sRGB primaries, both D65, in linear light.
		return rgba{
			1.2249*r - 0.2247*g + 0*b,
			-0.0420*r + 1.0419*g + 0*b,
			-0.0197*r - 0.0786*g + 1.0979*b,
			v[3],
		}
	case len(v) >= 4:
		return rgba{srgbToLinear(v[0]), srgbToLinear(v[1]), srgbToLinear(v[2]), v[3]}
	}
	return rgba{1, 1, 1, 1}
}

func (c rgba) mix(o rgba, t float64) rgba {
	return rgba{c.r + (o.r-c.r)*t, c.g + (o.g-c.g)*t, c.b + (o.b-c.b)*t, c.a + (o.a-c.a)*t}
}

// MARK: fills

// paint gives the fill's colour at a point in [0,1]² of the area it fills.
type paint func(x, y float64) rgba

type gradientFill struct {
	Linear      []string `json:"linear-gradient"`
	Automatic   string   `json:"automatic-gradient"`
	Solid       string   `json:"solid"`
	Orientation *struct {
		Start struct{ X, Y float64 } `json:"start"`
		Stop  struct{ X, Y float64 } `json:"stop"`
	} `json:"orientation"`
}

func linear(c0, c1 rgba, sx, sy, ex, ey float64) paint {
	dx, dy := ex-sx, ey-sy
	length := dx*dx + dy*dy
	return func(x, y float64) rgba {
		t := 0.0
		if length > 0 {
			t = ((x-sx)*dx + (y-sy)*dy) / length
		}
		return c0.mix(c1, math.Max(0, math.Min(1, t)))
	}
}

func makePaint(raw rawFill, appearance string, isBackground bool) paint {
	if len(raw) == 0 {
		if isBackground {
			return namedPaint("automatic", appearance)
		}
		return nil
	}
	var name string
	if json.Unmarshal(raw, &name) == nil {
		// On a layer, a named fill keeps the artwork's own colours.
		if !isBackground {
			return nil
		}
		return namedPaint(name, appearance)
	}
	var f gradientFill
	if json.Unmarshal(raw, &f) != nil {
		return nil
	}
	sx, sy, ex, ey := 0.5, 0.0, 0.5, 1.0
	if f.Orientation != nil {
		sx, sy, ex, ey = f.Orientation.Start.X, f.Orientation.Start.Y, f.Orientation.Stop.X, f.Orientation.Stop.Y
	}
	switch {
	case f.Solid != "":
		c := parseColor(f.Solid)
		return func(float64, float64) rgba { return c }
	case len(f.Linear) >= 2:
		return linear(parseColor(f.Linear[0]), parseColor(f.Linear[1]), sx, sy, ex, ey)
	case f.Automatic != "":
		base := parseColor(f.Automatic)
		top := base.mix(rgba{1, 1, 1, base.a}, 0.35)
		return linear(top, base, 0.5, 0, 0.5, 1)
	}
	return nil
}

func namedPaint(name, appearance string) paint {
	dark := strings.Contains(appearance, "dark")
	switch name {
	case "system-dark":
		return linear(parseColor("srgb:0.2,0.2,0.21,1"), parseColor("srgb:0.07,0.07,0.08,1"), 0.5, 0, 0.5, 1)
	case "system-light":
		return linear(parseColor("srgb:1,1,1,1"), parseColor("srgb:0.86,0.86,0.88,1"), 0.5, 0, 0.5, 1)
	case "none":
		return nil
	}
	if dark {
		return namedPaint("system-dark", appearance)
	}
	return namedPaint("system-light", appearance)
}

// MARK: raster helpers

type canvas struct {
	w, h int
	px   []rgba // premultiplied, linear light
}

func newCanvas(n int) *canvas { return &canvas{n, n, make([]rgba, n*n)} }

func (c *canvas) at(x, y int) *rgba { return &c.px[y*c.w+x] }

type blend func(src, dst float64) float64

var blends = map[string]blend{
	"normal":       func(s, d float64) float64 { return s },
	"multiply":     func(s, d float64) float64 { return s * d },
	"screen":       func(s, d float64) float64 { return s + d - s*d },
	"darken":       math.Min,
	"lighten":      math.Max,
	"plus-lighter": func(s, d float64) float64 { return math.Min(1, s+d) },
	"plus-darker":  func(s, d float64) float64 { return math.Max(0, s+d-1) },
	"overlay": func(s, d float64) float64 {
		if d < 0.5 {
			return 2 * s * d
		}
		return 1 - 2*(1-s)*(1-d)
	},
	"hard-light": func(s, d float64) float64 {
		if s < 0.5 {
			return 2 * s * d
		}
		return 1 - 2*(1-s)*(1-d)
	},
}

// over composites src (premultiplied) onto dst with a separable blend mode,
// per the W3C compositing model.
func over(dst, src *canvas, mode string, opacity float64) {
	b := blends[mode]
	if b == nil {
		b = blends["normal"]
	}
	additive := mode == "plus-lighter" || mode == "plus-darker"
	for i := range dst.px {
		s := src.px[i]
		sa := s.a * opacity
		if sa <= 0 {
			continue
		}
		s.r, s.g, s.b = s.r*opacity, s.g*opacity, s.b*opacity
		d := &dst.px[i]
		if additive {
			if mode == "plus-lighter" {
				d.r, d.g, d.b, d.a = math.Min(1, d.r+s.r), math.Min(1, d.g+s.g), math.Min(1, d.b+s.b), math.Min(1, d.a+sa)
			} else {
				d.r = math.Max(0, d.r+s.r-sa)
				d.g = math.Max(0, d.g+s.g-sa)
				d.b = math.Max(0, d.b+s.b-sa)
				d.a = math.Min(1, d.a+sa)
			}
			continue
		}
		da := d.a
		ch := func(sc, dc float64) float64 {
			su, du := sc/sa, 0.0
			if da > 0 {
				du = dc / da
			}
			return sc*(1-da) + dc*(1-sa) + sa*da*b(su, du)
		}
		d.r, d.g, d.b = ch(s.r, d.r), ch(s.g, d.g), ch(s.b, d.b)
		d.a = sa + da*(1-sa)
	}
}

func boxBlurAlpha(a []float64, w, h, radius int) []float64 {
	out := make([]float64, len(a))
	tmp := make([]float64, len(a))
	for pass := 0; pass < 3; pass++ {
		for y := 0; y < h; y++ {
			sum := 0.0
			for x := -radius; x <= radius; x++ {
				sum += a[y*w+clamp(x, w)]
			}
			for x := 0; x < w; x++ {
				tmp[y*w+x] = sum / float64(2*radius+1)
				sum += a[y*w+clamp(x+radius+1, w)] - a[y*w+clamp(x-radius, w)]
			}
		}
		for x := 0; x < w; x++ {
			sum := 0.0
			for y := -radius; y <= radius; y++ {
				sum += tmp[clamp(y, h)*w+x]
			}
			for y := 0; y < h; y++ {
				out[y*w+x] = sum / float64(2*radius+1)
				sum += tmp[clamp(y+radius+1, h)*w+x] - tmp[clamp(y-radius, h)*w+x]
			}
		}
		copy(a, out)
	}
	return out
}

func clamp(v, n int) int {
	if v < 0 {
		return 0
	}
	if v >= n {
		return n - 1
	}
	return v
}

// MARK: layers

var (
	rasterCache = map[string]image.Image{}
	rasterMu    sync.Mutex
)

func rasterize(path string, zoom float64) (image.Image, error) {
	key := fmt.Sprintf("%s@%.4f", path, zoom)
	rasterMu.Lock()
	cached, ok := rasterCache[key]
	rasterMu.Unlock()
	if ok {
		return cached, nil
	}
	var img image.Image
	if strings.EqualFold(filepath.Ext(path), ".svg") {
		out, err := exec.Command("rsvg-convert", "--dpi-x", "72", "--dpi-y", "72", "-z", strconv.FormatFloat(zoom, 'f', 5, 64), "-f", "png", path).Output()
		if err != nil {
			return nil, fmt.Errorf("rsvg-convert %s: %w", path, err)
		}
		if img, err = png.Decode(bytes.NewReader(out)); err != nil {
			return nil, err
		}
	} else {
		f, err := os.Open(path)
		if err != nil {
			return nil, err
		}
		defer f.Close()
		src, _, err := image.Decode(f)
		if err != nil {
			return nil, err
		}
		b := src.Bounds()
		w, h := int(math.Round(float64(b.Dx())*zoom)), int(math.Round(float64(b.Dy())*zoom))
		dst := image.NewRGBA(image.Rect(0, 0, max(w, 1), max(h, 1)))
		xdraw.CatmullRom.Scale(dst, dst.Bounds(), src, b, draw.Src, nil)
		img = dst
	}
	rasterMu.Lock()
	rasterCache[key] = img
	rasterMu.Unlock()
	return img, nil
}

func drawLayer(bundle string, l layer, appearance string, n int, clear bool) (*canvas, error) {
	pos := appicon.Position{Scale: 1}
	if p, ok := pick(l.Positions, appearance, l.Position); ok {
		pos = p
		if l.Position == nil && len(l.Positions) > 0 && l.Positions[0].Idiom == "square" {
			// A square-idiom position is in a canvas a sixth the size
			// (fitted against Reborn's own previews).
			const k = 6.0
			pos.Scale *= k
			pos.Translation[0] *= k
			pos.Translation[1] *= k
		}
	}
	if pos.Scale == 0 {
		pos.Scale = 1
	}
	unit := float64(n) / canvasPoints
	img, err := rasterize(filepath.Join(bundle, "Assets", l.Image), pos.Scale*unit)
	if err != nil {
		return nil, err
	}
	b := img.Bounds()
	ox := float64(n)/2 + pos.Translation[0]*unit - float64(b.Dx())/2
	oy := float64(n)/2 + pos.Translation[1]*unit - float64(b.Dy())/2
	fill := makePaint(pickFill(l.Fills, appearance, l.Fill), appearance, false)
	c := newCanvas(n)
	for y := 0; y < b.Dy(); y++ {
		ty := y + int(math.Round(oy))
		if ty < 0 || ty >= n {
			continue
		}
		for x := 0; x < b.Dx(); x++ {
			tx := x + int(math.Round(ox))
			if tx < 0 || tx >= n {
				continue
			}
			sr, sg, sb, sa := img.At(b.Min.X+x, b.Min.Y+y).RGBA()
			a := float64(sa) / 0xffff
			if a == 0 {
				continue
			}
			var col rgba
			if fill != nil {
				col = fill(float64(x)/float64(max(b.Dx(), 1)), float64(y)/float64(max(b.Dy(), 1)))
			} else {
				col = rgba{srgbToLinear(float64(sr) / float64(sa)), srgbToLinear(float64(sg) / float64(sa)), srgbToLinear(float64(sb) / float64(sa)), 1}
			}
			fa := a * col.a
			*c.at(tx, ty) = rgba{col.r * fa, col.g * fa, col.b * fa, fa}
		}
	}
	return c, nil
}

// glassLight adds the bright rim glass picks up along a shape's top edge.
func glassLight(c *canvas, strength float64) {
	n := c.w
	alpha := make([]float64, len(c.px))
	for i, p := range c.px {
		alpha[i] = p.a
	}
	shift := max(1, n/170)
	for y := n - 1; y >= 0; y-- {
		for x := 0; x < n; x++ {
			above := 0.0
			if y-shift >= 0 {
				above = alpha[(y-shift)*n+x]
			}
			rim := alpha[y*n+x] - above
			if rim <= 0 {
				continue
			}
			p := &c.px[y*n+x]
			k := rim * strength
			p.r += (p.a - p.r) * k
			p.g += (p.a - p.g) * k
			p.b += (p.a - p.b) * k
		}
	}
}

// toClear turns a group's colours into the clear look's greys: bright
// artwork towards white, dark artwork towards the background.
func toClear(c *canvas, dark bool) {
	lo, span := 0.30, 0.70
	if dark {
		lo, span = 0.04, 0.55
	}
	for i, p := range c.px {
		if p.a <= 0 {
			continue
		}
		l := (0.2126*p.r + 0.7152*p.g + 0.0722*p.b) / p.a
		v := (lo + span*math.Pow(l, 0.6)) * p.a
		c.px[i] = rgba{v, v, v, p.a}
	}
}

func render(bundle, appearance string, n int) (image.Image, error) {
	data, err := os.ReadFile(filepath.Join(bundle, "icon.json"))
	if err != nil {
		return nil, err
	}
	var m manifest
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, err
	}
	clear := strings.HasPrefix(appearance, "clear")
	look := appearance // the specializations to read
	if clear {
		look = strings.TrimPrefix(appearance, "clear-")
		if look == "light" {
			look = ""
		}
	}
	if look == "default" {
		look = ""
	}

	out := newCanvas(n)
	var bg paint
	if clear {
		if look == "dark" {
			bg = linear(parseColor("srgb:0.24,0.24,0.25,1"), parseColor("srgb:0.13,0.13,0.14,1"), 0.5, 0, 0.5, 1)
		} else {
			bg = linear(parseColor("srgb:0.66,0.66,0.67,1"), parseColor("srgb:0.55,0.55,0.56,1"), 0.5, 0, 0.5, 1)
		}
	} else {
		raw := pickFill(m.Fills, look, m.Fill)
		// Dark mode draws the system's dark background unless the icon
		// specialises its own for dark.
		if look == "dark" && !hasSpecialization(m.Fills, "dark") {
			raw = rawFill(`"system-dark"`)
		}
		bg = makePaint(raw, look, true)
	}
	if bg != nil {
		for y := 0; y < n; y++ {
			for x := 0; x < n; x++ {
				c := bg(float64(x)/float64(n), float64(y)/float64(n))
				*out.at(x, y) = rgba{c.r * c.a, c.g * c.a, c.b * c.a, c.a}
			}
		}
	}

	// Groups and layers are listed front to back.
	for gi := len(m.Groups) - 1; gi >= 0; gi-- {
		g := m.Groups[gi]
		if g.Hidden {
			continue
		}
		gc := newCanvas(n)
		anyGlass := false
		for li := len(g.Layers) - 1; li >= 0; li-- {
			l := g.Layers[li]
			if l.Hidden || l.Image == "" {
				continue
			}
			opacity := 1.0
			if o, ok := pick(l.Opacities, look, l.Opacity); ok {
				opacity = o
			}
			if opacity <= 0 {
				continue
			}
			lc, err := drawLayer(bundle, l, look, n, clear)
			if err != nil {
				return nil, err
			}
			anyGlass = anyGlass || l.Glass
			over(gc, lc, pickString(l.BlendModes, look, l.BlendMode), math.Min(1, opacity))
		}
		specular := false
		if s, ok := pick(g.Speculars, look, g.Specular); ok {
			specular = s
		}
		if anyGlass || specular || clear {
			glassLight(gc, 0.35)
		}
		groupOpacity := 1.0
		if o, ok := pick(g.Opacities, look, g.Opacity); ok {
			groupOpacity = math.Min(1, o)
		}
		// Glass lets the background through by its translucency; flat
		// layers stay opaque.
		if t, ok := pick(g.Translucencys, look, g.Translucency); ok && t.Enabled && (anyGlass || clear) {
			groupOpacity *= 1 - t.Value*0.8
		}
		if sh, ok := pick(g.Shadows, look, g.Shadow); ok && sh.Opacity > 0 {
			alpha := make([]float64, len(gc.px))
			for i, p := range gc.px {
				alpha[i] = p.a
			}
			blurred := boxBlurAlpha(alpha, n, n, max(1, n/64))
			strength := math.Min(0.6, sh.Opacity*0.12) * groupOpacity
			dy := max(1, n/80)
			sc := newCanvas(n)
			for y := 0; y < n; y++ {
				for x := 0; x < n; x++ {
					if y-dy < 0 {
						continue
					}
					a := blurred[(y-dy)*n+x] * strength
					*sc.at(x, y) = rgba{0, 0, 0, a}
				}
			}
			over(out, sc, "normal", 1)
		}
		if clear {
			toClear(gc, look == "dark")
		}
		over(out, gc, pickString(g.BlendModes, look, g.BlendMode), groupOpacity)
	}

	img := image.NewNRGBA(image.Rect(0, 0, n, n))
	for y := 0; y < n; y++ {
		for x := 0; x < n; x++ {
			p := out.px[y*n+x]
			if p.a <= 0 {
				continue
			}
			to := func(v float64) uint8 {
				return uint8(math.Round(math.Max(0, math.Min(1, linearToSRGB(v/p.a))) * 255))
			}
			img.SetNRGBA(x, y, color.NRGBA{to(p.r), to(p.g), to(p.b), uint8(math.Round(math.Min(1, p.a) * 255))})
		}
	}
	return img, nil
}

// renderAt renders at a working size, then reduces to size for smooth edges.
func renderAt(icon, appearance string, size int) (image.Image, error) {
	img, err := render(icon, appearance, max(size*2, 512))
	if err != nil {
		return nil, err
	}
	return resize(img, size), nil
}

func resize(img image.Image, size int) *image.NRGBA {
	dst := image.NewNRGBA(image.Rect(0, 0, size, size))
	xdraw.CatmullRom.Scale(dst, dst.Bounds(), img, img.Bounds(), draw.Src, nil)
	return dst
}

func writePNG(path string, img image.Image) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	if err := png.Encode(f, img); err != nil {
		f.Close()
		return err
	}
	return f.Close()
}

func main() {
	root := flag.String("root", "", "repository root: render every icon listed in Icons/LiquidGlass/icons.json")
	force := flag.Bool("force", false, "with -root, re-render icons that are up to date")
	apolloIPA := flag.String("apollo-ipa", "", "with -root, also extract the standard icons from this Apollo IPA")
	icon := flag.String("icon", "", ".icon bundle")
	appearance := flag.String("appearance", "default", "default, dark, clear-light or clear-dark")
	size := flag.Int("size", 180, "output size in pixels")
	outPath := flag.String("o", "", "output PNG")
	flag.Parse()
	if *root != "" {
		err := renderAll(*root, *force)
		if err == nil && *apolloIPA != "" {
			err = extractApolloIcons(*root, *apolloIPA, *force)
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, "lgrender:", err)
			os.Exit(1)
		}
		return
	}
	img, err := renderAt(*icon, *appearance, *size)
	if err == nil {
		err = writePNG(*outPath, img)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "lgrender:", err)
		os.Exit(1)
	}
}
