use image::{DynamicImage, ImageBuffer, Rgba};
use rayon::prelude::*;

use crate::pixel_ops::map_rgb;

/// Gaussian blur with the given sigma radius.
pub fn gaussian_blur(img: &DynamicImage, sigma: f32) -> DynamicImage {
    DynamicImage::ImageRgba8(image::imageops::blur(img, sigma))
}

/// Unsharp mask sharpen: original + amount * (original - blurred).
pub fn unsharp_mask(img: &DynamicImage, amount: f32, threshold: f32) -> DynamicImage {
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let blurred_rgba = image::imageops::blur(img, 1.0);

    let src = rgba.as_raw();
    let blur = blurred_rgba.as_raw();
    let mut dst = vec![0u8; src.len()];
    let row_stride = w as usize * 4;

    dst.par_chunks_mut(row_stride)
        .enumerate()
        .for_each(|(y, row)| {
            let off = y * row_stride;
            for i in (0..row.len()).step_by(4) {
                for c in 0..3 {
                    let orig = src[off + i + c] as f32;
                    let blur_val = blur[off + i + c] as f32;
                    let diff = (orig - blur_val).abs();
                    row[i + c] = if diff > threshold {
                        (orig + amount * (orig - blur_val)).clamp(0.0, 255.0) as u8
                    } else {
                        src[off + i + c]
                    };
                }
                row[i + 3] = src[off + i + 3];
            }
        });

    ImageBuffer::<Rgba<u8>, Vec<u8>>::from_raw(w, h, dst)
        .map(DynamicImage::ImageRgba8)
        .expect("buffer size matches image dimensions")
}

/// Sobel edge detection. Returns a greyscale edge map with alpha=255.
pub fn sobel_edges(img: &DynamicImage) -> DynamicImage {
    let gray = img.to_luma8();
    let (w, h) = gray.dimensions();
    let mut output = ImageBuffer::<Rgba<u8>, Vec<u8>>::new(w, h);

    let src: Vec<Vec<u8>> = (0..h)
        .map(|y| (0..w).map(|x| gray.get_pixel(x, y).0[0]).collect())
        .collect();

    let rows: Vec<Vec<[u8; 4]>> = (1..h - 1)
        .into_par_iter()
        .map(|y| {
            let mut row = Vec::with_capacity(w as usize);
            row.push([0u8, 0, 0, 255]);
            for x in 1..(w - 1) {
                let (xu, yu) = (x as usize, y as usize);
                let gx: i32 = -1 * src[yu - 1][xu - 1] as i32
                    + 1 * src[yu - 1][xu + 1] as i32
                    + -2 * src[yu][xu - 1] as i32
                    + 2 * src[yu][xu + 1] as i32
                    + -1 * src[yu + 1][xu - 1] as i32
                    + 1 * src[yu + 1][xu + 1] as i32;
                let gy: i32 = -1 * src[yu - 1][xu - 1] as i32
                    + -2 * src[yu - 1][xu] as i32
                    + -1 * src[yu - 1][xu + 1] as i32
                    + 1 * src[yu + 1][xu - 1] as i32
                    + 2 * src[yu + 1][xu] as i32
                    + 1 * src[yu + 1][xu + 1] as i32;
                let mag = ((gx * gx + gy * gy) as f64).sqrt().min(255.0) as u8;
                row.push([mag, mag, mag, 255]);
            }
            row.push([0u8, 0, 0, 255]);
            row
        })
        .collect();

    for x in 0..w {
        output.put_pixel(x, 0, Rgba([0, 0, 0, 255]));
        output.put_pixel(x, h - 1, Rgba([0, 0, 0, 255]));
    }
    for (i, row) in rows.iter().enumerate() {
        let y = (i + 1) as u32;
        for (x, px) in row.iter().enumerate() {
            output.put_pixel(x as u32, y, Rgba(*px));
        }
    }

    DynamicImage::ImageRgba8(output)
}

/// Brightness adjustment in the range [-1.0, 1.0].
pub fn adjust_brightness(img: &DynamicImage, value: f32) -> DynamicImage {
    let offset = (value * 255.0) as i16;
    map_rgb(img, |[r, g, b]| {
        [
            (r as i16 + offset).clamp(0, 255) as u8,
            (g as i16 + offset).clamp(0, 255) as u8,
            (b as i16 + offset).clamp(0, 255) as u8,
        ]
    })
}

/// Contrast adjustment in the range [-1.0, 1.0].
pub fn adjust_contrast(img: &DynamicImage, value: f32) -> DynamicImage {
    let factor = (1.0 + value) * (1.0 + value);
    map_rgb(img, |[r, g, b]| {
        let adjust = |v: u8| {
            let v = v as f32 / 255.0;
            (((v - 0.5) * factor + 0.5) * 255.0).clamp(0.0, 255.0) as u8
        };
        [adjust(r), adjust(g), adjust(b)]
    })
}

/// HSL colour adjustment.
///
/// `hue` is a rotation in degrees, `saturation` and `lightness` are offsets
/// in the range [-1.0, 1.0].
pub fn adjust_hsl(
    img: &DynamicImage,
    hue: f32,
    saturation: f32,
    lightness: f32,
) -> DynamicImage {
    map_rgb(img, |[r, g, b]| {
        let (h, s, l) = rgb_to_hsl(r, g, b);
        let new_h = (h + hue).rem_euclid(360.0);
        let new_s = (s + saturation).clamp(0.0, 1.0);
        let new_l = (l + lightness).clamp(0.0, 1.0);
        hsl_to_rgb(new_h, new_s, new_l)
    })
}

fn rgb_to_hsl(r: u8, g: u8, b: u8) -> (f32, f32, f32) {
    let r = r as f32 / 255.0;
    let g = g as f32 / 255.0;
    let b = b as f32 / 255.0;

    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let l = (max + min) / 2.0;

    if (max - min).abs() < f32::EPSILON {
        return (0.0, 0.0, l);
    }

    let d = max - min;
    let s = if l > 0.5 {
        d / (2.0 - max - min)
    } else {
        d / (max + min)
    };

    let h = if (max - r).abs() < f32::EPSILON {
        let mut h = (g - b) / d;
        if g < b {
            h += 6.0;
        }
        h
    } else if (max - g).abs() < f32::EPSILON {
        (b - r) / d + 2.0
    } else {
        (r - g) / d + 4.0
    };

    (h * 60.0, s, l)
}

fn hsl_to_rgb(h: f32, s: f32, l: f32) -> [u8; 3] {
    if s.abs() < f32::EPSILON {
        let v = (l * 255.0).clamp(0.0, 255.0) as u8;
        return [v, v, v];
    }

    let q = if l < 0.5 {
        l * (1.0 + s)
    } else {
        l + s - l * s
    };
    let p = 2.0 * l - q;
    let h_norm = h / 360.0;

    let r = hue_to_rgb(p, q, h_norm + 1.0 / 3.0);
    let g = hue_to_rgb(p, q, h_norm);
    let b = hue_to_rgb(p, q, h_norm - 1.0 / 3.0);

    [
        (r * 255.0).clamp(0.0, 255.0) as u8,
        (g * 255.0).clamp(0.0, 255.0) as u8,
        (b * 255.0).clamp(0.0, 255.0) as u8,
    ]
}

fn hue_to_rgb(p: f32, q: f32, mut t: f32) -> f32 {
    t = t.rem_euclid(1.0);
    if t < 1.0 / 6.0 {
        return p + (q - p) * 6.0 * t;
    }
    if t < 1.0 / 2.0 {
        return q;
    }
    if t < 2.0 / 3.0 {
        return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
    }
    p
}
