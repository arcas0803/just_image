use image::{DynamicImage, ImageBuffer};
use rayon::prelude::*;

/// Lista de filtros artísticos disponibles.
pub fn available_filters() -> Vec<&'static str> {
    vec![
        "vintage",
        "sepia",
        "cool",
        "warm",
        "marine",
        "dramatic",
        "lomo",
        "retro",
        "noir",
        "bloom",
        "polaroid",
        "golden_hour",
        "arctic",
        "cinematic",
        "fade",
    ]
}

/// Aplica un filtro artístico predefinido por nombre.
pub fn apply_filter(img: &DynamicImage, name: &str) -> Result<DynamicImage, String> {
    match name.to_lowercase().as_str() {
        "vintage" => Ok(filter_vintage(img)),
        "sepia" => Ok(filter_sepia(img)),
        "cool" => Ok(filter_cool(img)),
        "warm" => Ok(filter_warm(img)),
        "marine" => Ok(filter_marine(img)),
        "dramatic" => Ok(filter_dramatic(img)),
        "lomo" => Ok(filter_lomo(img)),
        "retro" => Ok(filter_retro(img)),
        "noir" => Ok(filter_noir(img)),
        "bloom" => Ok(filter_bloom(img)),
        "polaroid" => Ok(filter_polaroid(img)),
        "golden_hour" => Ok(filter_golden_hour(img)),
        "arctic" => Ok(filter_arctic(img)),
        "cinematic" => Ok(filter_cinematic(img)),
        "fade" => Ok(filter_fade(img)),
        _ => Err(format!(
            "Unknown filter: '{}'. Available: {}",
            name,
            available_filters().join(", ")
        )),
    }
}

// ──────────────────────────────────────────────
// Helpers internos
// ──────────────────────────────────────────────

/// Aplica un tinte de color uniforme con intensidad dada.
/// `tint` es (r, g, b) en [0, 255], `intensity` en [0.0, 1.0].
fn apply_color_tint(img: &DynamicImage, tint: (u8, u8, u8), intensity: f32) -> DynamicImage {
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let src = rgba.as_raw();
    let mut dst = vec![0u8; src.len()];
    let inv = 1.0 - intensity;

    dst.par_chunks_mut(w as usize * 4)
        .enumerate()
        .for_each(|(y, row)| {
            let off = y * w as usize * 4;
            for i in (0..row.len()).step_by(4) {
                row[i] = (src[off + i] as f32 * inv + tint.0 as f32 * intensity)
                    .clamp(0.0, 255.0) as u8;
                row[i + 1] = (src[off + i + 1] as f32 * inv + tint.1 as f32 * intensity)
                    .clamp(0.0, 255.0) as u8;
                row[i + 2] = (src[off + i + 2] as f32 * inv + tint.2 as f32 * intensity)
                    .clamp(0.0, 255.0) as u8;
                row[i + 3] = src[off + i + 3];
            }
        });

    let buf = ImageBuffer::from_raw(w, h, dst).unwrap();
    DynamicImage::ImageRgba8(buf)
}

/// Aplica un efecto de viñeta (oscurecimiento radial desde el centro).
fn apply_vignette(img: &DynamicImage, strength: f32) -> DynamicImage {
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let src = rgba.as_raw();
    let mut dst = vec![0u8; src.len()];
    let cx = w as f32 / 2.0;
    let cy = h as f32 / 2.0;
    let max_dist = (cx * cx + cy * cy).sqrt();

    dst.par_chunks_mut(w as usize * 4)
        .enumerate()
        .for_each(|(y, row)| {
            let off = y * w as usize * 4;
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

    let buf = ImageBuffer::from_raw(w, h, dst).unwrap();
    DynamicImage::ImageRgba8(buf)
}

/// Ajusta brillo de cada pixel.
fn adjust_brightness_raw(img: &DynamicImage, offset: f32) -> DynamicImage {
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let off_i = (offset * 255.0) as i16;
    let src = rgba.as_raw();
    let mut dst = vec![0u8; src.len()];

    dst.par_chunks_mut(w as usize * 4)
        .enumerate()
        .for_each(|(y, row)| {
            let s = y * w as usize * 4;
            for i in (0..row.len()).step_by(4) {
                row[i] = (src[s + i] as i16 + off_i).clamp(0, 255) as u8;
                row[i + 1] = (src[s + i + 1] as i16 + off_i).clamp(0, 255) as u8;
                row[i + 2] = (src[s + i + 2] as i16 + off_i).clamp(0, 255) as u8;
                row[i + 3] = src[s + i + 3];
            }
        });

    let buf = ImageBuffer::from_raw(w, h, dst).unwrap();
    DynamicImage::ImageRgba8(buf)
}

/// Ajusta contraste.
fn adjust_contrast_raw(img: &DynamicImage, value: f32) -> DynamicImage {
    let factor = (1.0 + value) * (1.0 + value);
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let src = rgba.as_raw();
    let mut dst = vec![0u8; src.len()];

    dst.par_chunks_mut(w as usize * 4)
        .enumerate()
        .for_each(|(y, row)| {
            let s = y * w as usize * 4;
            for i in (0..row.len()).step_by(4) {
                for c in 0..3 {
                    let v = src[s + i + c] as f32 / 255.0;
                    let adj = ((v - 0.5) * factor + 0.5) * 255.0;
                    row[i + c] = adj.clamp(0.0, 255.0) as u8;
                }
                row[i + 3] = src[s + i + 3];
            }
        });

    let buf = ImageBuffer::from_raw(w, h, dst).unwrap();
    DynamicImage::ImageRgba8(buf)
}

/// Ajusta saturación. value en [-1.0, 1.0]. -1 = greyscale, +1 = doble saturación.
fn adjust_saturation(img: &DynamicImage, value: f32) -> DynamicImage {
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let src = rgba.as_raw();
    let mut dst = vec![0u8; src.len()];
    let factor = 1.0 + value;

    dst.par_chunks_mut(w as usize * 4)
        .enumerate()
        .for_each(|(y, row)| {
            let s = y * w as usize * 4;
            for i in (0..row.len()).step_by(4) {
                let r = src[s + i] as f32;
                let g = src[s + i + 1] as f32;
                let b = src[s + i + 2] as f32;
                let gray = 0.299 * r + 0.587 * g + 0.114 * b;
                row[i] = (gray + (r - gray) * factor).clamp(0.0, 255.0) as u8;
                row[i + 1] = (gray + (g - gray) * factor).clamp(0.0, 255.0) as u8;
                row[i + 2] = (gray + (b - gray) * factor).clamp(0.0, 255.0) as u8;
                row[i + 3] = src[s + i + 3];
            }
        });

    let buf = ImageBuffer::from_raw(w, h, dst).unwrap();
    DynamicImage::ImageRgba8(buf)
}

/// Aplica una curva de tono (gamma) a cada canal.
fn apply_gamma(img: &DynamicImage, gamma: f32) -> DynamicImage {
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let src = rgba.as_raw();
    let mut dst = vec![0u8; src.len()];
    let inv_gamma = 1.0 / gamma;

    // Pre-computar LUT de 256 entradas
    let mut lut = [0u8; 256];
    for i in 0..256 {
        lut[i] = ((i as f32 / 255.0).powf(inv_gamma) * 255.0).clamp(0.0, 255.0) as u8;
    }

    dst.par_chunks_mut(w as usize * 4)
        .enumerate()
        .for_each(|(y, row)| {
            let s = y * w as usize * 4;
            for i in (0..row.len()).step_by(4) {
                row[i] = lut[src[s + i] as usize];
                row[i + 1] = lut[src[s + i + 1] as usize];
                row[i + 2] = lut[src[s + i + 2] as usize];
                row[i + 3] = src[s + i + 3];
            }
        });

    let buf = ImageBuffer::from_raw(w, h, dst).unwrap();
    DynamicImage::ImageRgba8(buf)
}

/// Ajusta canales RGB con multiplicadores individuales.
fn adjust_channels(img: &DynamicImage, r_mul: f32, g_mul: f32, b_mul: f32) -> DynamicImage {
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let src = rgba.as_raw();
    let mut dst = vec![0u8; src.len()];

    dst.par_chunks_mut(w as usize * 4)
        .enumerate()
        .for_each(|(y, row)| {
            let s = y * w as usize * 4;
            for i in (0..row.len()).step_by(4) {
                row[i] = (src[s + i] as f32 * r_mul).clamp(0.0, 255.0) as u8;
                row[i + 1] = (src[s + i + 1] as f32 * g_mul).clamp(0.0, 255.0) as u8;
                row[i + 2] = (src[s + i + 2] as f32 * b_mul).clamp(0.0, 255.0) as u8;
                row[i + 3] = src[s + i + 3];
            }
        });

    let buf = ImageBuffer::from_raw(w, h, dst).unwrap();
    DynamicImage::ImageRgba8(buf)
}

/// Soft light blending: mezcla suave de un color sobre la imagen.
fn soft_light_blend(img: &DynamicImage, color: (u8, u8, u8), intensity: f32) -> DynamicImage {
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let src = rgba.as_raw();
    let mut dst = vec![0u8; src.len()];
    let cr = color.0 as f32 / 255.0;
    let cg = color.1 as f32 / 255.0;
    let cb = color.2 as f32 / 255.0;

    dst.par_chunks_mut(w as usize * 4)
        .enumerate()
        .for_each(|(y, row)| {
            let s = y * w as usize * 4;
            for i in (0..row.len()).step_by(4) {
                let channels = [
                    (src[s + i] as f32 / 255.0, cr),
                    (src[s + i + 1] as f32 / 255.0, cg),
                    (src[s + i + 2] as f32 / 255.0, cb),
                ];
                for (c, &(base, blend)) in channels.iter().enumerate() {
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
                    row[i + c] = (mixed * 255.0).clamp(0.0, 255.0) as u8;
                }
                row[i + 3] = src[s + i + 3];
            }
        });

    let buf = ImageBuffer::from_raw(w, h, dst).unwrap();
    DynamicImage::ImageRgba8(buf)
}

// ──────────────────────────────────────────────
// Filtros artísticos
// ──────────────────────────────────────────────

/// Vintage: tonos cálidos desaturados con viñeta suave.
fn filter_vintage(img: &DynamicImage) -> DynamicImage {
    let img = adjust_saturation(img, -0.3);
    let img = adjust_contrast_raw(&img, 0.1);
    let img = apply_color_tint(&img, (240, 200, 140), 0.15);
    let img = apply_gamma(&img, 1.1);
    apply_vignette(&img, 0.6)
}

/// Sepia: tono marrón clásico.
fn filter_sepia(img: &DynamicImage) -> DynamicImage {
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let src = rgba.as_raw();
    let mut dst = vec![0u8; src.len()];

    dst.par_chunks_mut(w as usize * 4)
        .enumerate()
        .for_each(|(y, row)| {
            let s = y * w as usize * 4;
            for i in (0..row.len()).step_by(4) {
                let r = src[s + i] as f32;
                let g = src[s + i + 1] as f32;
                let b = src[s + i + 2] as f32;
                row[i] = (0.393 * r + 0.769 * g + 0.189 * b).clamp(0.0, 255.0) as u8;
                row[i + 1] = (0.349 * r + 0.686 * g + 0.168 * b).clamp(0.0, 255.0) as u8;
                row[i + 2] = (0.272 * r + 0.534 * g + 0.131 * b).clamp(0.0, 255.0) as u8;
                row[i + 3] = src[s + i + 3];
            }
        });

    let buf = ImageBuffer::from_raw(w, h, dst).unwrap();
    DynamicImage::ImageRgba8(buf)
}

/// Cool: tonos azulados fríos, sombras ligeramente elevadas.
fn filter_cool(img: &DynamicImage) -> DynamicImage {
    let img = adjust_channels(img, 0.9, 0.95, 1.15);
    let img = adjust_brightness_raw(&img, 0.03);
    adjust_contrast_raw(&img, 0.05)
}

/// Warm: realce cálido con tonos dorados.
fn filter_warm(img: &DynamicImage) -> DynamicImage {
    let img = adjust_channels(img, 1.12, 1.0, 0.88);
    let img = adjust_saturation(&img, 0.15);
    adjust_brightness_raw(&img, 0.02)
}

/// Marine: tonos acuáticos azul-verdosos.
fn filter_marine(img: &DynamicImage) -> DynamicImage {
    let img = adjust_channels(img, 0.85, 1.05, 1.15);
    let img = adjust_saturation(&img, 0.1);
    apply_color_tint(&img, (0, 120, 180), 0.08)
}

/// Dramatic: alto contraste con sombras profundas.
fn filter_dramatic(img: &DynamicImage) -> DynamicImage {
    let img = adjust_contrast_raw(img, 0.4);
    let img = adjust_brightness_raw(&img, -0.05);
    let img = adjust_saturation(&img, 0.15);
    apply_vignette(&img, 0.8)
}

/// Lomo: colores saturados, viñeta fuerte, contraste alto.
fn filter_lomo(img: &DynamicImage) -> DynamicImage {
    let img = adjust_saturation(img, 0.4);
    let img = adjust_contrast_raw(&img, 0.3);
    let img = adjust_channels(&img, 1.05, 1.0, 0.95);
    apply_vignette(&img, 1.0)
}

/// Retro: tonos pastel desaturados con tinte rosado.
fn filter_retro(img: &DynamicImage) -> DynamicImage {
    let img = adjust_saturation(img, -0.25);
    let img = adjust_brightness_raw(&img, 0.05);
    let img = apply_color_tint(&img, (255, 180, 180), 0.1);
    apply_gamma(&img, 1.05)
}

/// Noir: blanco y negro con contraste alto.
fn filter_noir(img: &DynamicImage) -> DynamicImage {
    let img = adjust_saturation(img, -1.0);
    let img = adjust_contrast_raw(&img, 0.3);
    apply_gamma(&img, 0.9)
}

/// Bloom: aspecto soñador con brillo suave y desaturación ligera.
fn filter_bloom(img: &DynamicImage) -> DynamicImage {
    let img = adjust_brightness_raw(img, 0.08);
    let img = adjust_saturation(&img, -0.15);
    let img = adjust_contrast_raw(&img, -0.1);
    soft_light_blend(&img, (255, 240, 230), 0.2)
}

/// Polaroid: tonos ligeramente verdes/amarillentos, contraste suave.
fn filter_polaroid(img: &DynamicImage) -> DynamicImage {
    let img = adjust_saturation(img, -0.1);
    let img = adjust_contrast_raw(&img, 0.05);
    let img = apply_color_tint(&img, (230, 230, 180), 0.08);
    adjust_brightness_raw(&img, 0.03)
}

/// Golden Hour: luz dorada cálida del atardecer.
fn filter_golden_hour(img: &DynamicImage) -> DynamicImage {
    let img = adjust_channels(img, 1.15, 1.05, 0.85);
    let img = adjust_saturation(&img, 0.2);
    let img = soft_light_blend(&img, (255, 200, 100), 0.15);
    apply_gamma(&img, 1.05)
}

/// Arctic: tonos azules gélidos con alto brillo.
fn filter_arctic(img: &DynamicImage) -> DynamicImage {
    let img = adjust_channels(img, 0.85, 0.95, 1.2);
    let img = adjust_brightness_raw(&img, 0.08);
    let img = adjust_saturation(&img, -0.15);
    adjust_contrast_raw(&img, 0.05)
}

/// Cinematic: look de película con teal en sombras y naranja en luces.
fn filter_cinematic(img: &DynamicImage) -> DynamicImage {
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let src = rgba.as_raw();
    let mut dst = vec![0u8; src.len()];

    dst.par_chunks_mut(w as usize * 4)
        .enumerate()
        .for_each(|(y, row)| {
            let s = y * w as usize * 4;
            for i in (0..row.len()).step_by(4) {
                let r = src[s + i] as f32 / 255.0;
                let g = src[s + i + 1] as f32 / 255.0;
                let b = src[s + i + 2] as f32 / 255.0;
                let lum = 0.299 * r + 0.587 * g + 0.114 * b;

                // Teal (0, 128, 128) en sombras, naranja (255, 165, 0) en luces
                let teal = (0.0_f32, 0.5_f32, 0.5_f32);
                let orange = (1.0_f32, 0.65_f32, 0.0_f32);
                let strength = 0.12;

                let tone_r = teal.0 * (1.0 - lum) + orange.0 * lum;
                let tone_g = teal.1 * (1.0 - lum) + orange.1 * lum;
                let tone_b = teal.2 * (1.0 - lum) + orange.2 * lum;

                row[i] = ((r * (1.0 - strength) + tone_r * strength) * 255.0)
                    .clamp(0.0, 255.0) as u8;
                row[i + 1] = ((g * (1.0 - strength) + tone_g * strength) * 255.0)
                    .clamp(0.0, 255.0) as u8;
                row[i + 2] = ((b * (1.0 - strength) + tone_b * strength) * 255.0)
                    .clamp(0.0, 255.0) as u8;
                row[i + 3] = src[s + i + 3];
            }
        });

    let buf = ImageBuffer::from_raw(w, h, dst).unwrap();
    let img = DynamicImage::ImageRgba8(buf);
    let img = adjust_contrast_raw(&img, 0.15);
    apply_vignette(&img, 0.4)
}

/// Fade: sombras elevadas, aspecto desvanecido mate.
fn filter_fade(img: &DynamicImage) -> DynamicImage {
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let src = rgba.as_raw();
    let mut dst = vec![0u8; src.len()];
    let lift = 30i16; // Elevar sombras

    dst.par_chunks_mut(w as usize * 4)
        .enumerate()
        .for_each(|(y, row)| {
            let s = y * w as usize * 4;
            for i in (0..row.len()).step_by(4) {
                for c in 0..3 {
                    let v = src[s + i + c] as i16;
                    row[i + c] = (v + lift).clamp(0, 255) as u8;
                }
                row[i + 3] = src[s + i + 3];
            }
        });

    let buf = ImageBuffer::from_raw(w, h, dst).unwrap();
    let img = DynamicImage::ImageRgba8(buf);
    let img = adjust_contrast_raw(&img, -0.15);
    adjust_saturation(&img, -0.2)
}
