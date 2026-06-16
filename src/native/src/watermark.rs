use image::DynamicImage;
use rayon::prelude::*;

use crate::pixel_ops::blend_pixels;

/// Overlays a watermark image onto the base image with the given position
/// and opacity.
pub fn apply_watermark(
    base: &DynamicImage,
    watermark_data: &[u8],
    x: i32,
    y: i32,
    opacity: f32,
) -> Result<DynamicImage, String> {
    let watermark = image::load_from_memory(watermark_data)
        .map_err(|e| format!("Failed to decode watermark: {e}"))?;

    let mut base_rgba = base.to_rgba8();
    let wm_rgba = watermark.to_rgba8();
    let (base_w, base_h) = base_rgba.dimensions();
    let (wm_w, wm_h) = wm_rgba.dimensions();

    if wm_w == 0 || wm_h == 0 {
        return Ok(DynamicImage::ImageRgba8(base_rgba));
    }

    let opacity = opacity.clamp(0.0, 1.0);
    let wm_raw = wm_rgba.as_raw();
    let row_stride = base_w as usize * 4;

    let y_start = y.max(0) as u32;
    let y_end = ((y + wm_h as i32) as u32).min(base_h);
    let x_start = x.max(0) as u32;
    let x_end = ((x + wm_w as i32) as u32).min(base_w);

    base_rgba
        .par_chunks_mut(row_stride)
        .enumerate()
        .for_each(|(row_idx, row)| {
            let row_y = row_idx as u32;
            if row_y < y_start || row_y >= y_end {
                return;
            }

            let wm_y = (row_y as i32 - y) as u32;
            if wm_y >= wm_h {
                return;
            }

            for bx in x_start..x_end {
                let wm_x = (bx as i32 - x) as u32;
                if wm_x >= wm_w {
                    continue;
                }

                let base_idx = (bx as usize) * 4;
                let wm_idx = ((wm_y * wm_w + wm_x) as usize) * 4;

                let base_px = [
                    row[base_idx],
                    row[base_idx + 1],
                    row[base_idx + 2],
                    row[base_idx + 3],
                ];
                let wm_px = [
                    wm_raw[wm_idx],
                    wm_raw[wm_idx + 1],
                    wm_raw[wm_idx + 2],
                    wm_raw[wm_idx + 3],
                ];

                let blended = blend_pixels(base_px, wm_px, opacity);
                row[base_idx..base_idx + 4].copy_from_slice(&blended);
            }
        });

    Ok(DynamicImage::ImageRgba8(base_rgba))
}
