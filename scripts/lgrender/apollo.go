package main

import (
	"archive/zip"
	"bytes"
	"compress/flate"
	"compress/zlib"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"hash/crc32"
	"image"
	"image/color"
	"image/png"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// apolloVersion is part of the extraction stamp; bump it with any change to
// the output.
const apolloVersion = "1"

// The standard icons listed in xtool.yml, `Icons/Standard/<id>/AppIcon-<id>60x60@2x.png`.
var standardIconPath = regexp.MustCompile(`Icons/Standard/([^/\s]+)/AppIcon-[^/\s]+60x60@[23]x\.png`)

func standardIconIDs(root string) ([]string, error) {
	data, err := os.ReadFile(filepath.Join(root, "xtool.yml"))
	if err != nil {
		return nil, err
	}
	seen := map[string]bool{}
	var ids []string
	for _, m := range standardIconPath.FindAllStringSubmatch(string(data), -1) {
		if !seen[m[1]] {
			seen[m[1]] = true
			ids = append(ids, m[1])
		}
	}
	return ids, nil
}

// extractApolloIcons writes the standard alternate icons from Apollo's own
// app bundle. Apollo ships each as loose PNGs (`app-icon-<device>-<slug>.png`,
// with @2x and @3x), named inconsistently, so each icon is taken by its
// measured size: an exact 120px or 180px file where one exists, otherwise
// the next larger one reduced. Icons Apollo doesn't have (Reborn's Ultra
// additions) are rendered from their Liquid Glass source instead.
func extractApolloIcons(root, ipaPath string, force bool) error {
	ids, err := standardIconIDs(root)
	if err != nil {
		return err
	}
	ipaSum, err := fileSHA256(ipaPath)
	if err != nil {
		return err
	}
	stampPath := filepath.Join(root, "Icons", "Standard", ".extracted")
	want := apolloVersion + " " + ipaSum + " " + strings.Join(ids, ",")
	if !force && standardUpToDate(root, ids, stampPath, want) {
		fmt.Println("lgrender: standard icons up to date")
		return nil
	}

	zr, err := zip.OpenReader(ipaPath)
	if err != nil {
		return fmt.Errorf("%s: %w", ipaPath, err)
	}
	defer zr.Close()
	// slug -> decoded images
	bySlug := map[string][]image.Image{}
	name := regexp.MustCompile(`^Payload/[^/]+\.app/app-icon-[a-z-]*?(iphone|ipad-pro|ipad)-(.+?)(@[23]x)?\.png$`)
	var primary []image.Image
	for _, f := range zr.File {
		m := name.FindStringSubmatch(f.Name)
		isPrimary := strings.HasPrefix(f.Name, "Payload/") && strings.Count(f.Name, "/") == 2 &&
			strings.HasPrefix(filepath.Base(f.Name), "AppIcon60x60")
		if m == nil && !isPrimary {
			continue
		}
		img, err := decodeZipPNG(f)
		if err != nil {
			return fmt.Errorf("%s: %w", f.Name, err)
		}
		if isPrimary {
			primary = append(primary, img)
		} else {
			bySlug[m[2]] = append(bySlug[m[2]], img)
		}
	}
	// The bundle's default icon.
	bySlug["Original"] = primary

	var missing []string
	for _, id := range ids {
		dir := filepath.Join(root, "Icons", "Standard", id)
		images := bySlug[id]
		var source func(int) (image.Image, error)
		switch {
		case len(images) > 0:
			source = func(px int) (image.Image, error) { return pickSize(images, px) }
		default:
			lg := filepath.Join(root, "Icons", "LiquidGlass", "ultra", id, id+".icon")
			if _, err := os.Stat(lg); err != nil {
				missing = append(missing, id)
				continue
			}
			source = func(px int) (image.Image, error) { return renderAt(lg, "default", px) }
		}
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
		for scale, px := range map[string]int{"@2x": 120, "@3x": 180} {
			img, err := source(px)
			if err != nil {
				return fmt.Errorf("%s%s: %w", id, scale, err)
			}
			if err := writePNG(filepath.Join(dir, "AppIcon-"+id+"60x60"+scale+".png"), img); err != nil {
				return err
			}
		}
	}
	if len(missing) > 0 {
		return fmt.Errorf("no artwork in the IPA or Icons/LiquidGlass/ultra for: %s", strings.Join(missing, ", "))
	}
	fmt.Printf("lgrender: %d standard icons extracted\n", len(ids))
	return os.WriteFile(stampPath, []byte(want), 0o644)
}

func standardUpToDate(root string, ids []string, stampPath, want string) bool {
	got, err := os.ReadFile(stampPath)
	if err != nil || string(got) != want {
		return false
	}
	for _, id := range ids {
		for _, scale := range []string{"@2x", "@3x"} {
			if _, err := os.Stat(filepath.Join(root, "Icons", "Standard", id, "AppIcon-"+id+"60x60"+scale+".png")); err != nil {
				return false
			}
		}
	}
	return true
}

// pickSize returns the image that is exactly px square, else the smallest
// larger one reduced to px, else the largest enlarged.
func pickSize(images []image.Image, px int) (image.Image, error) {
	sorted := append([]image.Image(nil), images...)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].Bounds().Dx() < sorted[j].Bounds().Dx() })
	for _, img := range sorted {
		if b := img.Bounds(); b.Dx() == px && b.Dy() == px {
			return img, nil
		}
	}
	for _, img := range sorted {
		if img.Bounds().Dx() > px {
			return resize(img, px), nil
		}
	}
	if len(sorted) == 0 {
		return nil, errors.New("no images")
	}
	return resize(sorted[len(sorted)-1], px), nil
}

func fileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func decodeZipPNG(f *zip.File) (image.Image, error) {
	r, err := f.Open()
	if err != nil {
		return nil, err
	}
	defer r.Close()
	data, err := io.ReadAll(r)
	if err != nil {
		return nil, err
	}
	return decodeCgBI(data)
}

// decodeCgBI decodes a PNG, including Apple's "crushed" CgBI variant that
// Xcode writes into app bundles: an extra CgBI chunk before IHDR, IDAT as
// a raw deflate stream with no zlib wrapper, and BGRA channels with
// premultiplied alpha. Standard PNGs decode as usual.
func decodeCgBI(data []byte) (image.Image, error) {
	const signature = "\x89PNG\r\n\x1a\n"
	if !bytes.HasPrefix(data, []byte(signature)) {
		return nil, errors.New("not a PNG")
	}
	var (
		isCgBI bool
		ihdr   []byte
		idat   bytes.Buffer
		rest   bytes.Buffer // chunks other than CgBI, IHDR, IDAT, IEND
	)
	for off := len(signature); off+8 <= len(data); {
		length := int(binary.BigEndian.Uint32(data[off:]))
		if off+12+length > len(data) {
			return nil, errors.New("truncated chunk")
		}
		kind := string(data[off+4 : off+8])
		body := data[off+8 : off+8+length]
		switch kind {
		case "CgBI":
			isCgBI = true
		case "IHDR":
			ihdr = body
		case "IDAT":
			idat.Write(body)
		case "IEND":
		default:
			rest.Write(data[off : off+12+length])
		}
		off += 12 + length
	}
	if !isCgBI {
		return png.Decode(bytes.NewReader(data))
	}
	if len(ihdr) < 13 || ihdr[8] != 8 || (ihdr[9] != 6 && ihdr[9] != 2) {
		return nil, errors.New("unsupported CgBI colour type")
	}
	raw, err := io.ReadAll(flate.NewReader(&idat))
	if err != nil {
		return nil, fmt.Errorf("inflating IDAT: %w", err)
	}
	// Re-wrap the filtered scanlines as a standard PNG and let image/png
	// unfilter them; the channel order and premultiplication are undone on
	// the decoded pixels.
	var z bytes.Buffer
	zw := zlib.NewWriter(&z)
	zw.Write(raw)
	zw.Close()
	var out bytes.Buffer
	out.WriteString(signature)
	writeChunk(&out, "IHDR", ihdr)
	writeChunk(&out, "IDAT", z.Bytes())
	writeChunk(&out, "IEND", nil)
	img, err := png.Decode(&out)
	if err != nil {
		return nil, err
	}
	b := img.Bounds()
	dst := image.NewNRGBA(b)
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			c := color.NRGBAModel.Convert(img.At(x, y)).(color.NRGBA)
			// Stored as B, G, R, A, premultiplied.
			r, g, bl, a := c.B, c.G, c.R, c.A
			if ihdr[9] == 6 && a > 0 {
				un := func(v uint8) uint8 { return uint8(min(255, (int(v)*255+int(a)/2)/int(a))) }
				r, g, bl = un(r), un(g), un(bl)
			}
			dst.SetNRGBA(x, y, color.NRGBA{r, g, bl, a})
		}
	}
	return dst, nil
}

func writeChunk(w *bytes.Buffer, kind string, body []byte) {
	var n [4]byte
	binary.BigEndian.PutUint32(n[:], uint32(len(body)))
	w.Write(n[:])
	w.WriteString(kind)
	w.Write(body)
	crc := crc32.NewIEEE()
	crc.Write([]byte(kind))
	crc.Write(body)
	binary.BigEndian.PutUint32(n[:], crc.Sum32())
	w.Write(n[:])
}
