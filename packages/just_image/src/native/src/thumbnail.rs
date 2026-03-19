use image::DynamicImage;
use fast_image_resize as fir;

/// Genera un thumbnail preservando el aspect ratio.
///
/// La imagen se redimensiona para caber dentro del bounding box
/// `max_width × max_height` sin distorsionar. Usa filtro Bilinear
/// para máxima velocidad.
pub fn generate_thumbnail(img: &DynamicImage, max_width: u32, max_height: u32) -> DynamicImage {
    let (src_w, src_h) = (img.width(), img.height());

    if src_w == 0 || src_h == 0 || max_width == 0 || max_height == 0 {
        return img.clone();
    }

    // Ya cabe dentro del bounding box
    if src_w <= max_width && src_h <= max_height {
        return img.clone();
    }

    // Calcular dimensiones preservando aspect ratio (fit inside)
    let ratio_w = max_width as f64 / src_w as f64;
    let ratio_h = max_height as f64 / src_h as f64;
    let ratio = ratio_w.min(ratio_h);

    let dst_w = (src_w as f64 * ratio).round().max(1.0) as u32;
    let dst_h = (src_h as f64 * ratio).round().max(1.0) as u32;

    let src_image = img.to_rgba8();

    let src = fir::images::Image::from_vec_u8(
        src_w,
        src_h,
        src_image.into_raw(),
        fir::PixelType::U8x4,
    )
    .unwrap();

    let mut dst = fir::images::Image::new(dst_w, dst_h, fir::PixelType::U8x4);

    let mut resizer = fir::Resizer::new();
    resizer
        .resize(
            &src,
            &mut dst,
            Some(
                &fir::ResizeOptions::new()
                    .resize_alg(fir::ResizeAlg::Convolution(fir::FilterType::Bilinear)),
            ),
        )
        .unwrap();

    let buf = dst.into_vec();
    let img_buf = image::ImageBuffer::from_raw(dst_w, dst_h, buf).unwrap();
    DynamicImage::ImageRgba8(img_buf)
}
