use image::{DynamicImage, ImageBuffer, Rgba};
use imageproc::geometric_transformations::{
    rotate_about_center, warp_into, Interpolation, Projection,
};

use crate::pipeline::RotationCanvas;

use fast_image_resize as fir;

/// Resize with Lanczos3 using fast_image_resize (SIMD-optimised).
pub fn resize_lanczos3(img: &DynamicImage, width: u32, height: u32) -> DynamicImage {
    let (src_w, src_h) = (img.width(), img.height());
    if src_w == width && src_h == height {
        return img.clone();
    }

    resize_with_filter(img, width, height, fir::FilterType::Lanczos3)
}

/// Resizes an image using the given filter.
pub fn resize_with_filter(
    img: &DynamicImage,
    width: u32,
    height: u32,
    filter: fir::FilterType,
) -> DynamicImage {
    let src_image = img.to_rgba8();
    let (src_w, src_h) = (src_image.width(), src_image.height());

    let src =
        fir::images::Image::from_vec_u8(src_w, src_h, src_image.into_raw(), fir::PixelType::U8x4)
            .expect("valid RGBA source");

    let mut dst = fir::images::Image::new(width, height, fir::PixelType::U8x4);

    let mut resizer = fir::Resizer::new();
    resizer
        .resize(
            &src,
            &mut dst,
            Some(&fir::ResizeOptions::new().resize_alg(fir::ResizeAlg::Convolution(filter))),
        )
        .expect("resize succeeds");

    let buf = dst.into_vec();
    ImageBuffer::from_raw(width, height, buf)
        .map(DynamicImage::ImageRgba8)
        .expect("buffer size matches dimensions")
}

/// Rectangular crop.
pub fn crop(img: &DynamicImage, x: u32, y: u32, width: u32, height: u32) -> DynamicImage {
    DynamicImage::ImageRgba8(
        image::imageops::crop_imm(&img.to_rgba8(), x, y, width, height).to_image(),
    )
}

/// Free-angle rotation with either the original canvas or a canvas expanded
/// to contain every rotated corner.
pub fn rotate(
    img: &DynamicImage,
    degrees: f64,
    canvas: RotationCanvas,
    background: u32,
) -> DynamicImage {
    let deg_normalized = degrees.rem_euclid(360.0);

    // Fast paths for exact angles.
    if (deg_normalized - 0.0).abs() < 0.01 || (deg_normalized - 360.0).abs() < 0.01 {
        return img.clone();
    }
    if (deg_normalized - 90.0).abs() < 0.01 {
        return img.rotate90();
    }
    if (deg_normalized - 180.0).abs() < 0.01 {
        return img.rotate180();
    }
    if (deg_normalized - 270.0).abs() < 0.01 {
        return img.rotate270();
    }

    // General case: rotate about the centre with bilinear interpolation.
    let radians = (-degrees).to_radians() as f32;
    let rgba = img.to_rgba8();
    let color = Rgba([
        ((background >> 16) & 0xff) as u8,
        ((background >> 8) & 0xff) as u8,
        (background & 0xff) as u8,
        ((background >> 24) & 0xff) as u8,
    ]);
    if canvas == RotationCanvas::Clip {
        return DynamicImage::ImageRgba8(rotate_about_center(
            &rgba,
            radians,
            Interpolation::Bilinear,
            color,
        ));
    }

    let (width, height) = (rgba.width() as f32, rgba.height() as f32);
    let (sin, cos) = radians.sin_cos();
    let output_width = (width * cos.abs() + height * sin.abs()).ceil() as u32;
    let output_height = (width * sin.abs() + height * cos.abs()).ceil() as u32;
    let projection = Projection::translate(-width / 2.0, -height / 2.0)
        .and_then(Projection::rotate(radians))
        .and_then(Projection::translate(
            output_width as f32 / 2.0,
            output_height as f32 / 2.0,
        ));
    let mut rotated = ImageBuffer::from_pixel(output_width, output_height, color);
    warp_into(
        &rgba,
        &projection,
        Interpolation::Bilinear,
        color,
        &mut rotated,
    );
    DynamicImage::ImageRgba8(rotated)
}

/// Horizontal flip.
pub fn flip_horizontal(img: &DynamicImage) -> DynamicImage {
    img.fliph()
}

/// Vertical flip.
pub fn flip_vertical(img: &DynamicImage) -> DynamicImage {
    img.flipv()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn expanded_rotation_does_not_keep_the_clipping_canvas() {
        let image =
            DynamicImage::ImageRgba8(ImageBuffer::from_pixel(100, 50, Rgba([1, 2, 3, 255])));
        let expanded = rotate(&image, 45.0, RotationCanvas::Expand, 0);
        let clipped = rotate(&image, 45.0, RotationCanvas::Clip, 0);
        assert!(expanded.width() > clipped.width());
        assert!(expanded.height() > clipped.height());
    }

    #[test]
    fn right_angle_rotation_uses_exact_dimensions() {
        let image = DynamicImage::ImageRgba8(ImageBuffer::from_pixel(7, 3, Rgba([0, 0, 0, 0])));
        let rotated = rotate(&image, 90.0, RotationCanvas::Expand, 0);
        assert_eq!((rotated.width(), rotated.height()), (3, 7));
    }
}
