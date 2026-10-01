// Package ogen renders the 1200x630 Open Graph card for a language page:
// "{language}" over "running on Laravel Cloud". It is the single OG generator
// for the whole repo -- the index serves its card from here at request time,
// and CI runs tools/ogen to produce og.png for every other language branch.
package ogen

import (
	"bytes"
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"math"

	"golang.org/x/image/font"
	"golang.org/x/image/font/gofont/gobold"
	"golang.org/x/image/font/gofont/goregular"
	"golang.org/x/image/font/opentype"
	"golang.org/x/image/math/fixed"
)

const (
	Width  = 1200
	Height = 630
)

var (
	bgTop    = color.NRGBA{0x0b, 0x10, 0x20, 0xff}
	bgBottom = color.NRGBA{0x1b, 0x22, 0x40, 0xff}
	glow     = color.NRGBA{0x3a, 0x2c, 0x62, 0xff}
	accent   = color.NRGBA{0xf0, 0x56, 0x4a, 0xff}
	fg       = color.NRGBA{0xee, 0xf1, 0xfa, 0xff}
	muted    = color.NRGBA{0x9a, 0xa4, 0xc7, 0xff}
)

// PNG renders the card for language and returns the encoded PNG bytes.
func PNG(language string) ([]byte, error) {
	img := image.NewNRGBA(image.Rect(0, 0, Width, Height))
	paintBackground(img)

	bold, err := opentype.Parse(gobold.TTF)
	if err != nil {
		return nil, err
	}
	regular, err := opentype.Parse(goregular.TTF)
	if err != nil {
		return nil, err
	}

	const left = 86

	eyebrow, err := opentype.NewFace(regular, &opentype.FaceOptions{Size: 30, DPI: 72, Hinting: font.HintingFull})
	if err != nil {
		return nil, err
	}
	drawText(img, eyebrow, accent, left, 178, "HELLO FROM")

	// The language name is the hero. Shrink it until it fits the canvas.
	size := 132.0
	var title font.Face
	for {
		title, err = opentype.NewFace(bold, &opentype.FaceOptions{Size: size, DPI: 72, Hinting: font.HintingFull})
		if err != nil {
			return nil, err
		}
		if font.MeasureString(title, language).Ceil() <= Width-2*left || size <= 42 {
			break
		}
		size -= 4
	}
	drawText(img, title, fg, left, 318, language)

	// Accent rule under the hero.
	draw.Draw(img, image.Rect(left, 360, left+132, 368), &image.Uniform{accent}, image.Point{}, draw.Src)

	sub, err := opentype.NewFace(regular, &opentype.FaceOptions{Size: 46, DPI: 72, Hinting: font.HintingFull})
	if err != nil {
		return nil, err
	}
	drawText(img, sub, fg, left, 450, "running on Laravel Cloud")

	foot, err := opentype.NewFace(regular, &opentype.FaceOptions{Size: 26, DPI: 72, Hinting: font.HintingFull})
	if err != nil {
		return nil, err
	}
	drawText(img, foot, muted, left, 536, "github.com/artisan-build/hello_cloud")

	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// paintBackground lays a vertical gradient down the canvas and a soft radial
// glow in the top-right corner, so the card matches the page's CSS.
func paintBackground(img *image.NRGBA) {
	for y := 0; y < Height; y++ {
		t := float64(y) / float64(Height-1)
		row := color.NRGBA{
			lerp(bgTop.R, bgBottom.R, t),
			lerp(bgTop.G, bgBottom.G, t),
			lerp(bgTop.B, bgBottom.B, t),
			0xff,
		}
		for x := 0; x < Width; x++ {
			img.SetNRGBA(x, y, row)
		}
	}

	cx, cy, radius := 1080.0, 60.0, 620.0
	for y := 0; y < Height; y++ {
		for x := 0; x < Width; x++ {
			d := math.Hypot(float64(x)-cx, float64(y)-cy)
			if d >= radius {
				continue
			}
			t := (1 - d/radius) * 0.55
			c := img.NRGBAAt(x, y)
			img.SetNRGBA(x, y, color.NRGBA{
				lerp(c.R, glow.R, t),
				lerp(c.G, glow.G, t),
				lerp(c.B, glow.B, t),
				0xff,
			})
		}
	}
}

func lerp(a, b uint8, t float64) uint8 {
	return uint8(float64(a) + (float64(b)-float64(a))*t)
}

func drawText(dst draw.Image, face font.Face, c color.NRGBA, x, baseline int, s string) {
	d := font.Drawer{
		Dst:  dst,
		Src:  &image.Uniform{c},
		Face: face,
		Dot:  fixed.P(x, baseline),
	}
	d.DrawString(s)
}
