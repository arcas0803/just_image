use image::{DynamicImage, ImageBuffer, Rgba};
use rayon::prelude::*;

use crate::pipeline::ArtisticFilter;
use crate::pixel_ops::{lerp_u8, map_rgb};

/// Returns the list of available artistic filter names.
pub fn available_filters() -> Vec<&'static str> {
    ArtisticFilter::ALL.iter().map(|f| f.name()).collect()
}

/// Applies a named artistic filter.
pub fn apply_filter(img: &DynamicImage, filter: ArtisticFilter) -> Result<DynamicImage, String> {
    let result = match filter {
        ArtisticFilter::Vintage => filter_vintage(img),
        ArtisticFilter::Sepia => filter_sepia(img),
        ArtisticFilter::Cool => filter_cool(img),
        ArtisticFilter::Warm => filter_warm(img),
        ArtisticFilter::Marine => filter_marine(img),
        ArtisticFilter::Dramatic => filter_dramatic(img),
        ArtisticFilter::Lomo => filter_lomo(img),
        ArtisticFilter::Retro => filter_retro(img),
        ArtisticFilter::Noir => filter_noir(img),
        ArtisticFilter::Bloom => filter_bloom(img),
        ArtisticFilter::Polaroid => filter_polaroid(img),
        ArtisticFilter::GoldenHour => filter_golden_hour(img),
        ArtisticFilter::Arctic => filter_arctic(img),
        ArtisticFilter::Cinematic => filter_cinematic(img),
        ArtisticFilter::Fade => filter_fade(img),
    };
    Ok(result)
}

// ──────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────

/// Applies a uniform colour tint, leaving alpha untouched.
fn apply_color_tint(img: &DynamicImage, tint: (u8, u8, u8), intensity: f32) -> DynamicImage {
    map_rgb(img, |[r, g, b]| {
        [
            lerp_u8(r, tint.0, intensity),
            lerp_u8(g, tint.1, intensity),
            lerp_u8(b, tint.2, intensity),
        ]
    })
}

/// Applies a radial vignette (darkening from the centre outwards).
fn apply_vignette(img: &DynamicImage, strength: f32) -> DynamicImage {
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let src = rgba.as_raw();
    let mut dst = vec![0u8; src.len()];
    let row_stride = w as usize * 4;
    let cx = w as f32 / 2.0;
    let cy = h as f32 / 2.0;
    let max_dist = (cx * cx + cy * cy).sqrt();

    dst.par_chunks_mut(row_stride)
        .enumerate()
        .for_each(|(y, row)| {
            let off = y * row_stride;
            let dy = y as f32 - cy;
            for x in 0..(w as usize) {
                let dx = x as f32 - cx;
                let dist = (dx * dx + dy * dy).sqrt() / max_dist;
                let factor = 1.0 - (dist * strength).clamp(0.0, 1.0);
                let i = x * 4;
                row[i] = (src[off + i] as f32 * factor).clamp(0.0, 255.0) as u8;
                row[i + 1] = (src[off + i + 1] as f32 * factor).clamp(0.0, 255.0) as u8;
                row[i + 2] = (src[off + i + 2] as f32 * factor).clamp(0.0, 255.0) as u8;
                row[i + 3] = src[off + i + 3];
            }
        });

    ImageBuffer::<Rgba<u8>, Vec<u8>>::from_raw(w, h, dst)
        .map(DynamicImage::ImageRgba8)
        .expect("buffer size matches image dimensions")
}

/// Adjusts brightness, leaving alpha untouched.
fn adjust_brightness_raw(img: &DynamicImage, offset: f32) -> DynamicImage {
    let off_i = (offset * 255.0) as i16;
    map_rgb(img, |[r, g, b]| {
        [
            (r as i16 + off_i).clamp(0, 255) as u8,
            (g as i16 + off_i).clamp(0, 255) as u8,
            (b as i16 + off_i).clamp(0, 255) as u8,
        ]
    })
}

/// Adjusts contrast, leaving alpha untouched.
fn adjust_contrast_raw(img: &DynamicImage, value: f32) -> DynamicImage {
    let factor = (1.0 + value) * (1.0 + value);
    map_rgb(img, |[r, g, b]| {
        let adjust = |v: u8| {
            let v = v as f32 / 255.0;
            (((v - 0.5) * factor + 0.5) * 255.0).clamp(0.0, 255.0) as u8
        };
        [adjust(r), adjust(g), adjust(b)]
    })
}

/// Adjusts saturation in [-1.0, 1.0]; -1 = greyscale, +1 = double saturation.
fn adjust_saturation(img: &DynamicImage, value: f32) -> DynamicImage {
    let factor = 1.0 + value;
    map_rgb(img, |[r, g, b]| {
        let gray = 0.299 * r as f32 + 0.587 * g as f32 + 0.114 * b as f32;
        [
            (gray + (r as f32 - gray) * factor).clamp(0.0, 255.0) as u8,
            (gray + (g as f32 - gray) * factor).clamp(0.0, 255.0) as u8,
            (gray + (b as f32 - gray) * factor).clamp(0.0, 255.0) as u8,
        ]
    })
}

/// Applies a gamma curve, leaving alpha untouched.
fn apply_gamma(img: &DynamicImage, gamma: f32) -> DynamicImage {
    let inv_gamma = 1.0 / gamma;
    let mut lut = [0u8; 256];
    for i in 0..256 {
        lut[i] = ((i as f32 / 255.0).powf(inv_gamma) * 255.0).clamp(0.0, 255.0) as u8;
    }
    map_rgb(img, |[r, g, b]| [lut[r as usize], lut[g as usize], lut[b as usize]])
}

/// Adjusts individual RGB channels, leaving alpha untouched.
fn adjust_channels(
    img: &DynamicImage,
    r_mul: f32,
    g_mul: f32,
    b_mul: f32,
) -> DynamicImage {
    map_rgb(img, |[r, g, b]| {
        [
            (r as f32 * r_mul).clamp(0.0, 255.0) as u8,
            (g as f32 * g_mul).clamp(0.0, 255.0) as u8,
            (b as f32 * b_mul).clamp(0.0, 255.0) as u8,
        ]
    })
}

/// Soft-light blend of a colour over the image.
fn soft_light_blend(img: &DynamicImage, color: (u8, u8, u8), intensity: f32) -> DynamicImage {
    let cr = color.0 as f32 / 255.0;
    let cg = color.1 as f32 / 255.0;
    let cb = color.2 as f32 / 255.0;

    map_rgb(img, |[r, g, b]| {
        let blend_channel = |base: u8, blend: f32| {
            let base = base as f32 / 255.0;
            let result = if blend < 0.5 {
                base - (1.0 - 2.0 * blend) * base * (1.0 - base)
            } else {
                let d = if base <= 0.25 {
                    ((16.0 * base - 12.0) * base + 4.0) * base
                } else {
                    base.sqrt()
                };
                base + (2.0 * blend - 1.0) * (d - base)
            };
            let mixed = base * (1.0 - intensity) + result * intensity;
            (mixed * 255.0).clamp(0.0, 255.0) as u8
        };
        [
            blend_channel(r, cr),
            blend_channel(g, cg),
            blend_channel(b, cb),
        ]
    })
}

// ──────────────────────────────────────────────
// Artistic filters
// ──────────────────────────────────────────────

fn filter_vintage(img: &DynamicImage) -> DynamicImage {
    let img = adjust_saturation(img, -0.3);
    let img = adjust_contrast_raw(&img, 0.1);
    let img = apply_color_tint(&img, (240, 200, 140), 0.15);
    let img = apply_gamma(&img, 1.1);
    apply_vignette(&img, 0.6)
}

fn filter_sepia(img: &DynamicImage) -> DynamicImage {
    map_rgb(img, |[r, g, b]| {
        [
            (0.393 * r as f32 + 0.769 * g as f32 + 0.189 * b as f32).clamp(0.0, 255.0) as u8,
            (0.349 * r as f32 + 0.686 * g as f32 + 0.168 * b as f32).clamp(0.0, 255.0) as u8,
            (0.272 * r as f32 + 0.534 * g as f32 + 0.131 * b as f32).clamp(0.0, 255.0) as u8,
        ]
    })
}

fn filter_cool(img: &DynamicImage) -> DynamicImage {
    let img = adjust_channels(img, 0.9, 0.95, 1.15);
    let img = adjust_brightness_raw(&img, 0.03);
    adjust_contrast_raw(&img, 0.05)
}

fn filter_warm(img: &DynamicImage) -> DynamicImage {
    let img = adjust_channels(img, 1.12, 1.0, 0.88);
    let img = adjust_saturation(&img, 0.15);
    adjust_brightness_raw(&img, 0.02)
}

fn filter_marine(img: &DynamicImage) -> DynamicImage {
    let img = adjust_channels(img, 0.85, 1.05, 1.15);
    let img = adjust_saturation(&img, 0.1);
    apply_color_tint(&img, (0, 120, 180), 0.08)
}

fn filter_dramatic(img: &DynamicImage) -> DynamicImage {
    let img = adjust_contrast_raw(img, 0.4);
    let img = adjust_brightness_raw(&img, -0.05);
    let img = adjust_saturation(&img, 0.15);
    apply_vignette(&img, 0.8)
}

fn filter_lomo(img: &DynamicImage) -> DynamicImage {
    let img = adjust_saturation(img, 0.4);
    let img = adjust_contrast_raw(&img, 0.3);
    let img = adjust_channels(&img, 1.05, 1.0, 0.95);
    apply_vignette(&img, 1.0)
}

fn filter_retro(img: &DynamicImage) -> DynamicImage {
    let img = adjust_saturation(img, -0.25);
    let img = adjust_brightness_raw(&img, 0.05);
    let img = apply_color_tint(&img, (255, 180, 180), 0.1);
    apply_gamma(&img, 1.05)
}

fn filter_noir(img: &DynamicImage) -> DynamicImage {
    let img = adjust_saturation(img, -1.0);
    let img = adjust_contrast_raw(&img, 0.3);
    apply_gamma(&img, 0.9)
}

fn filter_bloom(img: &DynamicImage) -> DynamicImage {
    let img = adjust_brightness_raw(img, 0.08);
    let img = adjust_saturation(&img, -0.15);
    let img = adjust_contrast_raw(&img, -0.1);
    soft_light_blend(&img, (255, 240, 230), 0.2)
}

fn filter_polaroid(img: &DynamicImage) -> DynamicImage {
    let img = adjust_saturation(img, -0.1);
    let img = adjust_contrast_raw(&img, 0.05);
    let img = apply_color_tint(&img, (230, 230, 180), 0.08);
    adjust_brightness_raw(&img, 0.03)
}

fn filter_golden_hour(img: &DynamicImage) -> DynamicImage {
    let img = adjust_channels(img, 1.15, 1.05, 0.85);
    let img = adjust_saturation(&img, 0.2);
    let img = soft_light_blend(&img, (255, 200, 100), 0.15);
    apply_gamma(&img, 1.05)
}

fn filter_arctic(img: &DynamicImage) -> DynamicImage {
    let img = adjust_channels(img, 0.85, 0.95, 1.2);
    let img = adjust_brightness_raw(&img, 0.08);
    let img = adjust_saturation(&img, -0.15);
    adjust_contrast_raw(&img, 0.05)
}

fn filter_cinematic(img: &DynamicImage) -> DynamicImage {
    let img = map_rgb(img, |[r, g, b]| {
        let r_f = r as f32 / 255.0;
        let g_f = g as f32 / 255.0;
        let b_f = b as f32 / 255.0;
        let lum = 0.299 * r_f + 0.587 * g_f + 0.114 * b_f;

        let teal = (0.0_f32, 0.5_f32, 0.5_f32);
        let orange = (1.0_f32, 0.65_f32, 0.0_f32);
        let strength = 0.12;

        let tone = |t: f32, o: f32| t * (1.0 - lum) + o * lum;
        let mix = |base: f32, tone: f32| {
            ((base * (1.0 - strength) + tone * strength) * 255.0).clamp(0.0, 255.0) as u8
        };

        [
            mix(r_f, tone(teal.0, orange.0)),
            mix(g_f, tone(teal.1, orange.1)),
            mix(b_f, tone(teal.2, orange.2)),
        ]
    });
    let img = adjust_contrast_raw(&img, 0.15);
    apply_vignette(&img, 0.4)
}

fn filter_fade(img: &DynamicImage) -> DynamicImage {
    let lift = 30i16;
    let img = map_rgb(img, |[r, g, b]| {
        [
            (r as i16 + lift).clamp(0, 255) as u8,
            (g as i16 + lift).clamp(0, 255) as u8,
            (b as i16 + lift).clamp(0, 255) as u8,
        ]
    });
    let img = adjust_contrast_raw(&img, -0.15);
    adjust_saturation(&img, -0.2)
}
