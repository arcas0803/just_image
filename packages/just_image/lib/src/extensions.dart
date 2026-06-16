import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'image_pipeline.dart';

/// Entrypoints for single-image processing.
extension JustImageFile on File {
  /// Returns an [ImagePipeline] for this file.
  ImagePipeline get justImage => ImagePipeline.file(this);
}

extension JustImageXFile on XFile {
  /// Returns an [ImagePipeline] for this cross-file.
  ImagePipeline get justImage => ImagePipeline.xfile(this);
}

extension JustImageBytes on Uint8List {
  /// Returns an [ImagePipeline] for these raw bytes.
  ImagePipeline get justImage => ImagePipeline.bytes(this);
}
