/// Módulo de gestión de perfiles de color ICC.
/// Usa lcms2 para conversiones de espacio de color con preservación de tonos.

use rgb::RGBA;

/// Aplica un perfil ICC al buffer de imagen si está disponible.
/// Convierte de perfil embebido a sRGB para procesamiento uniforme,
/// luego reconvierte al perfil original antes de la salida.
pub fn apply_icc_transform(
    pixels: &mut [u8],
    width: u32,
    height: u32,
    icc_profile: &[u8],
    to_working: bool,
) -> Result<(), String> {
    use lcms2::*;

    let src_profile = Profile::new_icc(icc_profile).map_err(|e| format!("ICC parse error: {e}"))?;

    let srgb = Profile::new_srgb();

    let (from, to) = if to_working {
        (&src_profile, &srgb)
    } else {
        (&srgb, &src_profile)
    };

    let transform = Transform::new(
        from,
        PixelFormat::RGBA_8,
        to,
        PixelFormat::RGBA_8,
        Intent::Perceptual,
    )
    .map_err(|e| format!("ICC transform error: {e}"))?;

    let pixel_count = (width * height) as usize;
    if pixels.len() < pixel_count * 4 {
        return Err("Buffer too small for ICC transform".to_string());
    }

    let src = pixels_as_rgba(pixels, pixel_count);
    let mut dst: Vec<RGBA<u8>> = vec![RGBA { r: 0, g: 0, b: 0, a: 0 }; pixel_count];
    transform.transform_pixels(&src, &mut dst);
    write_icc_result(pixels, &dst);

    Ok(())
}

fn pixels_as_rgba(data: &[u8], count: usize) -> Vec<RGBA<u8>> {
    let mut result = Vec::with_capacity(count);
    for i in 0..count {
        let offset = i * 4;
        result.push(RGBA {
            r: data[offset],
            g: data[offset + 1],
            b: data[offset + 2],
            a: data[offset + 3],
        });
    }
    result
}

fn write_icc_result(dst: &mut [u8], src: &[RGBA<u8>]) {
    for (i, px) in src.iter().enumerate() {
        let offset = i * 4;
        dst[offset] = px.r;
        dst[offset + 1] = px.g;
        dst[offset + 2] = px.b;
        dst[offset + 3] = px.a;
    }
}
