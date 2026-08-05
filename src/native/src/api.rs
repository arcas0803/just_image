//! FFI API — exported functions consumed from Dart via dart:ffi.
//!
//! Convention: all memory passed from Dart to Rust remains owned by Dart.
//! Result buffers are allocated in Rust and must be freed by Dart using
//! `rust_free_buffer` / `rust_free_error` / `rust_free_result`.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::slice;

use image::GenericImageView;

use crate::blurhash_bridge;
use crate::effects;
use crate::filters;
use crate::formats;
use crate::metadata;
use crate::pipeline::{Operation, OutputFormat, PipelineConfig};

use crate::thumbnail;
use crate::transforms;
use crate::watermark;

/// ABI version shared with the generated Dart bindings.
pub const ABI_VERSION: u32 = 1;

// ──────────────────────────────────────────────
// FFI result struct
// ──────────────────────────────────────────────

/// Result structure returned to Dart.
/// Dart reads the fields and then calls `rust_free_result` to release memory.
#[repr(C)]
pub struct FfiResult {
    /// Pointer to output bytes (owned by Rust until Dart frees them).
    pub data: *mut u8,
    /// Length of the output data.
    pub len: usize,
    /// Width of the resulting image in pixels.
    pub width: u32,
    /// Height of the resulting image in pixels.
    pub height: u32,
    /// Pointer to an error string (null on success). Owned by Rust.
    pub error: *mut c_char,
}

impl FfiResult {
    fn success(data: Vec<u8>, width: u32, height: u32) -> Self {
        let len = data.len();
        let ptr = Box::into_raw(data.into_boxed_slice()) as *mut u8;
        Self {
            data: ptr,
            len,
            width,
            height,
            error: std::ptr::null_mut(),
        }
    }

    fn error(msg: &str) -> Self {
        let c_msg = CString::new(msg).unwrap_or_else(|_| CString::new("Unknown error").unwrap());
        Self {
            data: std::ptr::null_mut(),
            len: 0,
            width: 0,
            height: 0,
            error: c_msg.into_raw(),
        }
    }
}

/// Returns the ABI version implemented by this native library.
#[no_mangle]
pub extern "C" fn rust_abi_version() -> u32 {
    ABI_VERSION
}

// ──────────────────────────────────────────────
// Error type
// ──────────────────────────────────────────────

#[derive(Debug)]
enum NativeError {
    InvalidInput(String),
    Decode(String),
    Encode(String),
    Pipeline(String),
}

impl std::fmt::Display for NativeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidInput(msg) => write!(f, "{msg}"),
            Self::Decode(msg) => write!(f, "Decode error: {msg}"),
            Self::Encode(msg) => write!(f, "Encode error: {msg}"),
            Self::Pipeline(msg) => write!(f, "Pipeline error: {msg}"),
        }
    }
}

impl From<std::str::Utf8Error> for NativeError {
    fn from(_: std::str::Utf8Error) -> Self {
        Self::InvalidInput("Invalid UTF-8 in input string".to_string())
    }
}

impl From<serde_json::Error> for NativeError {
    fn from(e: serde_json::Error) -> Self {
        Self::Pipeline(format!("Config parse error: {e}"))
    }
}

type NativeResult<T> = Result<T, NativeError>;

fn ffi_boundary<T, F>(operation: F) -> FfiResult
where
    T: Into<(Vec<u8>, u32, u32)>,
    F: FnOnce() -> NativeResult<T>,
{
    match catch_unwind(AssertUnwindSafe(operation)) {
        Ok(result) => to_ffi_result(result),
        Err(_) => FfiResult::error("Native panic while processing the image"),
    }
}

fn to_ffi_result<T>(result: NativeResult<T>) -> FfiResult
where
    T: Into<(Vec<u8>, u32, u32)>,
{
    match result {
        Ok(value) => {
            let (data, width, height) = value.into();
            FfiResult::success(data, width, height)
        }
        Err(e) => FfiResult::error(&e.to_string()),
    }
}

impl From<(Vec<u8>, u32, u32)> for FfiResult {
    fn from((data, width, height): (Vec<u8>, u32, u32)) -> Self {
        FfiResult::success(data, width, height)
    }
}

// ──────────────────────────────────────────────
// Main pipeline
// ──────────────────────────────────────────────

/// Processes an image through the full pipeline.
///
/// # Safety
/// - `input_ptr` must point to `input_len` valid bytes.
/// - `config_json` must be a valid UTF-8 C string.
/// - `watermark_ptr` may be null if no watermark is used.
#[no_mangle]
pub unsafe extern "C" fn rust_process_pipeline(
    input_ptr: *const u8,
    input_len: usize,
    config_json: *const c_char,
    watermark_ptr: *const u8,
    watermark_len: usize,
) -> FfiResult {
    ffi_boundary(|| {
        process_pipeline(
            input_ptr,
            input_len,
            config_json,
            watermark_ptr,
            watermark_len,
        )
    })
}

unsafe fn process_pipeline(
    input_ptr: *const u8,
    input_len: usize,
    config_json: *const c_char,
    watermark_ptr: *const u8,
    watermark_len: usize,
) -> NativeResult<(Vec<u8>, u32, u32)> {
    if input_ptr.is_null() || input_len == 0 {
        return Err(NativeError::InvalidInput(
            "Null or empty input buffer".to_string(),
        ));
    }
    if config_json.is_null() {
        return Err(NativeError::InvalidInput("Null config JSON".to_string()));
    }

    let input_data = slice::from_raw_parts(input_ptr, input_len);
    let config_str = CStr::from_ptr(config_json).to_str()?;
    let config: PipelineConfig = serde_json::from_str(config_str)?;
    config.validate().map_err(NativeError::InvalidInput)?;

    run_pipeline(input_data, &config, watermark_ptr, watermark_len)
}

fn run_pipeline(
    input_data: &[u8],
    config: &PipelineConfig,
    watermark_ptr: *const u8,
    watermark_len: usize,
) -> NativeResult<(Vec<u8>, u32, u32)> {
    let meta = if config.preserve_metadata || config.auto_orient || config.preserve_icc {
        metadata::extract_metadata(input_data)
    } else {
        metadata::ImageMetadata::default()
    };

    let mut img = formats::decode_image(input_data).map_err(NativeError::Decode)?;

    if config.auto_orient && meta.orientation > 1 {
        img = metadata::apply_orientation(&img, meta.orientation);
    }

    if config.preserve_icc {
        if let Some(ref icc) = meta.icc_profile {
            let mut rgba = img.to_rgba8();
            let (w, h) = rgba.dimensions();
            let _ = crate::color::apply_icc_transform(rgba.as_mut(), w, h, icc, true);
            img = image::DynamicImage::ImageRgba8(rgba);
        }
    }

    for op in &config.operations {
        img = apply_operation(&img, op, watermark_ptr, watermark_len)?;
    }

    if config.preserve_icc {
        if let Some(ref icc) = meta.icc_profile {
            let mut rgba = img.to_rgba8();
            let (w, h) = rgba.dimensions();
            let _ = crate::color::apply_icc_transform(rgba.as_mut(), w, h, icc, false);
            img = image::DynamicImage::ImageRgba8(rgba);
        }
    }

    let (w, h) = img.dimensions();
    let mut encoded = formats::encode_to_format(&img, config.output_format, config.quality)
        .map_err(NativeError::Encode)?;

    if config.output_format == OutputFormat::Jpeg
        && (config.preserve_metadata || config.preserve_icc)
    {
        encoded = metadata::inject_metadata_jpeg(
            &encoded,
            if config.preserve_metadata {
                meta.exif_data.as_deref()
            } else {
                None
            },
            if config.preserve_icc {
                meta.icc_profile.as_deref()
            } else {
                None
            },
        );
    }

    Ok((encoded, w, h))
}

fn apply_operation(
    img: &image::DynamicImage,
    op: &Operation,
    watermark_ptr: *const u8,
    watermark_len: usize,
) -> NativeResult<image::DynamicImage> {
    let result = match op {
        Operation::Resize { width, height } => transforms::resize_lanczos3(img, *width, *height),
        Operation::Crop {
            x,
            y,
            width,
            height,
        } => {
            let right = x.checked_add(*width);
            let bottom = y.checked_add(*height);
            if right.is_none_or(|right| right > img.width())
                || bottom.is_none_or(|bottom| bottom > img.height())
            {
                return Err(NativeError::Pipeline(format!(
                    "Crop ({x}, {y}, {width}, {height}) exceeds image bounds {}x{}",
                    img.width(),
                    img.height()
                )));
            }
            transforms::crop(img, *x, *y, *width, *height)
        }
        Operation::Rotate { degrees } => transforms::rotate(img, *degrees),
        Operation::FlipHorizontal => transforms::flip_horizontal(img),
        Operation::FlipVertical => transforms::flip_vertical(img),
        Operation::GaussianBlur { sigma } => effects::gaussian_blur(img, *sigma),
        Operation::UnsharpMask { amount, threshold } => {
            effects::unsharp_mask(img, *amount, *threshold)
        }
        Operation::Sobel => effects::sobel_edges(img),
        Operation::Brightness { value } => effects::adjust_brightness(img, *value),
        Operation::Contrast { value } => effects::adjust_contrast(img, *value),
        Operation::HslAdjust {
            hue,
            saturation,
            lightness,
        } => effects::adjust_hsl(img, *hue, *saturation, *lightness),
        Operation::Watermark { x, y, opacity } => {
            if watermark_ptr.is_null() || watermark_len == 0 {
                return Err(NativeError::Pipeline(
                    "Watermark operation requires watermark data".to_string(),
                ));
            }
            let wm_data = unsafe { slice::from_raw_parts(watermark_ptr, watermark_len) };
            watermark::apply_watermark(img, wm_data, *x, *y, *opacity)
                .map_err(NativeError::Pipeline)?
        }
        Operation::Filter { name } => {
            filters::apply_filter(img, *name).map_err(NativeError::Pipeline)?
        }
        Operation::Thumbnail {
            max_width,
            max_height,
        } => thumbnail::generate_thumbnail(img, *max_width, *max_height),
    };
    Ok(result)
}

// ──────────────────────────────────────────────
// Memory management
// ──────────────────────────────────────────────

/// Frees the data buffer returned by `rust_process_pipeline`.
///
/// # Safety
/// - `ptr` must have been obtained from a previous `FfiResult.data`.
/// - `len` must match the original `FfiResult.len`.
#[no_mangle]
pub unsafe extern "C" fn rust_free_buffer(ptr: *mut u8, len: usize) {
    if !ptr.is_null() && len > 0 {
        let _ = Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len));
    }
}

/// Frees the error string returned by `FfiResult.error`.
///
/// # Safety
/// - `ptr` must have been obtained from a previous `FfiResult.error`.
#[no_mangle]
pub unsafe extern "C" fn rust_free_error(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = CString::from_raw(ptr);
    }
}

/// Frees a complete `FfiResult` (both data and error string).
///
/// # Safety
/// - `result` must be a valid `FfiResult` obtained from `rust_process_pipeline`.
#[no_mangle]
#[allow(dead_code)]
pub unsafe extern "C" fn rust_free_result(result: FfiResult) {
    rust_free_buffer(result.data, result.len);
    rust_free_error(result.error);
}

// ──────────────────────────────────────────────
// Utilities
// ──────────────────────────────────────────────

/// Returns the native library version string.
#[no_mangle]
pub extern "C" fn rust_version() -> *mut c_char {
    let v = CString::new(env!("CARGO_PKG_VERSION")).unwrap();
    v.into_raw()
}

/// Frees the version string returned by `rust_version`.
///
/// # Safety
/// - `ptr` must be the pointer returned by `rust_version`.
#[no_mangle]
pub unsafe extern "C" fn rust_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = CString::from_raw(ptr);
    }
}

/// Reads basic image info (dimensions, detected format) without processing.
///
/// # Safety
/// - `input_ptr` must point to `input_len` valid bytes.
#[no_mangle]
pub unsafe extern "C" fn rust_image_info(input_ptr: *const u8, input_len: usize) -> FfiResult {
    ffi_boundary(|| image_info(input_ptr, input_len))
}

unsafe fn image_info(input_ptr: *const u8, input_len: usize) -> NativeResult<(Vec<u8>, u32, u32)> {
    if input_ptr.is_null() || input_len == 0 {
        return Err(NativeError::InvalidInput(
            "Null or empty input buffer".to_string(),
        ));
    }
    let input_data = slice::from_raw_parts(input_ptr, input_len);
    let img = formats::decode_image(input_data).map_err(NativeError::Decode)?;
    let (w, h) = img.dimensions();
    let info = serde_json::json!({"width": w, "height": h});
    Ok((info.to_string().into_bytes(), w, h))
}

// ──────────────────────────────────────────────
// BlurHash
// ──────────────────────────────────────────────

/// Encodes an image into a BlurHash string.
/// The hash is returned as UTF-8 bytes in `FfiResult.data`.
///
/// # Safety
/// - `input_ptr` must point to `input_len` valid image bytes.
#[no_mangle]
pub unsafe extern "C" fn rust_blurhash_encode(
    input_ptr: *const u8,
    input_len: usize,
    components_x: u32,
    components_y: u32,
) -> FfiResult {
    ffi_boundary(|| blurhash_encode(input_ptr, input_len, components_x, components_y))
}

unsafe fn blurhash_encode(
    input_ptr: *const u8,
    input_len: usize,
    components_x: u32,
    components_y: u32,
) -> NativeResult<(Vec<u8>, u32, u32)> {
    if input_ptr.is_null() || input_len == 0 {
        return Err(NativeError::InvalidInput(
            "Null or empty input buffer".to_string(),
        ));
    }
    if !(1..=9).contains(&components_x) || !(1..=9).contains(&components_y) {
        return Err(NativeError::InvalidInput(format!(
            "BlurHash components must be between 1 and 9, got {components_x}x{components_y}"
        )));
    }

    let input_data = slice::from_raw_parts(input_ptr, input_len);
    let img = formats::decode_image(input_data).map_err(NativeError::Decode)?;
    let hash = blurhash_bridge::encode_blurhash(&img, components_x, components_y)
        .map_err(NativeError::Encode)?;
    let (w, h) = img.dimensions();
    Ok((hash.into_bytes(), w, h))
}

/// Decodes a BlurHash string into PNG image bytes.
///
/// # Safety
/// - `hash_ptr` must be a valid UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn rust_blurhash_decode(
    hash_ptr: *const c_char,
    width: u32,
    height: u32,
) -> FfiResult {
    ffi_boundary(|| blurhash_decode(hash_ptr, width, height))
}

unsafe fn blurhash_decode(
    hash_ptr: *const c_char,
    width: u32,
    height: u32,
) -> NativeResult<(Vec<u8>, u32, u32)> {
    if hash_ptr.is_null() {
        return Err(NativeError::InvalidInput(
            "Null BlurHash string".to_string(),
        ));
    }
    if width == 0 || height == 0 {
        return Err(NativeError::InvalidInput(format!(
            "BlurHash dimensions must be positive, got {width}x{height}"
        )));
    }

    let hash_str = CStr::from_ptr(hash_ptr).to_str()?;
    let img =
        blurhash_bridge::decode_blurhash(hash_str, width, height).map_err(NativeError::Decode)?;
    let png_bytes =
        formats::encode_to_format(&img, OutputFormat::Png, 100).map_err(NativeError::Encode)?;
    Ok((png_bytes, width, height))
}

/// Returns the available artistic filter names as a JSON array string.
#[no_mangle]
pub extern "C" fn rust_available_filters() -> *mut c_char {
    let names = filters::available_filters();
    let json = serde_json::to_string(&names).unwrap_or_else(|_| "[]".to_string());
    let c_str = CString::new(json).unwrap_or_else(|_| CString::new("[]").unwrap());
    c_str.into_raw()
}
