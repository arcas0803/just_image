use image::DynamicImage;
use fast_image_resize::{self as fir};

/// Resize con Lanczos3 usando fast_image_resize (SIMD-optimizado)
pub fn resize_lanczos3(img: &DynamicImage, width: u32, height: u32) -> DynamicImage {
    let src_image = img.to_rgba8();
    let (src_w, src_h) = (src_image.width(), src_image.height());

    if src_w == width && src_h == height {
        return img.clone();
    }

    let src = fir::images::Image::from_vec_u8(
        src_w,
        src_h,
        src_image.into_raw(),
        fir::PixelType::U8x4,
    )
    .unwrap();

    let mut dst = fir::images::Image::new(
        width,
        height,
        fir::PixelType::U8x4,
    );

    let mut resizer = fir::Resizer::new();
    resizer.resize(
        &src,
        &mut dst,
        Some(&fir::ResizeOptions::new().resize_alg(
            fir::ResizeAlg::Convolution(fir::FilterType::Lanczos3),
        )),
    ).unwrap();

    let buf = dst.into_vec();
    let img_buf = image::ImageBuffer::from_raw(width, height, buf).unwrap();
    DynamicImage::ImageRgba8(img_buf)
}

/// Crop: recorta una región rectangular
pub fn crop(img: &DynamicImage, x: u32, y: u32, width: u32, height: u32) -> DynamicImage {
    img.crop_imm(x, y, width, height)
}

/// Rotación en ángulos libres con anti-aliasing
pub fn rotate(img: &DynamicImage, degrees: f64) -> DynamicImage {
    // Ángulos exactos: optimización sin interpolación
    let deg_normalized = ((degrees % 360.0) + 360.0) % 360.0;
    if (deg_normalized - 90.0).abs() < 0.01 {
        return img.rotate90();
    }
    if (deg_normalized - 180.0).abs() < 0.01 {
        return img.rotate180();
    }
    if (deg_normalized - 270.0).abs() < 0.01 {
        return img.rotate270();
    }
    if deg_normalized.abs() < 0.01 || (deg_normalized - 360.0).abs() < 0.01 {
        return img.clone();
    }

    // Rotación libre usando imageproc con interpolación bilinear
    let rgba = img.to_rgba8();
    let (w, h) = (rgba.width(), rgba.height());

    let radians = degrees.to_radians();
    let cos_a = radians.cos();
    let sin_a = radians.sin();

    // Calcular dimensiones del resultado
    let new_w = ((w as f64 * cos_a.abs()) + (h as f64 * sin_a.abs())).ceil() as u32;
    let new_h = ((w as f64 * sin_a.abs()) + (h as f64 * cos_a.abs())).ceil() as u32;

    let center_x = w as f64 / 2.0;
    let center_y = h as f64 / 2.0;
    let new_cx = new_w as f64 / 2.0;
    let new_cy = new_h as f64 / 2.0;

    let mut output = image::ImageBuffer::new(new_w, new_h);

    use rayon::prelude::*;
    let rows: Vec<Vec<image::Rgba<u8>>> = (0..new_h)
        .into_par_iter()
        .map(|ny| {
            let mut row = Vec::with_capacity(new_w as usize);
            for nx in 0..new_w {
                let dx = nx as f64 - new_cx;
                let dy = ny as f64 - new_cy;

                // Rotación inversa para encontrar pixel fuente
                let src_x = dx * cos_a + dy * sin_a + center_x;
                let src_y = -dx * sin_a + dy * cos_a + center_y;

                // Interpolación bilinear
                if src_x >= 0.0
                    && src_x < (w - 1) as f64
                    && src_y >= 0.0
                    && src_y < (h - 1) as f64
                {
                    let x0 = src_x.floor() as u32;
                    let y0 = src_y.floor() as u32;
                    let x1 = x0 + 1;
                    let y1 = y0 + 1;
                    let fx = src_x - x0 as f64;
                    let fy = src_y - y0 as f64;

                    let p00 = rgba.get_pixel(x0, y0).0;
                    let p10 = rgba.get_pixel(x1, y0).0;
                    let p01 = rgba.get_pixel(x0, y1).0;
                    let p11 = rgba.get_pixel(x1, y1).0;

                    let mut px = [0u8; 4];
                    for c in 0..4 {
                        let v = p00[c] as f64 * (1.0 - fx) * (1.0 - fy)
                            + p10[c] as f64 * fx * (1.0 - fy)
                            + p01[c] as f64 * (1.0 - fx) * fy
                            + p11[c] as f64 * fx * fy;
                        px[c] = v.clamp(0.0, 255.0) as u8;
                    }
                    row.push(image::Rgba(px));
                } else {
                    row.push(image::Rgba([0, 0, 0, 0]));
                }
            }
            row
        })
        .collect();

    for (y, row) in rows.into_iter().enumerate() {
        for (x, px) in row.into_iter().enumerate() {
            output.put_pixel(x as u32, y as u32, px);
        }
    }

    DynamicImage::ImageRgba8(output)
}

/// Flip horizontal
pub fn flip_horizontal(img: &DynamicImage) -> DynamicImage {
    img.fliph()
}

/// Flip vertical
pub fn flip_vertical(img: &DynamicImage) -> DynamicImage {
    img.flipv()
}
