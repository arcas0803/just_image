import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

/// An image source that can be read lazily when the pipeline runs.
///
/// Implemented by [BytesSource], [FileSource] and [XFileSource].
sealed class ImageSource {
  const ImageSource();

  /// Reads the raw image bytes asynchronously.
  Future<Uint8List> readBytes();
}

/// Image source backed by an in-memory byte buffer.
final class BytesSource extends ImageSource {
  final Uint8List bytes;

  const BytesSource(this.bytes);

  @override
  Future<Uint8List> readBytes() async => bytes;
}

/// Image source backed by a dart:io [File].
final class FileSource extends ImageSource {
  final File file;

  const FileSource(this.file);

  @override
  Future<Uint8List> readBytes() => file.readAsBytes();
}

/// Image source backed by a cross_file [XFile].
final class XFileSource extends ImageSource {
  final XFile xfile;

  const XFileSource(this.xfile);

  @override
  Future<Uint8List> readBytes() => xfile.readAsBytes();
}
