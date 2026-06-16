use image::DynamicImage;

use crate::transforms::resize_with_filter;
use fast_image_resize as fir;

/// Generates a thumbnail that fits inside the given bounding box while
/// preserving the aspect ratio. Uses a fast Bilinear filter.
pub fn generate_thumbnail(img: &DynamicImage, max_width: u32, max_height: u32) -> DynamicImage {
    let (src_w, src_h) = (img.width(), img.height());

    if src_w == 0
        || src_h == 0
        || max_width == 0
        || max_height == 0
        || (src_w <= max_width && src_h <= max_height)
    {
        return img.clone();
    }

    let ratio_w = max_width as f64 / src_w as f64;
    let ratio_h = max_height as f64 / src_h as f64;
    let ratio = ratio_w.min(ratio_h);

    let dst_w = (src_w as f64 * ratio).round().max(1.0) as u32;
    let dst_h = (src_h as f64 * ratio).round().max(1.0) as u32;

    resize_with_filter(img, dst_w, dst_h, fir::FilterType::Bilinear)
}
