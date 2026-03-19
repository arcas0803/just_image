use serde::{Deserialize, Serialize};

/// Configuración completa del pipeline de procesamiento.
/// Se pasa desde Dart como JSON serializado.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PipelineConfig {
    /// Formato de salida: "jpeg", "png", "webp", "avif", "tiff", "bmp"
    pub output_format: String,
    /// Calidad de compresión (1-100)
    pub quality: u8,
    /// Auto-orientar según EXIF
    pub auto_orient: bool,
    /// Preservar metadatos EXIF
    pub preserve_metadata: bool,
    /// Preservar perfil ICC
    pub preserve_icc: bool,
    /// Lista ordenada de operaciones a aplicar
    pub operations: Vec<Operation>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum Operation {
    #[serde(rename = "resize")]
    Resize { width: u32, height: u32 },
    #[serde(rename = "crop")]
    Crop { x: u32, y: u32, width: u32, height: u32 },
    #[serde(rename = "rotate")]
    Rotate { degrees: f64 },
    #[serde(rename = "flip_horizontal")]
    FlipHorizontal,
    #[serde(rename = "flip_vertical")]
    FlipVertical,
    #[serde(rename = "blur")]
    GaussianBlur { sigma: f32 },
    #[serde(rename = "sharpen")]
    UnsharpMask { amount: f32, threshold: f32 },
    #[serde(rename = "sobel")]
    Sobel,
    #[serde(rename = "brightness")]
    Brightness { value: f32 },
    #[serde(rename = "contrast")]
    Contrast { value: f32 },
    #[serde(rename = "hsl")]
    HslAdjust { hue: f32, saturation: f32, lightness: f32 },
    #[serde(rename = "watermark")]
    Watermark {
        /// Puntero y longitud del overlay se pasan por separado
        x: i32,
        y: i32,
        opacity: f32,
    },
    #[serde(rename = "filter")]
    Filter { name: String },
    #[serde(rename = "thumbnail")]
    Thumbnail { max_width: u32, max_height: u32 },
}

impl Default for PipelineConfig {
    fn default() -> Self {
        Self {
            output_format: "jpeg".to_string(),
            quality: 90,
            auto_orient: true,
            preserve_metadata: true,
            preserve_icc: true,
            operations: Vec::new(),
        }
    }
}

/// Resultado devuelto al caller (Dart) con el buffer de salida.
#[derive(Debug)]
pub struct ProcessingResult {
    pub data: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub format: String,
    pub error: Option<String>,
}
