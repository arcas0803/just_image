use image::{DynamicImage, ImageBuffer, Rgba};
use rayon::prelude::*;

/// Gaussian Blur con sigma dinámico usando kernel separable para rendimiento.
pub fn gaussian_blur(img: &DynamicImage, sigma: f32) -> DynamicImage {
    // Usamos el blur integrado de la crate image que soporta SIMD
    DynamicImage::ImageRgba8(image::imageops::blur(img, sigma))
}

/// Unsharp Mask (sharpen): original + amount * (original - blurred)
pub fn unsharp_mask(img: &DynamicImage, amount: f32, threshold: f32) -> DynamicImage {
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let blurred_rgba = image::imageops::blur(img, 1.0);

    let mut output = ImageBuffer::<Rgba<u8>, Vec<u8>>::new(w, h);

    // Procesar filas en paralelo con rayon
    let src_chunks: Vec<&[u8]> = rgba.chunks(w as usize * 4).collect();
    let blur_chunks: Vec<&[u8]> = blurred_rgba.chunks(w as usize * 4).collect();
    let mut out_rows: Vec<Vec<u8>> = vec![vec![0u8; w as usize * 4]; h as usize];

    out_rows.par_iter_mut().enumerate().for_each(|(y, row)| {
        for x in 0..(w as usize) {
            for c in 0..4usize {
                let idx = x * 4 + c;
                let orig = src_chunks[y][idx] as f32;
                let blur_val = blur_chunks[y][idx] as f32;
                let diff = (orig - blur_val).abs();
                if diff > threshold {
                    let val = orig + amount * (orig - blur_val);
                    row[idx] = val.clamp(0.0, 255.0) as u8;
                } else {
                    row[idx] = src_chunks[y][idx];
                }
            }
        }
    });

    for (y, row) in out_rows.iter().enumerate() {
        for x in 0..(w as usize) {
            let idx = x * 4;
            output.put_pixel(
                x as u32,
                y as u32,
                Rgba([row[idx], row[idx + 1], row[idx + 2], row[idx + 3]]),
            );
        }
    }

    DynamicImage::ImageRgba8(output)
}

/// Detección de bordes con operador Sobel
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

    // Fila superior e inferior negra
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

/// Ajuste de Brillo: value en rango [-1.0, 1.0]
pub fn adjust_brightness(img: &DynamicImage, value: f32) -> DynamicImage {
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let offset = (value * 255.0) as i16;

    let src: &[u8] = rgba.as_raw();
    let mut dst = vec![0u8; src.len()];

    dst.par_chunks_mut(w as usize * 4)
        .enumerate()
        .for_each(|(y, row)| {
            let src_offset = y * w as usize * 4;
            for i in (0..row.len()).step_by(4) {
                row[i] = (src[src_offset + i] as i16 + offset).clamp(0, 255) as u8;
                row[i + 1] = (src[src_offset + i + 1] as i16 + offset).clamp(0, 255) as u8;
                row[i + 2] = (src[src_offset + i + 2] as i16 + offset).clamp(0, 255) as u8;
                row[i + 3] = src[src_offset + i + 3]; // alpha sin cambios
            }
        });

    let buf = ImageBuffer::from_raw(w, h, dst).unwrap();
    DynamicImage::ImageRgba8(buf)
}

/// Ajuste de Contraste: value en rango [-1.0, 1.0]
pub fn adjust_contrast(img: &DynamicImage, value: f32) -> DynamicImage {
    let factor = (1.0 + value) * (1.0 + value);
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let src: &[u8] = rgba.as_raw();
    let mut dst = vec![0u8; src.len()];

    dst.par_chunks_mut(w as usize * 4)
        .enumerate()
        .for_each(|(y, row)| {
            let src_offset = y * w as usize * 4;
            for i in (0..row.len()).step_by(4) {
                for c in 0..3 {
                    let v = src[src_offset + i + c] as f32 / 255.0;
                    let adjusted = ((v - 0.5) * factor + 0.5) * 255.0;
                    row[i + c] = adjusted.clamp(0.0, 255.0) as u8;
                }
                row[i + 3] = src[src_offset + i + 3];
            }
        });

    let buf = ImageBuffer::from_raw(w, h, dst).unwrap();
    DynamicImage::ImageRgba8(buf)
}

/// Ajuste HSL (Hue rotation en grados, Saturation y Lightness en [-1.0, 1.0])
pub fn adjust_hsl(img: &DynamicImage, hue: f32, saturation: f32, lightness: f32) -> DynamicImage {
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let src: &[u8] = rgba.as_raw();
    let mut dst = vec![0u8; src.len()];

    dst.par_chunks_mut(w as usize * 4)
        .enumerate()
        .for_each(|(y, row)| {
            let src_offset = y * w as usize * 4;
            for i in (0..row.len()).step_by(4) {
                let r = src[src_offset + i] as f32 / 255.0;
                let g = src[src_offset + i + 1] as f32 / 255.0;
                let b = src[src_offset + i + 2] as f32 / 255.0;

                let (h_val, s_val, l_val) = rgb_to_hsl(r, g, b);

                let new_h = (h_val + hue) % 360.0;
                let new_s = (s_val + saturation).clamp(0.0, 1.0);
                let new_l = (l_val + lightness).clamp(0.0, 1.0);

                let (nr, ng, nb) = hsl_to_rgb(
                    if new_h < 0.0 { new_h + 360.0 } else { new_h },
                    new_s,
                    new_l,
                );
                row[i] = (nr * 255.0).clamp(0.0, 255.0) as u8;
                row[i + 1] = (ng * 255.0).clamp(0.0, 255.0) as u8;
                row[i + 2] = (nb * 255.0).clamp(0.0, 255.0) as u8;
                row[i + 3] = src[src_offset + i + 3];
            }
        });

    let buf = ImageBuffer::from_raw(w, h, dst).unwrap();
    DynamicImage::ImageRgba8(buf)
}

fn rgb_to_hsl(r: f32, g: f32, b: f32) -> (f32, f32, f32) {
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

fn hsl_to_rgb(h: f32, s: f32, l: f32) -> (f32, f32, f32) {
    if s.abs() < f32::EPSILON {
        return (l, l, l);
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

    (r, g, b)
}

fn hue_to_rgb(p: f32, q: f32, mut t: f32) -> f32 {
    if t < 0.0 {
        t += 1.0;
    }
    if t > 1.0 {
        t -= 1.0;
    }
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
