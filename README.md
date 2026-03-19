# just_image

Monorepo de procesamiento de imágenes para Dart y Flutter, impulsado por un núcleo Rust vía FFI y Native Assets.

## Qué incluye

Este repositorio se divide en tres paquetes independientes:

| Paquete | Rol |
|---|---|
| [`just_image`](packages/just_image/) | Núcleo de la librería. Expone la API de procesamiento, el puente FFI y la compilación nativa automática. |
| [`just_image_cli`](packages/just_image_cli/) | Interfaz de línea de comandos para convertir, transformar e inspeccionar imágenes desde terminal. |
| [`just_image_flutter`](packages/just_image_flutter/) | Plugin Flutter sin widgets ni UI. Solo activa `ffiPlugin: true` para que Flutter empaquete el binario nativo. |

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

## Cómo se usa cada paquete

- `just_image`: para proyectos Dart, servidores, herramientas y cualquier runtime Dart sin Flutter
- `just_image_cli`: para uso desde terminal y scripts de automatización
- `just_image_flutter`: para apps Flutter que quieran reutilizar la misma API de `just_image`

## Ejemplo rápido

```dart
import 'package:just_image/just_image.dart';

// Pipeline con filtro artístico y thumbnail
final result = await ImagePipeline(imageBytes)
    .filter('cinematic')
    .thumbnail(400, 300)
    .toFormat(ImageFormat.webp)
    .quality(85)
    .execute();

// BlurHash para placeholders
final engine = JustImageEngine();
final hash = await engine.blurHashEncode(imageBytes);
print(hash); // ej: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
```

## Licencia

MIT
