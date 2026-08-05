use image::DynamicImage;
use std::io::Cursor;

use crate::pipeline::OutputFormat;

/// Encodes an image to the requested output format.
pub fn encode_to_format(
    img: &DynamicImage,
    format: OutputFormat,
    quality: u8,
) -> Result<Vec<u8>, String> {
    let mut buffer = Vec::new();

    match format {
        OutputFormat::Jpeg => {
            let mut cursor = Cursor::new(&mut buffer);
            let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut cursor, quality);
            img.write_with_encoder(encoder)
                .map_err(|e| format!("JPEG encode error: {e}"))?;
        }
        OutputFormat::Png => {
            let mut cursor = Cursor::new(&mut buffer);
            let encoder = image::codecs::png::PngEncoder::new(&mut cursor);
            img.write_with_encoder(encoder)
                .map_err(|e| format!("PNG encode error: {e}"))?;

            // Optionally optimize with oxipng when quality < 100.
            if quality < 100 {
                let _ = cursor;
                let opts = oxipng::Options {
                    strip: oxipng::StripChunks::None,
                    ..oxipng::Options::from_preset(2)
                };
                buffer = oxipng::optimize_from_memory(&buffer, &opts).unwrap_or(buffer);
            }
        }
        OutputFormat::Webp => {
            let rgba = img.to_rgba8();
            let (w, h) = rgba.dimensions();
            let encoder = webp::Encoder::from_rgba(rgba.as_raw(), w, h);
            let webp_data = if quality >= 100 {
                encoder.encode_lossless()
            } else {
                encoder.encode(quality as f32)
            };
            buffer = webp_data.to_vec();
            if buffer.is_empty() {
                return Err("WebP encode error: encoder returned empty data".to_string());
            }
        }
        OutputFormat::Avif => {
            let rgba = img.to_rgba8();
            let (w, h) = rgba.dimensions();

            use rgb::FromSlice;
            let pixels: &[rgb::RGBA8] = rgba.as_raw().as_rgba();
            let img_ref = ravif::Img::new(pixels, w as usize, h as usize);

            let encoder = ravif::Encoder::new()
                .with_quality(quality as f32)
                .with_speed(6)
                .with_alpha_quality(quality as f32);

            let result = encoder
                .encode_rgba(img_ref)
                .map_err(|e| format!("AVIF encode error: {e}"))?;

            buffer = result.avif_file;
        }
        OutputFormat::Tiff => {
            let mut cursor = Cursor::new(&mut buffer);
            let encoder = image::codecs::tiff::TiffEncoder::new(&mut cursor);
            img.write_with_encoder(encoder)
                .map_err(|e| format!("TIFF encode error: {e}"))?;
        }
        OutputFormat::Bmp => {
            let mut cursor = Cursor::new(&mut buffer);
            let encoder = image::codecs::bmp::BmpEncoder::new(&mut cursor);
            img.write_with_encoder(encoder)
                .map_err(|e| format!("BMP encode error: {e}"))?;
        }
    }

    Ok(buffer)
}

/// Decodes raw bytes into a DynamicImage.
pub fn decode_image(data: &[u8]) -> Result<DynamicImage, String> {
    image::load_from_memory(data).map_err(|e| format!("Decode error: {e}"))
}

#[cfg(test)]
mod tests {
    use image::{ImageBuffer, Rgba};

    use super::*;

    fn test_image() -> DynamicImage {
        DynamicImage::ImageRgba8(ImageBuffer::from_fn(4, 3, |x, y| {
            Rgba([(x * 50) as u8, (y * 70) as u8, 120, 255])
        }))
    }

    #[test]
    fn every_output_format_round_trips() {
        for format in [
            OutputFormat::Jpeg,
            OutputFormat::Png,
            OutputFormat::Webp,
            OutputFormat::Avif,
            OutputFormat::Tiff,
            OutputFormat::Bmp,
        ] {
            let encoded = encode_to_format(&test_image(), format, 85)
                .unwrap_or_else(|error| panic!("{} failed: {error}", format.as_str()));
            assert!(!encoded.is_empty());
            if format == OutputFormat::Avif {
                assert_eq!(&encoded[4..8], b"ftyp");
                continue;
            }
            let decoded = decode_image(&encoded)
                .unwrap_or_else(|error| panic!("{} failed to decode: {error}", format.as_str()));
            assert_eq!((decoded.width(), decoded.height()), (4, 3));
        }
    }

    #[test]
    fn invalid_bytes_return_a_decode_error() {
        assert!(decode_image(&[1, 2, 3]).is_err());
    }
}
