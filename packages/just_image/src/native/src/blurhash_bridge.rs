use image::{DynamicImage, ImageBuffer, Rgba};

/// Codifica una imagen a un hash BlurHash.
///
/// `components_x` y `components_y` controlan la complejidad del hash
/// (típicamente 4x3). Valores más altos producen hashes más largos
/// pero más detallados.
pub fn encode_blurhash(
    img: &DynamicImage,
    components_x: u32,
    components_y: u32,
) -> Result<String, String> {
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();

    // blurhash::encode espera pixels como &[u8] en RGBA, 4 bytes por pixel
    let pixels = rgba.as_raw();

    blurhash::encode(
        components_x,
        components_y,
        w,
        h,
        pixels,
    )
    .map_err(|e| format!("BlurHash encode error: {e}"))
}

/// Decodifica un hash BlurHash a una imagen RGBA.
///
/// `width` y `height` son las dimensiones de la imagen de salida.
/// Típicamente se usa con dimensiones pequeñas (32x32) para placeholders.
pub fn decode_blurhash(
    hash: &str,
    width: u32,
    height: u32,
) -> Result<DynamicImage, String> {
    let pixels = blurhash::decode(hash, width, height, 1.0)
        .map_err(|e| format!("BlurHash decode error: {e}"))?;

    // blurhash::decode devuelve Vec<u8> en RGBA
    let img_buf = ImageBuffer::<Rgba<u8>, Vec<u8>>::from_raw(width, height, pixels)
        .ok_or_else(|| "Failed to create image buffer from BlurHash decode output".to_string())?;

    Ok(DynamicImage::ImageRgba8(img_buf))
}
