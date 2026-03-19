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

- Formatos soportados: AVIF, WebP, JPEG, PNG, TIFF y BMP
- Transformaciones: resize, crop, rotate y flip
- Efectos: blur, sharpen, sobel, brightness, contrast y HSL
- Metadatos: orientación EXIF y preservación de ICC
- Motor Rust con paralelismo y SIMD
- Compilación nativa automática con Native Assets

> HEIC no está soportado actualmente.

## Cómo se usa cada paquete

- `just_image`: para proyectos Dart, servidores, herramientas y cualquier runtime Dart sin Flutter
- `just_image_cli`: para uso desde terminal y scripts de automatización
- `just_image_flutter`: para apps Flutter que quieran reutilizar la misma API de `just_image`

## Licencia

MIT
