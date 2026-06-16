# just_image

Monorepo de procesamiento de imágenes para Dart y Flutter, impulsado por un núcleo Rust vía FFI y Native Assets.

## Qué incluye

Este repositorio contiene el paquete [`just_image`](packages/just_image/): el núcleo de la librería de procesamiento de imágenes. Expone la API de procesamiento, el puente FFI y la compilación nativa automática para cualquier entorno Dart (CLI, servidores, Flutter, etc.) gracias a su `hook/build.dart` de Native Assets.

> Los antiguos paquetes `just_image_cli` e `just_image_flutter` han sido **discontinuados** en pub.dev; se usa `just_image` directamente.

## Capacidades principales

- **Formatos**: AVIF, WebP, JPEG, PNG, TIFF y BMP
- **Transformaciones**: resize, crop, rotate, flip y thumbnail
- **Efectos**: blur, sharpen, sobel, brightness, contrast y HSL
- **15 filtros artísticos**: vintage, sepia, cool, warm, marine, dramatic, lomo, retro, noir, bloom, polaroid, golden_hour, arctic, cinematic, fade
- **BlurHash**: codificación y decodificación de placeholders compactos
- **Metadatos**: orientación EXIF y preservación de ICC
- **Marca de agua**: overlay con posición y opacidad
- **Motor Rust** con paralelismo (rayon) y SIMD
- **Compilación nativa automática** con Native Assets

> HEIC no está soportado actualmente.

## Uso

`just_image` es el único paquete necesario para proyectos Dart, servidores, herramientas **y apps Flutter**.

## Ejemplo rápido

```yaml
dependencies:
  just_image: ^1.0.3
```

```dart
import 'package:just_image/just_image.dart';

// Pipeline con filtro artístico y thumbnail
final result = await imageBytes
    .justImage
    .filter(ArtisticFilterName.cinematic)
    .thumbnail(400, 300)
    .encode(const WebpOutput(quality: 85))
    .run();

// Desde File o XFile
final result2 = await File('photo.jpg')
    .justImage
    .resize(800, 600)
    .encode(const JpegOutput(quality: 90))
    .run();

// BlurHash para placeholders
final hash = await JustImage.blurHashEncode(BytesSource(imageBytes));
print(hash); // ej: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"

// Batch homogéneo
final results = await JustImage.processBatch([
  file1.justImage.resize(100, 100).encode(const JpegOutput()),
  file2.justImage.resize(100, 100).encode(const JpegOutput()),
], concurrency: 4);
```

### Flutter

```bash
flutter run --enable-experiment=native-assets
```

### Dart CLI / servidores

```bash
dart --enable-experiment=native-assets run bin/main.dart
```

## Licencia

MIT
