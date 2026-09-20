package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"sort"
	"sync"
)

// rendererVersion is part of every icon's stamp, so a change to the
// renderer re-renders everything. Bump it with any change to the output.
const rendererVersion = "1"

// catalog is Icons/LiquidGlass/icons.json.
type catalog struct {
	Icons []struct {
		ID    string `json:"id"`
		Group string `json:"group"`
		// Appearances the icon is drawn in: "default" always; "dark",
		// "clear-light" and "clear-dark" where the icon has them.
		Appearances []string `json:"appearances"`
	} `json:"icons"`
}

// output is one PNG an icon produces.
type output struct {
	path, appearance string
	size             int
}

// outputs lists an icon's files: the alternate app icons beside its source
// (`LGIcon-<id>` for System, `__apollo_light` and `__apollo_dark` for the
// picker's Light and Dark, at 2x and 3x), and the picker's 104px previews.
func outputs(root, dir, id string, appearances []string) []output {
	has := func(a string) bool { return slices.Contains(appearances, a) }
	var out []output
	names := map[string]string{"": "default", "__apollo_light": "default"}
	if has("dark") {
		names["__apollo_dark"] = "dark"
	}
	for suffix, look := range names {
		for scale, px := range map[string]int{"@2x": 120, "@3x": 180} {
			out = append(out, output{filepath.Join(dir, "LGIcon-"+id+suffix+"60x60"+scale+".png"), look, px})
		}
	}
	previews := filepath.Join(root, "Sources", "PhoebusUI", "Resources", "LiquidGlassIcons")
	for _, look := range appearances {
		name := id + ".png"
		if look != "default" {
			name = id + "--" + look + ".png"
		}
		out = append(out, output{filepath.Join(previews, name), look, 104})
	}
	return out
}

// stamp hashes the icon's source files and the renderer version.
func stamp(bundle string, outs []output) (string, error) {
	h := sha256.New()
	fmt.Fprintln(h, rendererVersion)
	var files []string
	err := filepath.WalkDir(bundle, func(path string, d fs.DirEntry, err error) error {
		if err == nil && !d.IsDir() {
			files = append(files, path)
		}
		return err
	})
	if err != nil {
		return "", err
	}
	sort.Strings(files)
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			return "", err
		}
		rel, _ := filepath.Rel(bundle, f)
		fmt.Fprintf(h, "%s %d\n", rel, len(data))
		h.Write(data)
	}
	var names []string
	for _, o := range outs {
		names = append(names, fmt.Sprintln(filepath.Base(o.path), o.appearance, o.size))
	}
	sort.Strings(names)
	for _, n := range names {
		h.Write([]byte(n))
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func upToDate(stampPath, want string, outs []output) bool {
	got, err := os.ReadFile(stampPath)
	if err != nil || string(got) != want {
		return false
	}
	for _, o := range outs {
		if _, err := os.Stat(o.path); err != nil {
			return false
		}
	}
	return true
}

// renderOne renders an icon's outputs, each appearance once at the largest
// size it is needed at, then reduced.
func renderOne(bundle string, outs []output) error {
	largest := map[string]int{}
	for _, o := range outs {
		largest[o.appearance] = max(largest[o.appearance], o.size)
	}
	for look, size := range largest {
		img, err := render(bundle, look, max(size*2, 512))
		if err != nil {
			return err
		}
		for _, o := range outs {
			if o.appearance != look {
				continue
			}
			if err := os.MkdirAll(filepath.Dir(o.path), 0o755); err != nil {
				return err
			}
			if err := writePNG(o.path, resize(img, o.size)); err != nil {
				return err
			}
		}
	}
	return nil
}

func renderAll(root string, force bool) error {
	data, err := os.ReadFile(filepath.Join(root, "Icons", "LiquidGlass", "icons.json"))
	if err != nil {
		return err
	}
	var c catalog
	if err := json.Unmarshal(data, &c); err != nil {
		return fmt.Errorf("icons.json: %w", err)
	}
	type job struct{ id, dir string }
	jobs := make(chan job)
	var (
		mu       sync.Mutex
		failures []error
		rendered int
		wg       sync.WaitGroup
	)
	appearances := map[string][]string{}
	for _, icon := range c.Icons {
		appearances[icon.ID] = icon.Appearances
	}
	for range runtime.NumCPU() {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := range jobs {
				bundle := filepath.Join(j.dir, j.id+".icon")
				outs := outputs(root, j.dir, j.id, appearances[j.id])
				want, err := stamp(bundle, outs)
				stampPath := filepath.Join(j.dir, ".rendered")
				if err == nil && (force || !upToDate(stampPath, want, outs)) {
					if err = renderOne(bundle, outs); err == nil {
						err = os.WriteFile(stampPath, []byte(want), 0o644)
						mu.Lock()
						rendered++
						mu.Unlock()
					}
				}
				if err != nil {
					mu.Lock()
					failures = append(failures, fmt.Errorf("%s: %w", j.id, err))
					mu.Unlock()
				}
			}
		}()
	}
	for _, icon := range c.Icons {
		jobs <- job{icon.ID, filepath.Join(root, "Icons", "LiquidGlass", icon.Group, icon.ID)}
	}
	close(jobs)
	wg.Wait()
	if len(failures) > 0 {
		return fmt.Errorf("%d icon(s) failed: %v", len(failures), failures)
	}
	fmt.Printf("lgrender: %d of %d icons rendered, the rest up to date\n", rendered, len(c.Icons))
	return nil
}
