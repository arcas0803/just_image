use image::{DynamicImage, ImageBuffer, Rgba};
use rayon::prelude::*;

/// Aplica una marca de agua (overlay) con canal alfa sobre la imagen base.
/// `watermark_data` son los bytes raw de la imagen de watermark (se decodifica).
/// `x`, `y` posición del overlay. `opacity` en [0.0, 1.0].
pub fn apply_watermark(
    base: &DynamicImage,
    watermark_data: &[u8],
    x: i32,
    y: i32,
    opacity: f32,
) -> Result<DynamicImage, String> {
    let watermark = image::load_from_memory(watermark_data)
        .map_err(|e| format!("Failed to decode watermark: {e}"))?;

    let base_rgba = base.to_rgba8();
    let wm_rgba = watermark.to_rgba8();
    let (base_w, base_h) = base_rgba.dimensions();
    let (wm_w, wm_h) = wm_rgba.dimensions();

    let opacity = opacity.clamp(0.0, 1.0);

    let base_raw = base_rgba.as_raw().clone();
    let wm_raw = wm_rgba.as_raw().clone();

    let mut output = base_raw;

    // Procesar filas que se solapan en paralelo
    let y_start = y.max(0) as u32;
    let y_end = ((y + wm_h as i32) as u32).min(base_h);

    let row_stride = base_w as usize * 4;

    output
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

            let x_start = x.max(0) as u32;
            let x_end = ((x + wm_w as i32) as u32).min(base_w);

            for bx in x_start..x_end {
                let wm_x = (bx as i32 - x) as u32;
                if wm_x >= wm_w {
                    continue;
                }

                let base_idx = (bx as usize) * 4;
                let wm_idx = ((wm_y * wm_w + wm_x) as usize) * 4;

                let wm_a = wm_raw[wm_idx + 3] as f32 / 255.0 * opacity;
                let inv_a = 1.0 - wm_a;

                for c in 0..3 {
                    let base_c = row[base_idx + c] as f32;
                    let wm_c = wm_raw[wm_idx + c] as f32;
                    row[base_idx + c] = (base_c * inv_a + wm_c * wm_a).clamp(0.0, 255.0) as u8;
                }
                // Alpha: combinar
                let base_a = row[base_idx + 3] as f32 / 255.0;
                let out_a = wm_a + base_a * inv_a;
                row[base_idx + 3] = (out_a * 255.0).clamp(0.0, 255.0) as u8;
            }
        });

    let img_buf = ImageBuffer::<Rgba<u8>, Vec<u8>>::from_raw(base_w, base_h, output)
        .ok_or_else(|| "Failed to create output buffer".to_string())?;

    Ok(DynamicImage::ImageRgba8(img_buf))
}
