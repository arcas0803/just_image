//! FFI API — Funciones exportadas para consumo desde Dart via dart:ffi.
//!
//! Convención: Toda memoria que Dart pasa a Rust sigue siendo propiedad de Dart.
//! Los buffers de resultado se alocan en Rust y Dart debe liberarlos con `rust_free_buffer`.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::slice;

use image::GenericImageView;

use crate::effects;
use crate::formats;
use crate::metadata;
use crate::pipeline::{Operation, PipelineConfig};
use crate::transforms;
use crate::watermark;

// ──────────────────────────────────────────────
// Resultado FFI
// ──────────────────────────────────────────────

/// Estructura de resultado devuelta a Dart.
/// Dart lee los campos y luego llama a `rust_free_result` para liberar.
#[repr(C)]
pub struct FfiResult {
    /// Puntero a los bytes de salida (propiedad de Rust hasta que Dart llame free).
    pub data: *mut u8,
    /// Longitud de los datos.
    pub len: usize,
    /// Ancho de la imagen resultante.
    pub width: u32,
    /// Alto de la imagen resultante.
    pub height: u32,
    /// Puntero a string de error (null si éxito). Propiedad de Rust.
    pub error: *mut c_char,
}

impl FfiResult {
    fn success(data: Vec<u8>, width: u32, height: u32) -> Self {
        let len = data.len();
        let boxed = data.into_boxed_slice();
        let ptr = Box::into_raw(boxed) as *mut u8;
        FfiResult {
            data: ptr,
            len,
            width,
            height,
            error: std::ptr::null_mut(),
        }
    }

    fn error(msg: &str) -> Self {
        let c_msg = CString::new(msg).unwrap_or_else(|_| CString::new("Unknown error").unwrap());
        FfiResult {
            data: std::ptr::null_mut(),
            len: 0,
            width: 0,
            height: 0,
            error: c_msg.into_raw(),
        }
    }
}

// ──────────────────────────────────────────────
// Pipeline principal
// ──────────────────────────────────────────────

/// Procesa una imagen completa a través del pipeline.
///
/// # Safety
/// - `input_ptr` debe apuntar a `input_len` bytes válidos.
/// - `config_json` debe ser un C-string UTF-8 válido.
/// - `watermark_ptr` puede ser null si no hay watermark.
#[no_mangle]
pub unsafe extern "C" fn rust_process_pipeline(
    input_ptr: *const u8,
    input_len: usize,
    config_json: *const c_char,
    watermark_ptr: *const u8,
    watermark_len: usize,
) -> FfiResult {
    // Validar punteros
    if input_ptr.is_null() || input_len == 0 {
        return FfiResult::error("Null or empty input buffer");
    }
    if config_json.is_null() {
        return FfiResult::error("Null config JSON");
    }

    // Leer input como slice (sin copiar — zero-copy)
    let input_data = slice::from_raw_parts(input_ptr, input_len);

    // Parsear configuración
    let config_str = match CStr::from_ptr(config_json).to_str() {
        Ok(s) => s,
        Err(_) => return FfiResult::error("Invalid UTF-8 in config JSON"),
    };

    let config: PipelineConfig = match serde_json::from_str(config_str) {
        Ok(c) => c,
        Err(e) => return FfiResult::error(&format!("Config parse error: {e}")),
    };

    // Ejecutar pipeline
    match process_pipeline_inner(input_data, &config, watermark_ptr, watermark_len) {
        Ok((data, w, h)) => FfiResult::success(data, w, h),
        Err(e) => FfiResult::error(&e),
    }
}

fn process_pipeline_inner(
    input_data: &[u8],
    config: &PipelineConfig,
    watermark_ptr: *const u8,
    watermark_len: usize,
) -> Result<(Vec<u8>, u32, u32), String> {
    // 1. Extraer metadatos antes de decodificar
    let meta = if config.preserve_metadata || config.auto_orient || config.preserve_icc {
        metadata::extract_metadata(input_data)
    } else {
        metadata::ImageMetadata::default()
    };

    // 2. Decodificar imagen (usa zune-jpeg para JPEG rápido)
    let mut img = formats::decode_image(input_data)?;

    // 3. Auto-orientación EXIF
    if config.auto_orient && meta.orientation > 1 {
        img = metadata::apply_orientation(&img, meta.orientation);
    }

    // 4. Convertir a espacio de trabajo sRGB si hay ICC
    if config.preserve_icc {
        if let Some(ref icc) = meta.icc_profile {
            let mut rgba = img.to_rgba8();
            let (w, h) = rgba.dimensions();
            let _ = crate::color::apply_icc_transform(rgba.as_mut(), w, h, icc, true);
            img = image::DynamicImage::ImageRgba8(rgba);
        }
    }

    // 5. Aplicar operaciones del pipeline en orden
    for op in &config.operations {
        img = apply_operation(&img, op, watermark_ptr, watermark_len)?;
    }

    // 6. Reconvertir desde sRGB al perfil ICC original
    if config.preserve_icc {
        if let Some(ref icc) = meta.icc_profile {
            let mut rgba = img.to_rgba8();
            let (w, h) = rgba.dimensions();
            let _ = crate::color::apply_icc_transform(rgba.as_mut(), w, h, icc, false);
            img = image::DynamicImage::ImageRgba8(rgba);
        }
    }

    let (w, h) = img.dimensions();

    // 7. Codificar al formato de salida
    let mut encoded = formats::encode_to_format(&img, &config.output_format, config.quality)?;

    // 8. Re-inyectar metadatos si es JPEG
    if config.preserve_metadata
        && (config.output_format == "jpeg" || config.output_format == "jpg")
    {
        encoded = metadata::inject_metadata_jpeg(
            &encoded,
            meta.exif_data.as_deref(),
            meta.icc_profile.as_deref(),
        );
    }

    Ok((encoded, w, h))
}

fn apply_operation(
    img: &image::DynamicImage,
    op: &Operation,
    watermark_ptr: *const u8,
    watermark_len: usize,
) -> Result<image::DynamicImage, String> {
    match op {
        Operation::Resize { width, height } => {
            Ok(transforms::resize_lanczos3(img, *width, *height))
        }
        Operation::Crop {
            x,
            y,
            width,
            height,
        } => Ok(transforms::crop(img, *x, *y, *width, *height)),
        Operation::Rotate { degrees } => Ok(transforms::rotate(img, *degrees)),
        Operation::FlipHorizontal => Ok(transforms::flip_horizontal(img)),
        Operation::FlipVertical => Ok(transforms::flip_vertical(img)),
        Operation::GaussianBlur { sigma } => Ok(effects::gaussian_blur(img, *sigma)),
        Operation::UnsharpMask { amount, threshold } => {
            Ok(effects::unsharp_mask(img, *amount, *threshold))
        }
        Operation::Sobel => Ok(effects::sobel_edges(img)),
        Operation::Brightness { value } => Ok(effects::adjust_brightness(img, *value)),
        Operation::Contrast { value } => Ok(effects::adjust_contrast(img, *value)),
        Operation::HslAdjust {
            hue,
            saturation,
            lightness,
        } => Ok(effects::adjust_hsl(img, *hue, *saturation, *lightness)),
        Operation::Watermark { x, y, opacity } => {
            if watermark_ptr.is_null() || watermark_len == 0 {
                return Err("Watermark operation requires watermark data".to_string());
            }
            let wm_data = unsafe { slice::from_raw_parts(watermark_ptr, watermark_len) };
            watermark::apply_watermark(img, wm_data, *x, *y, *opacity)
        }
    }
}

// ──────────────────────────────────────────────
// Gestión de memoria
// ──────────────────────────────────────────────

/// Libera el buffer de datos devuelto por `rust_process_pipeline`.
///
/// # Safety
/// - `ptr` debe haber sido obtenido de un `FfiResult.data` previo.
/// - `len` debe coincidir con el `FfiResult.len` original.
#[no_mangle]
pub unsafe extern "C" fn rust_free_buffer(ptr: *mut u8, len: usize) {
    if !ptr.is_null() && len > 0 {
        let _ = Box::from_raw(slice::from_raw_parts_mut(ptr, len));
    }
}

/// Libera el string de error devuelto por `FfiResult.error`.
///
/// # Safety
/// - `ptr` debe haber sido obtenido de un `FfiResult.error` previo.
#[no_mangle]
pub unsafe extern "C" fn rust_free_error(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = CString::from_raw(ptr);
    }
}

/// Libera un FfiResult completo (data + error string).
///
/// # Safety
/// - `result` debe ser un FfiResult válido obtenido de `rust_process_pipeline`.
#[no_mangle]
pub unsafe extern "C" fn rust_free_result(result: FfiResult) {
    rust_free_buffer(result.data, result.len);
    rust_free_error(result.error);
}

// ──────────────────────────────────────────────
// Utilidades
// ──────────────────────────────────────────────

/// Devuelve la versión de la librería nativa.
#[no_mangle]
pub extern "C" fn rust_version() -> *mut c_char {
    let v = CString::new(env!("CARGO_PKG_VERSION")).unwrap();
    v.into_raw()
}

/// Libera el string de versión.
///
/// # Safety
/// - `ptr` debe ser el puntero devuelto por `rust_version`.
#[no_mangle]
pub unsafe extern "C" fn rust_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = CString::from_raw(ptr);
    }
}

/// Obtiene info de la imagen sin procesarla (dimensiones, formato detectado).
///
/// # Safety
/// - `input_ptr` debe apuntar a `input_len` bytes válidos.
#[no_mangle]
pub unsafe extern "C" fn rust_image_info(
    input_ptr: *const u8,
    input_len: usize,
) -> FfiResult {
    if input_ptr.is_null() || input_len == 0 {
        return FfiResult::error("Null or empty input buffer");
    }

    let input_data = slice::from_raw_parts(input_ptr, input_len);

    match formats::decode_image(input_data) {
        Ok(img) => {
            let (w, h) = img.dimensions();
            let info = serde_json::json!({
                "width": w,
                "height": h,
            });
            let json_bytes = info.to_string().into_bytes();
            FfiResult::success(json_bytes, w, h)
        }
        Err(e) => FfiResult::error(&e),
    }
}
