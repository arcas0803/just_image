use std::io::Cursor;

use image::ImageDecoder;
use img_parts::{Bytes, DynImage, ImageICC};
use little_exif::exif_tag::ExifTag;
use little_exif::filetype::FileExtension;
use little_exif::ifd::ExifTagGroup;
use little_exif::metadata::Metadata;

use crate::pipeline::{MetadataPolicy, OutputFormat};

/// Metadata decoded once and reused throughout the pipeline.
#[derive(Debug, Clone)]
pub struct ImageMetadata {
    exif: Option<Metadata>,
    pub icc_profile: Option<Vec<u8>>,
    pub orientation: u16,
}

impl Default for ImageMetadata {
    fn default() -> Self {
        Self {
            exif: None,
            icc_profile: None,
            orientation: 1,
        }
    }
}

/// Extracts EXIF from every container supported by little_exif and ICC from
/// JPEG, PNG and WebP. Malformed optional metadata never prevents decoding.
pub fn extract_metadata(data: &[u8]) -> ImageMetadata {
    let orientation = exif::Reader::new()
        .read_from_container(&mut Cursor::new(data))
        .ok()
        .and_then(|reader| {
            reader
                .get_field(exif::Tag::Orientation, exif::In::PRIMARY)
                .and_then(|field| field.value.get_uint(0))
        })
        .map_or(1, |value| value as u16);
    let file_type = detect_file_type(data);
    let exif = file_type.and_then(|kind| Metadata::new_from_vec(&data.to_vec(), kind).ok());
    let icc_profile = DynImage::from_bytes(Bytes::copy_from_slice(data))
        .ok()
        .flatten()
        .and_then(|image| image.icc_profile())
        .map(|bytes| bytes.to_vec())
        .or_else(|| extract_tiff_icc(data));
    ImageMetadata {
        exif,
        icc_profile,
        orientation,
    }
}

fn extract_tiff_icc(data: &[u8]) -> Option<Vec<u8>> {
    let is_tiff = data.starts_with(b"II\x2a\0") || data.starts_with(b"MM\0\x2a");
    if !is_tiff {
        return None;
    }
    let mut decoder = image::codecs::tiff::TiffDecoder::new(Cursor::new(data)).ok()?;
    decoder.icc_profile().ok().flatten()
}

/// Writes metadata according to the selected privacy policy. EXIF is written
/// to JPEG, PNG, WebP, TIFF and AVIF; ICC is written to JPEG, PNG and WebP.
pub fn inject_metadata(
    mut encoded: Vec<u8>,
    metadata: &ImageMetadata,
    policy: MetadataPolicy,
    preserve_icc: bool,
    output_format: OutputFormat,
    reset_orientation: bool,
) -> Vec<u8> {
    if policy != MetadataPolicy::None {
        if let Some(mut exif) = metadata.exif.clone() {
            if policy == MetadataPolicy::Safe {
                remove_sensitive_tags(&mut exif);
            }
            if reset_orientation {
                exif.remove_tag(ExifTag::Orientation(Vec::new()));
            }
            if let Some(file_type) = output_file_type(output_format) {
                let _ = exif.write_to_vec(&mut encoded, file_type);
            }
        }
    }

    if preserve_icc {
        if let Some(profile) = metadata.icc_profile.as_deref() {
            if let Ok(Some(mut image)) = DynImage::from_bytes(Bytes::from(encoded.clone())) {
                image.set_icc_profile(Some(Bytes::copy_from_slice(profile)));
                let mut result = Vec::with_capacity(image.len());
                if image.encoder().write_to(&mut result).is_ok() {
                    encoded = result;
                }
            }
        }
    }
    encoded
}

/// Removes location and common device/owner identifiers while retaining
/// photographic fields such as exposure, lens model and capture date.
fn remove_sensitive_tags(metadata: &mut Metadata) {
    for tag in 0x0000..=0x001f {
        metadata.remove_tag_by_hex_group(tag, ExifTagGroup::GPS);
    }
    for (tag, group) in [
        (0x013b, ExifTagGroup::GENERIC), // Artist
        (0x927c, ExifTagGroup::EXIF),    // MakerNote
        (0x9286, ExifTagGroup::EXIF),    // UserComment
        (0xa420, ExifTagGroup::EXIF),    // ImageUniqueID
        (0xa430, ExifTagGroup::EXIF),    // OwnerName
        (0xa431, ExifTagGroup::EXIF),    // SerialNumber
        (0xa435, ExifTagGroup::EXIF),    // LensSerialNumber
    ] {
        metadata.remove_tag_by_hex_group(tag, group);
    }
}

fn detect_file_type(data: &[u8]) -> Option<FileExtension> {
    FileExtension::auto_detect(&mut Cursor::new(data))
}

fn output_file_type(format: OutputFormat) -> Option<FileExtension> {
    match format {
        OutputFormat::Jpeg => Some(FileExtension::JPEG),
        OutputFormat::Png => Some(FileExtension::PNG {
            as_zTXt_chunk: false,
        }),
        OutputFormat::Webp => Some(FileExtension::WEBP),
        OutputFormat::Tiff => Some(FileExtension::TIFF),
        OutputFormat::Avif => Some(FileExtension::HEIF),
        OutputFormat::Bmp => None,
    }
}

/// Applies EXIF orientation and returns pixels in canonical orientation.
pub fn apply_orientation(img: &image::DynamicImage, orientation: u16) -> image::DynamicImage {
    match orientation {
        2 => img.fliph(),
        3 => img.rotate180(),
        4 => img.flipv(),
        5 => img.fliph().rotate90(),
        6 => img.rotate90(),
        7 => img.fliph().rotate270(),
        8 => img.rotate270(),
        _ => img.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn safe_policy_removes_identifiers_but_keeps_camera_model() {
        let mut metadata = Metadata::new();
        metadata.set_tag(ExifTag::OwnerName("private".into()));
        metadata.set_tag(ExifTag::SerialNumber("12345".into()));
        metadata.set_tag(ExifTag::Model("Camera model".into()));
        remove_sensitive_tags(&mut metadata);
        assert_eq!(
            metadata.get_tag(&ExifTag::OwnerName(String::new())).count(),
            0
        );
        assert_eq!(
            metadata
                .get_tag(&ExifTag::SerialNumber(String::new()))
                .count(),
            0
        );
        assert_eq!(metadata.get_tag(&ExifTag::Model(String::new())).count(), 1);
    }
}
