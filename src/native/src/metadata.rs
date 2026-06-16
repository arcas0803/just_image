use std::io::Cursor;

/// Datos de metadatos extraídos de una imagen.
#[derive(Debug, Clone)]
pub struct ImageMetadata {
    pub exif_data: Option<Vec<u8>>,
    pub icc_profile: Option<Vec<u8>>,
    pub orientation: u16,
}

impl Default for ImageMetadata {
    fn default() -> Self {
        Self {
            exif_data: None,
            icc_profile: None,
            orientation: 1,
        }
    }
}

/// Extrae metadatos EXIF del buffer de imagen original.
pub fn extract_metadata(data: &[u8]) -> ImageMetadata {
    let mut meta = ImageMetadata::default();

    // Extraer EXIF con kamadak-exif
    if let Ok(exif_reader) = exif::Reader::new().read_from_container(&mut Cursor::new(data)) {
        // Obtener orientación
        if let Some(orient) = exif_reader.get_field(exif::Tag::Orientation, exif::In::PRIMARY) {
            if let Some(v) = orient.value.get_uint(0) {
                meta.orientation = v as u16;
            }
        }
    }

    // Extraer raw EXIF bytes (APP1 marker en JPEG)
    meta.exif_data = extract_exif_bytes(data);

    // Extraer perfil ICC (APP2 marker en JPEG)
    meta.icc_profile = extract_icc_profile(data);

    meta
}

/// Extrae los bytes EXIF raw de un JPEG (APP1 segment)
fn extract_exif_bytes(data: &[u8]) -> Option<Vec<u8>> {
    if data.len() < 4 {
        return None;
    }

    // JPEG: buscar APP1 marker (0xFF 0xE1)
    if data[0] == 0xFF && data[1] == 0xD8 {
        let mut pos = 2;
        while pos + 4 < data.len() {
            if data[pos] != 0xFF {
                break;
            }
            let marker = data[pos + 1];
            let seg_len = u16::from_be_bytes([data[pos + 2], data[pos + 3]]) as usize;

            if marker == 0xE1 {
                // APP1 - EXIF
                let end = (pos + 2 + seg_len).min(data.len());
                return Some(data[pos..end].to_vec());
            }

            pos += 2 + seg_len;
            if marker == 0xDA {
                break; // Start of scan, no more markers
            }
        }
    }

    // PNG: buscar chunk eXIf
    if data.len() > 8 && &data[0..4] == b"\x89PNG" {
        let mut pos = 8;
        while pos + 12 < data.len() {
            let chunk_len =
                u32::from_be_bytes([data[pos], data[pos + 1], data[pos + 2], data[pos + 3]])
                    as usize;
            let chunk_type = &data[pos + 4..pos + 8];
            if chunk_type == b"eXIf" {
                let start = pos + 8;
                let end = (start + chunk_len).min(data.len());
                return Some(data[start..end].to_vec());
            }
            pos += 12 + chunk_len;
        }
    }

    None
}

/// Extrae el perfil ICC de un JPEG (APP2 segment) o PNG (iCCP chunk)
fn extract_icc_profile(data: &[u8]) -> Option<Vec<u8>> {
    if data.len() < 4 {
        return None;
    }

    // JPEG: buscar APP2 marker (0xFF 0xE2) con "ICC_PROFILE"
    if data[0] == 0xFF && data[1] == 0xD8 {
        let mut icc_chunks: Vec<(u8, Vec<u8>)> = Vec::new();
        let mut pos = 2;

        while pos + 4 < data.len() {
            if data[pos] != 0xFF {
                break;
            }
            let marker = data[pos + 1];
            let seg_len = u16::from_be_bytes([data[pos + 2], data[pos + 3]]) as usize;

            if marker == 0xE2 && seg_len > 14 {
                let seg_start = pos + 4;
                let icc_header = b"ICC_PROFILE\0";
                if seg_start + 14 < data.len()
                    && &data[seg_start..seg_start + 12] == icc_header
                {
                    let chunk_num = data[seg_start + 12];
                    let _total = data[seg_start + 13];
                    let payload_start = seg_start + 14;
                    let payload_end = (pos + 2 + seg_len).min(data.len());
                    if payload_start < payload_end {
                        icc_chunks.push((chunk_num, data[payload_start..payload_end].to_vec()));
                    }
                }
            }

            pos += 2 + seg_len;
            if marker == 0xDA {
                break;
            }
        }

        if !icc_chunks.is_empty() {
            icc_chunks.sort_by_key(|(n, _)| *n);
            let mut profile = Vec::new();
            for (_, chunk) in icc_chunks {
                profile.extend_from_slice(&chunk);
            }
            return Some(profile);
        }
    }

    // PNG: buscar chunk iCCP
    if data.len() > 8 && &data[0..4] == b"\x89PNG" {
        let mut pos = 8;
        while pos + 12 < data.len() {
            let chunk_len =
                u32::from_be_bytes([data[pos], data[pos + 1], data[pos + 2], data[pos + 3]])
                    as usize;
            let chunk_type = &data[pos + 4..pos + 8];
            if chunk_type == b"iCCP" {
                let start = pos + 8;
                let end = (start + chunk_len).min(data.len());
                return Some(data[start..end].to_vec());
            }
            pos += 12 + chunk_len;
        }
    }

    None
}

/// Aplica la auto-orientación EXIF a la imagen
pub fn apply_orientation(img: &image::DynamicImage, orientation: u16) -> image::DynamicImage {
    match orientation {
        2 => img.fliph(),
        3 => img.rotate180(),
        4 => img.flipv(),
        5 => img.rotate90().fliph(),
        6 => img.rotate90(),
        7 => img.rotate270().fliph(),
        8 => img.rotate270(),
        _ => img.clone(), // 1 = normal, o desconocido
    }
}

/// Re-inyecta EXIF y ICC en un buffer JPEG de salida.
pub fn inject_metadata_jpeg(
    output: &[u8],
    exif_data: Option<&[u8]>,
    icc_profile: Option<&[u8]>,
) -> Vec<u8> {
    if exif_data.is_none() && icc_profile.is_none() {
        return output.to_vec();
    }

    let mut result = Vec::with_capacity(output.len() + 65536);

    // JPEG debe empezar con SOI (0xFF 0xD8)
    if output.len() < 2 || output[0] != 0xFF || output[1] != 0xD8 {
        return output.to_vec();
    }

    result.push(0xFF);
    result.push(0xD8);

    // Insertar EXIF (APP1)
    if let Some(exif) = exif_data {
        if exif.len() > 2 && exif[0] == 0xFF && exif[1] == 0xE1 {
            result.extend_from_slice(exif);
        } else {
            // Wrap en APP1
            let len = exif.len() + 2;
            result.push(0xFF);
            result.push(0xE1);
            result.push((len >> 8) as u8);
            result.push((len & 0xFF) as u8);
            result.extend_from_slice(exif);
        }
    }

    // Insertar ICC (APP2)
    if let Some(icc) = icc_profile {
        let header = b"ICC_PROFILE\0";
        // Fragmentar si > 65519 bytes
        let max_chunk = 65519 - 14;
        let total_chunks = (icc.len() + max_chunk - 1) / max_chunk;

        for (i, chunk) in icc.chunks(max_chunk).enumerate() {
            let seg_len = chunk.len() + 14 + 2;
            result.push(0xFF);
            result.push(0xE2);
            result.push((seg_len >> 8) as u8);
            result.push((seg_len & 0xFF) as u8);
            result.extend_from_slice(header);
            result.push((i + 1) as u8);
            result.push(total_chunks as u8);
            result.extend_from_slice(chunk);
        }
    }

    // Copiar el resto del JPEG original (saltando SOI)
    result.extend_from_slice(&output[2..]);

    result
}
