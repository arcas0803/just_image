use serde::{Deserialize, Serialize};

/// Complete image processing pipeline configuration.
/// Passed from Dart as serialized JSON.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PipelineConfig {
    /// Explicit input format for codecs that are intentionally kept out of
    /// the lightweight auto-detect path.
    #[serde(default)]
    pub input_format: InputFormat,
    /// Output image format.
    pub output_format: OutputFormat,
    /// Compression quality (1-100).
    pub quality: u8,
    /// Auto-orient according to EXIF.
    pub auto_orient: bool,
    /// Preserve EXIF metadata.
    pub preserve_metadata: bool,
    /// Fine-grained metadata policy used by the v3 API.
    #[serde(default)]
    pub metadata_policy: MetadataPolicy,
    /// Preserve ICC colour profile.
    pub preserve_icc: bool,
    /// SVG raster width. The intrinsic aspect ratio is retained when only one
    /// dimension is specified.
    #[serde(default)]
    pub svg_width: Option<u32>,
    #[serde(default)]
    pub svg_height: Option<u32>,
    #[serde(default)]
    pub png_compression: PngCompression,
    #[serde(default)]
    pub png_filter: PngFilter,
    #[serde(default)]
    pub png_optimization: u8,
    #[serde(default)]
    pub webp_lossless: bool,
    #[serde(default = "default_avif_speed")]
    pub avif_speed: u8,
    #[serde(default)]
    pub avif_threads: Option<usize>,
    /// Ordered list of operations to apply.
    pub operations: Vec<Operation>,
}

impl Default for PipelineConfig {
    fn default() -> Self {
        Self {
            input_format: InputFormat::Auto,
            output_format: OutputFormat::Jpeg,
            quality: 90,
            auto_orient: true,
            preserve_metadata: true,
            metadata_policy: MetadataPolicy::PreserveAll,
            preserve_icc: true,
            svg_width: None,
            svg_height: None,
            png_compression: PngCompression::Balanced,
            png_filter: PngFilter::Adaptive,
            png_optimization: 0,
            webp_lossless: false,
            avif_speed: default_avif_speed(),
            avif_threads: None,
            operations: Vec::new(),
        }
    }
}

impl PipelineConfig {
    /// Resolves the v2 boolean into the v3 policy for older callers.
    pub fn effective_metadata_policy(&self) -> MetadataPolicy {
        if self.metadata_policy == MetadataPolicy::None && self.preserve_metadata {
            MetadataPolicy::PreserveAll
        } else {
            self.metadata_policy
        }
    }

    /// Validates values received over FFI before allocating image buffers.
    pub fn validate(&self) -> Result<(), String> {
        if !(1..=100).contains(&self.quality) {
            return Err(format!(
                "quality must be between 1 and 100, got {}",
                self.quality
            ));
        }
        if self.png_optimization > 6 {
            return Err(format!(
                "png_optimization must be between 0 and 6, got {}",
                self.png_optimization
            ));
        }
        if !(1..=10).contains(&self.avif_speed) {
            return Err(format!(
                "avif_speed must be between 1 and 10, got {}",
                self.avif_speed
            ));
        }
        if self.avif_threads == Some(0) {
            return Err("avif_threads must be positive".into());
        }
        if matches!(self.input_format, InputFormat::Svg)
            && (self.svg_width == Some(0) || self.svg_height == Some(0))
        {
            return Err("SVG raster dimensions must be positive".into());
        }

        for operation in &self.operations {
            match operation {
                Operation::Resize { width, height } | Operation::Crop { width, height, .. } => {
                    require_dimensions(*width, *height)?;
                }
                Operation::Thumbnail {
                    max_width,
                    max_height,
                } => require_dimensions(*max_width, *max_height)?,
                Operation::GaussianBlur { sigma } if !sigma.is_finite() || *sigma < 0.0 => {
                    return Err(format!(
                        "sigma must be finite and non-negative, got {sigma}"
                    ));
                }
                Operation::UnsharpMask { amount, threshold }
                    if !amount.is_finite()
                        || !threshold.is_finite()
                        || *amount < 0.0
                        || *threshold < 0.0 =>
                {
                    return Err(
                        "sharpen amount and threshold must be finite and non-negative".into(),
                    );
                }
                Operation::Brightness { value } | Operation::Contrast { value }
                    if !(-1.0..=1.0).contains(value) =>
                {
                    return Err(format!("adjustment must be between -1 and 1, got {value}"));
                }
                Operation::HslAdjust {
                    hue,
                    saturation,
                    lightness,
                } if !hue.is_finite()
                    || !(-1.0..=1.0).contains(saturation)
                    || !(-1.0..=1.0).contains(lightness) =>
                {
                    return Err("invalid HSL adjustment".into());
                }
                Operation::Watermark { opacity, .. } if !(0.0..=1.0).contains(opacity) => {
                    return Err(format!(
                        "watermark opacity must be between 0 and 1, got {opacity}"
                    ));
                }
                Operation::Rotate { degrees, .. } if !degrees.is_finite() => {
                    return Err("rotation must be finite".into());
                }
                _ => {}
            }
        }
        Ok(())
    }
}

const fn default_avif_speed() -> u8 {
    6
}

/// Input codecs that require the extended native entry point.
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum InputFormat {
    #[default]
    Auto,
    Avif,
    Svg,
}

/// Metadata retention and privacy policy.
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MetadataPolicy {
    #[default]
    None,
    Safe,
    PreserveAll,
}

/// PNG compression effort.
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum PngCompression {
    Fast,
    #[default]
    Balanced,
    Best,
}

/// PNG scanline filtering strategy.
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum PngFilter {
    #[default]
    Adaptive,
    None,
    Sub,
    Up,
    Average,
    Paeth,
}

/// Canvas behavior for arbitrary rotations.
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum RotationCanvas {
    Clip,
    #[default]
    Expand,
}

fn require_dimensions(width: u32, height: u32) -> Result<(), String> {
    if width == 0 || height == 0 {
        return Err(format!("dimensions must be positive, got {width}x{height}"));
    }
    Ok(())
}

/// Supported output image formats.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum OutputFormat {
    Jpeg,
    Png,
    Webp,
    Tiff,
    Bmp,
    Avif,
}

impl OutputFormat {
    /// Returns the canonical string representation used in FFI/JSON.
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Jpeg => "jpeg",
            Self::Png => "png",
            Self::Webp => "webp",
            Self::Tiff => "tiff",
            Self::Bmp => "bmp",
            Self::Avif => "avif",
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
    Crop {
        x: u32,
        y: u32,
        width: u32,
        height: u32,
    },
    #[serde(rename = "rotate")]
    Rotate {
        degrees: f64,
        #[serde(default)]
        canvas: RotationCanvas,
        #[serde(default)]
        background: u32,
    },
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
    HslAdjust {
        hue: f32,
        saturation: f32,
        lightness: f32,
    },
    #[serde(rename = "watermark")]
    Watermark { x: i32, y: i32, opacity: f32 },
    #[serde(rename = "filter")]
    Filter { name: ArtisticFilter },
    #[serde(rename = "thumbnail")]
    Thumbnail { max_width: u32, max_height: u32 },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_config_is_valid() {
        assert!(PipelineConfig::default().validate().is_ok());
    }

    #[test]
    fn rejects_zero_sized_operations() {
        let config = PipelineConfig {
            operations: vec![Operation::Resize {
                width: 0,
                height: 10,
            }],
            ..PipelineConfig::default()
        };
        assert!(config.validate().is_err());
    }

    #[test]
    fn rejects_invalid_effect_ranges() {
        let config = PipelineConfig {
            operations: vec![Operation::Brightness { value: 2.0 }],
            ..PipelineConfig::default()
        };
        assert!(config.validate().is_err());
    }
}
