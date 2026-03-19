use image::DynamicImage;
use std::io::Cursor;

/// Codifica una imagen en el formato de salida especificado.
pub fn encode_to_format(
    img: &DynamicImage,
    format: &str,
    quality: u8,
) -> Result<Vec<u8>, String> {
    let mut buffer = Vec::new();
    let mut cursor = Cursor::new(&mut buffer);

    match format.to_lowercase().as_str() {
        "jpeg" | "jpg" => {
            let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(
                &mut cursor,
                quality,
            );
            img.write_with_encoder(encoder)
                .map_err(|e| format!("JPEG encode error: {e}"))?;
        }
        "png" => {
            let encoder = image::codecs::png::PngEncoder::new(&mut cursor);
            img.write_with_encoder(encoder)
                .map_err(|e| format!("PNG encode error: {e}"))?;

            // Optimizar con oxipng si calidad < 100
            if quality < 100 {
                drop(cursor);
                let opts = oxipng::Options {
                    strip: oxipng::StripChunks::None, // Preservar metadatos
                    ..oxipng::Options::from_preset(2)
                };
                buffer = oxipng::optimize_from_memory(&buffer, &opts)
                    .unwrap_or(buffer);
            }
        }
        "webp" => {
            let rgba = img.to_rgba8();
            let (w, h) = rgba.dimensions();
            let encoder = webp::Encoder::from_rgba(rgba.as_raw(), w, h);
            let webp_data = if quality >= 100 {
                encoder.encode_lossless()
            } else {
                encoder.encode(quality as f32)
            };
            buffer = webp_data.to_vec();
        }
        "avif" => {
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
        "tiff" => {
            let encoder = image::codecs::tiff::TiffEncoder::new(&mut cursor);
            img.write_with_encoder(encoder)
                .map_err(|e| format!("TIFF encode error: {e}"))?;
        }
        "bmp" => {
            let encoder = image::codecs::bmp::BmpEncoder::new(&mut cursor);
            img.write_with_encoder(encoder)
                .map_err(|e| format!("BMP encode error: {e}"))?;
        }
        _ => {
            return Err(format!("Unsupported output format: {format}"));
        }
    }

    Ok(buffer)
}

/// Decodifica bytes a DynamicImage.
pub fn decode_image(data: &[u8]) -> Result<DynamicImage, String> {
    image::load_from_memory(data).map_err(|e| format!("Decode error: {e}"))
}
