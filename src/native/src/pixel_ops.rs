//! Low-level pixel manipulation helpers.
//!
//! These helpers centralise the repetitive `to_rgba8 -> parallel rows ->
//! ImageBuffer` pattern used by effects and filters.

use image::{DynamicImage, ImageBuffer, Rgba};
use rayon::prelude::*;

/// Applies a per-pixel transformation to an RGBA image in parallel.
///
/// The alpha channel is transformed like any other channel. For operations
/// that should leave alpha untouched, use [`map_rgb`].
pub fn map_rgba<F>(img: &DynamicImage, f: F) -> DynamicImage
where
    F: Fn([u8; 4]) -> [u8; 4] + Sync + Send,
{
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let src = rgba.as_raw();
    let mut dst = vec![0u8; src.len()];
    let row_stride = w as usize * 4;

    dst.par_chunks_mut(row_stride)
        .enumerate()
        .for_each(|(y, row)| {
            let off = y * row_stride;
            for i in (0..row.len()).step_by(4) {
                let px = [src[off + i], src[off + i + 1], src[off + i + 2], src[off + i + 3]];
                let out = f(px);
                row[i..i + 4].copy_from_slice(&out);
            }
        });

    ImageBuffer::<Rgba<u8>, Vec<u8>>::from_raw(w, h, dst)
        .map(DynamicImage::ImageRgba8)
        .expect("buffer size matches image dimensions")
}

/// Applies a per-pixel transformation to the RGB channels, leaving alpha
/// untouched.
pub fn map_rgb<F>(img: &DynamicImage, f: F) -> DynamicImage
where
    F: Fn([u8; 3]) -> [u8; 3] + Sync + Send,
{
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let src = rgba.as_raw();
    let mut dst = vec![0u8; src.len()];
    let row_stride = w as usize * 4;

    dst.par_chunks_mut(row_stride)
        .enumerate()
        .for_each(|(y, row)| {
            let off = y * row_stride;
            for i in (0..row.len()).step_by(4) {
                let rgb = f([src[off + i], src[off + i + 1], src[off + i + 2]]);
                row[i] = rgb[0];
                row[i + 1] = rgb[1];
                row[i + 2] = rgb[2];
                row[i + 3] = src[off + i + 3];
            }
        });

    ImageBuffer::<Rgba<u8>, Vec<u8>>::from_raw(w, h, dst)
        .map(DynamicImage::ImageRgba8)
        .expect("buffer size matches image dimensions")
}

/// Linearly interpolates two byte values.
#[inline]
pub fn lerp_u8(a: u8, b: u8, t: f32) -> u8 {
    (a as f32 * (1.0 - t) + b as f32 * t).clamp(0.0, 255.0) as u8
}

/// Blends two RGBA pixels using alpha compositing (source-over).
#[inline]
pub fn blend_pixels(base: [u8; 4], over: [u8; 4], opacity: f32) -> [u8; 4] {
    let over_a = over[3] as f32 / 255.0 * opacity;
    if over_a <= 0.0 {
        return base;
    }
    let inv_a = 1.0 - over_a;
    let base_a = base[3] as f32 / 255.0;
    let out_a = over_a + base_a * inv_a;

    let blend = |b, o| (b as f32 * inv_a + o as f32 * over_a) / out_a;
    [
        blend(base[0], over[0]).clamp(0.0, 255.0) as u8,
        blend(base[1], over[1]).clamp(0.0, 255.0) as u8,
        blend(base[2], over[2]).clamp(0.0, 255.0) as u8,
        (out_a * 255.0).clamp(0.0, 255.0) as u8,
    ]
}
