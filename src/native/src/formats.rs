use image::{DynamicImage, ImageBuffer, ImageDecoder, ImageEncoder, ImageFormat, Rgb, Rgba};
use std::io::Cursor;

use crate::pipeline::{InputFormat, OutputFormat, PipelineConfig, PngCompression, PngFilter};

pub fn encode_to_format(
    img: &DynamicImage,
    config: &PipelineConfig,
    icc_profile: Option<&[u8]>,
) -> Result<Vec<u8>, String> {
    match config.output_format {
        OutputFormat::Webp => encode_webp(img, config),
        OutputFormat::Tiff => encode_tiff(img, icc_profile),
        OutputFormat::Avif => Err("AVIF output requires the extended pipeline".into()),
        _ => encode_core_format(img, config),
    }
}

pub fn encode_extended_format(
    img: &DynamicImage,
    config: &PipelineConfig,
    icc_profile: Option<&[u8]>,
) -> Result<Vec<u8>, String> {
    if config.output_format != OutputFormat::Avif {
        return encode_to_format(img, config, icc_profile);
    }
    let rgba = img.to_rgba8();
    let (width, height) = rgba.dimensions();
    let mut buffer = Vec::new();
    image::codecs::avif::AvifEncoder::new_with_speed_quality(
        &mut buffer,
        config.avif_speed,
        config.quality,
    )
    .with_num_threads(config.avif_threads)
    .write_image(
        rgba.as_raw(),
        width,
        height,
        image::ExtendedColorType::Rgba8,
    )
    .map_err(|error| format!("AVIF encode error: {error}"))?;
    Ok(buffer)
}

/// This entry point deliberately has no references to optional codecs.
pub fn encode_core_format(img: &DynamicImage, config: &PipelineConfig) -> Result<Vec<u8>, String> {
    let mut buffer = Vec::new();
    match config.output_format {
        OutputFormat::Jpeg => {
            let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(
                Cursor::new(&mut buffer),
                config.quality,
            );
            img.write_with_encoder(encoder)
                .map_err(|e| format!("JPEG encode error: {e}"))?;
        }
        OutputFormat::Png => {
            let compression = match config.png_compression {
                PngCompression::Fast => image::codecs::png::CompressionType::Fast,
                PngCompression::Balanced => image::codecs::png::CompressionType::Default,
                PngCompression::Best => image::codecs::png::CompressionType::Best,
            };
            let filter = match config.png_filter {
                PngFilter::Adaptive => image::codecs::png::FilterType::Adaptive,
                PngFilter::None => image::codecs::png::FilterType::NoFilter,
                PngFilter::Sub => image::codecs::png::FilterType::Sub,
                PngFilter::Up => image::codecs::png::FilterType::Up,
                PngFilter::Average => image::codecs::png::FilterType::Avg,
                PngFilter::Paeth => image::codecs::png::FilterType::Paeth,
            };
            let encoder = image::codecs::png::PngEncoder::new_with_quality(
                Cursor::new(&mut buffer),
                compression,
                filter,
            );
            img.write_with_encoder(encoder)
                .map_err(|e| format!("PNG encode error: {e}"))?;
            if config.png_optimization > 0 || config.quality < 100 {
                let preset = if config.png_optimization > 0 {
                    config.png_optimization
                } else {
                    2
                };
                let options = oxipng::Options {
                    strip: oxipng::StripChunks::None,
                    ..oxipng::Options::from_preset(preset)
                };
                buffer = oxipng::optimize_from_memory(&buffer, &options).unwrap_or(buffer);
            }
        }
        OutputFormat::Bmp => {
            let mut cursor = Cursor::new(&mut buffer);
            let encoder = image::codecs::bmp::BmpEncoder::new(&mut cursor);
            img.write_with_encoder(encoder)
                .map_err(|e| format!("BMP encode error: {e}"))?;
        }
        OutputFormat::Webp | OutputFormat::Tiff | OutputFormat::Avif => {
            return Err(format!(
                "{} is not supported by the core pipeline",
                config.output_format.as_str()
            ))
        }
    }
    Ok(buffer)
}

fn encode_webp(img: &DynamicImage, config: &PipelineConfig) -> Result<Vec<u8>, String> {
    let rgba = img.to_rgba8();
    let (width, height) = rgba.dimensions();
    let encoder = webp::Encoder::from_rgba(rgba.as_raw(), width, height);
    let data = if config.webp_lossless || config.quality == 100 {
        encoder.encode_lossless()
    } else {
        encoder.encode(config.quality as f32)
    };
    let result = data.to_vec();
    if result.is_empty() {
        Err("WebP encode error: encoder returned empty data".into())
    } else {
        Ok(result)
    }
}

fn encode_tiff(img: &DynamicImage, icc_profile: Option<&[u8]>) -> Result<Vec<u8>, String> {
    let mut buffer = Vec::new();
    let mut encoder = image::codecs::tiff::TiffEncoder::new(Cursor::new(&mut buffer));
    if let Some(profile) = icc_profile {
        encoder
            .set_icc_profile(profile.to_vec())
            .map_err(|error| format!("TIFF ICC profile error: {error}"))?;
    }
    img.write_with_encoder(encoder)
        .map_err(|e| format!("TIFF encode error: {e}"))?;
    Ok(buffer)
}

pub fn decode_image(data: &[u8]) -> Result<DynamicImage, String> {
    image::load_from_memory(data).map_err(|e| format!("Decode error: {e}"))
}

pub fn decode_extended_image(data: &[u8], config: &PipelineConfig) -> Result<DynamicImage, String> {
    match config.input_format {
        InputFormat::Svg => decode_svg(data, config.svg_width, config.svg_height),
        InputFormat::Avif => decode_avif(data),
        InputFormat::Auto if looks_like_svg(data) => {
            decode_svg(data, config.svg_width, config.svg_height)
        }
        InputFormat::Auto if looks_like_avif(data) => decode_avif(data),
        InputFormat::Auto => decode_image(data),
    }
}

pub fn decode_core_image(data: &[u8]) -> Result<DynamicImage, String> {
    let format = image::guess_format(data).map_err(|e| format!("Decode error: {e}"))?;
    let cursor = Cursor::new(data);
    match format {
        ImageFormat::Jpeg => image::codecs::jpeg::JpegDecoder::new(cursor)
            .map_err(|e| format!("JPEG decode error: {e}"))
            .and_then(decode_dynamic),
        ImageFormat::Png => image::codecs::png::PngDecoder::new(cursor)
            .map_err(|e| format!("PNG decode error: {e}"))
            .and_then(decode_dynamic),
        ImageFormat::Bmp => image::codecs::bmp::BmpDecoder::new(cursor)
            .map_err(|e| format!("BMP decode error: {e}"))
            .and_then(decode_dynamic),
        _ => Err(format!(
            "{} input is not supported by the core pipeline",
            format
                .extensions_str()
                .first()
                .copied()
                .unwrap_or("unknown")
        )),
    }
}

fn decode_dynamic<D: ImageDecoder>(decoder: D) -> Result<DynamicImage, String> {
    DynamicImage::from_decoder(decoder).map_err(|e| format!("Decode error: {e}"))
}

fn looks_like_avif(data: &[u8]) -> bool {
    data.len() >= 12
        && &data[4..8] == b"ftyp"
        && matches!(&data[8..12], b"avif" | b"avis" | b"mif1" | b"msf1")
}

fn looks_like_svg(data: &[u8]) -> bool {
    let prefix = std::str::from_utf8(&data[..data.len().min(512)]).unwrap_or("");
    let prefix = prefix.trim_start_matches('\u{feff}').trim_start();
    prefix.starts_with("<svg") || (prefix.starts_with("<?xml") && prefix.contains("<svg"))
}

fn decode_svg(
    data: &[u8],
    requested_width: Option<u32>,
    requested_height: Option<u32>,
) -> Result<DynamicImage, String> {
    let tree = resvg::usvg::Tree::from_data(data, &resvg::usvg::Options::default())
        .map_err(|e| format!("SVG parse error: {e}"))?;
    let intrinsic = tree.size();
    let (iw, ih) = (intrinsic.width(), intrinsic.height());
    let (width, height) = match (requested_width, requested_height) {
        (Some(w), Some(h)) => (w, h),
        (Some(w), None) => (w, ((w as f32 * ih / iw).round() as u32).max(1)),
        (None, Some(h)) => (((h as f32 * iw / ih).round() as u32).max(1), h),
        (None, None) => {
            let size = intrinsic.to_int_size();
            (size.width(), size.height())
        }
    };
    let mut pixmap = resvg::tiny_skia::Pixmap::new(width, height)
        .ok_or_else(|| format!("SVG raster dimensions are too large: {width}x{height}"))?;
    let transform = resvg::tiny_skia::Transform::from_scale(width as f32 / iw, height as f32 / ih);
    resvg::render(&tree, transform, &mut pixmap.as_mut());
    let mut bytes = pixmap.take();
    for pixel in bytes.as_chunks_mut::<4>().0 {
        let alpha = pixel[3] as u32;
        if alpha > 0 && alpha < 255 {
            for channel in &mut pixel[..3] {
                *channel = ((*channel as u32 * 255 + alpha / 2) / alpha).min(255) as u8;
            }
        }
    }
    ImageBuffer::from_raw(width, height, bytes)
        .map(DynamicImage::ImageRgba8)
        .ok_or_else(|| "SVG raster buffer size mismatch".into())
}

fn decode_avif(data: &[u8]) -> Result<DynamicImage, String> {
    let decoded = avif_decode::Decoder::from_avif(data)
        .and_then(avif_decode::Decoder::to_image)
        .map_err(|e| format!("AVIF decode error: {e}"))?;
    use avif_decode::Image;
    match decoded {
        Image::Rgb8(i) => {
            let (w, h) = (i.width() as u32, i.height() as u32);
            let b = i.pixels().flat_map(|p| [p.r, p.g, p.b]).collect();
            ImageBuffer::<Rgb<u8>, _>::from_raw(w, h, b)
                .map(DynamicImage::ImageRgb8)
                .ok_or_else(|| "AVIF RGB buffer mismatch".into())
        }
        Image::Rgba8(i) => {
            let (w, h) = (i.width() as u32, i.height() as u32);
            let b = i.pixels().flat_map(|p| [p.r, p.g, p.b, p.a]).collect();
            ImageBuffer::<Rgba<u8>, _>::from_raw(w, h, b)
                .map(DynamicImage::ImageRgba8)
                .ok_or_else(|| "AVIF RGBA buffer mismatch".into())
        }
        Image::Gray8(i) => {
            let (w, h) = (i.width() as u32, i.height() as u32);
            ImageBuffer::from_raw(w, h, i.pixels().map(|p| p.value()).collect())
                .map(DynamicImage::ImageLuma8)
                .ok_or_else(|| "AVIF gray buffer mismatch".into())
        }
        Image::Rgb16(i) => {
            let (w, h) = (i.width() as u32, i.height() as u32);
            let b = i.pixels().flat_map(|p| [p.r, p.g, p.b]).collect();
            ImageBuffer::<Rgb<u16>, _>::from_raw(w, h, b)
                .map(DynamicImage::ImageRgb16)
                .ok_or_else(|| "AVIF RGB16 buffer mismatch".into())
        }
        Image::Rgba16(i) => {
            let (w, h) = (i.width() as u32, i.height() as u32);
            let b = i.pixels().flat_map(|p| [p.r, p.g, p.b, p.a]).collect();
            ImageBuffer::<Rgba<u16>, _>::from_raw(w, h, b)
                .map(DynamicImage::ImageRgba16)
                .ok_or_else(|| "AVIF RGBA16 buffer mismatch".into())
        }
        Image::Gray16(i) => {
            let (w, h) = (i.width() as u32, i.height() as u32);
            ImageBuffer::from_raw(w, h, i.pixels().map(|p| p.value()).collect())
                .map(DynamicImage::ImageLuma16)
                .ok_or_else(|| "AVIF gray16 buffer mismatch".into())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::GenericImageView;

    fn sample() -> DynamicImage {
        DynamicImage::ImageRgba8(ImageBuffer::from_fn(8, 6, |x, y| {
            Rgba([(x * 20) as u8, (y * 30) as u8, 120, 255])
        }))
    }

    #[test]
    fn avif_round_trip_preserves_dimensions() {
        let config = PipelineConfig {
            output_format: OutputFormat::Avif,
            ..PipelineConfig::default()
        };
        let bytes = encode_extended_format(&sample(), &config, None).unwrap();
        let decoded = decode_avif(&bytes).unwrap();
        assert_eq!(decoded.dimensions(), (8, 6));
    }

    #[test]
    fn svg_uses_requested_width_and_intrinsic_ratio() {
        let svg = br#"<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10"><rect width="20" height="10" fill="red"/></svg>"#;
        let decoded = decode_svg(svg, Some(40), None).unwrap();
        assert_eq!(decoded.dimensions(), (40, 20));
    }

    #[test]
    fn core_rejects_optional_codecs() {
        for output_format in [OutputFormat::Webp, OutputFormat::Tiff, OutputFormat::Avif] {
            let config = PipelineConfig {
                output_format,
                ..PipelineConfig::default()
            };
            assert!(encode_core_format(&sample(), &config).is_err());
        }
    }
}
