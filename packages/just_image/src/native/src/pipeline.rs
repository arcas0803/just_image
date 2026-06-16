use serde::{Deserialize, Serialize};

/// Complete image processing pipeline configuration.
/// Passed from Dart as serialized JSON.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PipelineConfig {
    /// Output image format.
    pub output_format: OutputFormat,
    /// Compression quality (1-100).
    pub quality: u8,
    /// Auto-orient according to EXIF.
    pub auto_orient: bool,
    /// Preserve EXIF metadata.
    pub preserve_metadata: bool,
    /// Preserve ICC colour profile.
    pub preserve_icc: bool,
    /// Ordered list of operations to apply.
    pub operations: Vec<Operation>,
}

impl Default for PipelineConfig {
    fn default() -> Self {
        Self {
            output_format: OutputFormat::Jpeg,
            quality: 90,
            auto_orient: true,
            preserve_metadata: true,
            preserve_icc: true,
            operations: Vec::new(),
        }
    }
}

/// Supported output image formats.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum OutputFormat {
    Jpeg,
    Png,
    Webp,
    Avif,
    Tiff,
    Bmp,
}

impl OutputFormat {
    /// Returns the canonical string representation used in FFI/JSON.
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Jpeg => "jpeg",
            Self::Png => "png",
            Self::Webp => "webp",
            Self::Avif => "avif",
            Self::Tiff => "tiff",
            Self::Bmp => "bmp",
        }
    }
}

/// Available artistic filters.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ArtisticFilter {
    Vintage,
    Sepia,
    Cool,
    Warm,
    Marine,
    Dramatic,
    Lomo,
    Retro,
    Noir,
    Bloom,
    Polaroid,
    #[serde(rename = "golden_hour")]
    GoldenHour,
    Arctic,
    Cinematic,
    Fade,
}

impl ArtisticFilter {
    /// All available artistic filters.
    pub const ALL: [Self; 15] = [
        Self::Vintage,
        Self::Sepia,
        Self::Cool,
        Self::Warm,
        Self::Marine,
        Self::Dramatic,
        Self::Lomo,
        Self::Retro,
        Self::Noir,
        Self::Bloom,
        Self::Polaroid,
        Self::GoldenHour,
        Self::Arctic,
        Self::Cinematic,
        Self::Fade,
    ];

    /// Returns the canonical snake_case name.
    pub fn name(&self) -> &'static str {
        match self {
            Self::Vintage => "vintage",
            Self::Sepia => "sepia",
            Self::Cool => "cool",
            Self::Warm => "warm",
            Self::Marine => "marine",
            Self::Dramatic => "dramatic",
            Self::Lomo => "lomo",
            Self::Retro => "retro",
            Self::Noir => "noir",
            Self::Bloom => "bloom",
            Self::Polaroid => "polaroid",
            Self::GoldenHour => "golden_hour",
            Self::Arctic => "arctic",
            Self::Cinematic => "cinematic",
            Self::Fade => "fade",
        }
    }
}

/// A single processing operation in the pipeline.
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
        x: i32,
        y: i32,
        opacity: f32,
    },
    #[serde(rename = "filter")]
    Filter { name: ArtisticFilter },
    #[serde(rename = "thumbnail")]
    Thumbnail { max_width: u32, max_height: u32 },
}
