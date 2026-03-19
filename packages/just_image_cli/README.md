# just_image_cli

Command-line tool for high-performance image processing, powered by [`just_image`](https://pub.dev/packages/just_image).

Resize, convert, crop, rotate, apply effects, and inspect images — all from the terminal.

## Prerequisites

- **Dart SDK** >= 3.10.8
- **Rust toolchain** ([rustup.rs](https://rustup.rs/))

## Installation

```bash
dart pub global activate just_image_cli
```

## Commands

### `process` — Transform images

```bash
just_image_cli process -i photo.jpg -o result.webp [options]
```

| Option | Description | Example |
|---|---|---|
| `-i, --input` | Input file path (**required**) | `-i photo.jpg` |
| `-o, --output` | Output file path (**required**) | `-o out.webp` |
| `--resize` | Resize to WxH | `--resize 1920x1080` |
| `-f, --format` | Output format (jpeg, png, webp, avif, tiff, bmp) | `-f webp` |
| `-q, --quality` | Compression quality 1-100 (default: 90) | `-q 85` |
| `--blur` | Gaussian blur sigma | `--blur 2.0` |
| `--sharpen` | Sharpen amount | `--sharpen 1.5` |
| `--brightness` | Brightness [-1.0, 1.0] | `--brightness 0.1` |
| `--contrast` | Contrast [-1.0, 1.0] | `--contrast 0.2` |
| `--rotate` | Rotation in degrees | `--rotate 90` |
| `--flip` | Flip direction (horizontal, vertical) | `--flip horizontal` |
| `--crop` | Crop as X,Y,W,H | `--crop 0,0,800,600` |
| `--watermark` | Watermark image path | `--watermark logo.png` |
| `--watermark-x` | Watermark X offset (default: 0) | `--watermark-x 50` |
| `--watermark-y` | Watermark Y offset (default: 0) | `--watermark-y 50` |
| `--watermark-opacity` | Watermark opacity 0.0-1.0 (default: 1.0) | `--watermark-opacity 0.7` |

### `info` — Inspect images

```bash
just_image_cli info -i photo.jpg
```

Output:

```
File:       photo.jpg
Dimensions: 4032x3024
File size:  3.2 MB
```

## Examples

```bash
# Convert JPEG to WebP at quality 85
just_image_cli process -i photo.jpg -o photo.webp -f webp -q 85

# Resize and sharpen
just_image_cli process -i input.png -o thumb.png --resize 400x300 --sharpen 1.5

# Crop, rotate, and adjust brightness
just_image_cli process -i raw.tiff -o final.avif \
  --crop 100,200,1600,1200 --rotate 90 --brightness 0.1 -f avif

# Add watermark
just_image_cli process -i photo.jpg -o branded.jpg \
  --watermark logo.png --watermark-x 50 --watermark-y 50 --watermark-opacity 0.5
```

## License

See [LICENSE](LICENSE).
