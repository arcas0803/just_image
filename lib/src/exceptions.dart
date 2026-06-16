/// Exception hierarchy for the just_image package.
///
/// Every exception extends [JustImageException], which allows catching
/// individual error types or handling them all with a single `catch`.
///
/// ```dart
/// try {
///   final result = await pipeline.execute();
/// } on ImageDecodeException catch (e) {
///   print('Unrecognised format: $e');
/// } on ImageEncodeException catch (e) {
///   print('Encoding failed: $e');
/// } on JustImageException catch (e) {
///   print('General just_image error: $e');
/// }
/// ```
library;

/// Base exception for all errors thrown by the just_image package.
///
/// Catch this type to handle **any** error coming from the image
/// processing engine in a single place.
///
/// ```dart
/// try {
///   final result = await ImagePipeline(bytes).resize(800, 600).execute();
/// } on JustImageException catch (e) {
///   print('Something went wrong: $e');
/// }
/// ```
class JustImageException implements Exception {
  /// Human-readable description of the error.
  final String message;

  const JustImageException(this.message);

  @override
  String toString() => 'JustImageException: $message';
}

// ─────────────────────────────────────────
// Input / decoding errors
// ─────────────────────────────────────────

/// The input bytes do not represent a valid image or the format is
/// not supported.
///
/// **Common cause:** the bytes are not an image (e.g. a PDF was passed),
/// or the file is corrupted / truncated.
///
/// ```dart
/// try {
///   final result = await ImagePipeline(badBytes).execute();
/// } on ImageDecodeException catch (e) {
///   print('Cannot decode: $e');
/// }
/// ```
class ImageDecodeException extends JustImageException {
  const ImageDecodeException(super.message);

  @override
  String toString() => 'ImageDecodeException: $message';
}

// ─────────────────────────────────────────
// Encoding / output errors
// ─────────────────────────────────────────

/// The engine could not encode the image into the requested output format.
///
/// **Common cause:** the output format is unsupported, or the quality
/// parameters are incompatible with the codec (e.g. quality > 100).
///
/// ```dart
/// try {
///   final result = await ImagePipeline(bytes)
///       .toFormat(ImageFormat.avif)
///       .quality(150) // out of range
///       .execute();
/// } on ImageEncodeException catch (e) {
///   print('Encode failed: $e');
/// }
/// ```
class ImageEncodeException extends JustImageException {
  const ImageEncodeException(super.message);

  @override
  String toString() => 'ImageEncodeException: $message';
}

// ─────────────────────────────────────────
// Processing / pipeline errors
// ─────────────────────────────────────────

/// An operation inside the pipeline failed during execution.
///
/// **Common cause:** invalid parameters in a pipeline step — for example,
/// `crop` with coordinates outside the image bounds, or `resize` with
/// zero dimensions.
///
/// ```dart
/// try {
///   final result = await ImagePipeline(bytes)
///       .crop(0, 0, 99999, 99999) // exceeds image dimensions
///       .execute();
/// } on PipelineExecutionException catch (e) {
///   print('Pipeline step failed: $e');
/// }
/// ```
class PipelineExecutionException extends JustImageException {
  const PipelineExecutionException(super.message);

  @override
  String toString() => 'PipelineExecutionException: $message';
}

// ─────────────────────────────────────────
// Native library errors
// ─────────────────────────────────────────

/// The native Rust library (.dylib / .so / .dll) could not be loaded.
///
/// **Common cause:** the native library has not been compiled, it cannot
/// be found at the expected path, or there is no compatible binary for
/// the current platform.
///
/// **Fix:** run `cd src/native && cargo build --release` and make sure
/// the resulting binary is accessible at runtime.
///
/// ```dart
/// try {
///   final engine = JustImageEngine();
/// } on NativeLibraryException catch (e) {
///   print('Native library missing: $e');
/// }
/// ```
class NativeLibraryException extends JustImageException {
  const NativeLibraryException(super.message);

  @override
  String toString() => 'NativeLibraryException: $message';
}

/// The current platform is not supported by the native engine.
///
/// **Common cause:** running on a platform for which no pre-compiled
/// binary exists (e.g. Fuchsia).
///
/// ```dart
/// try {
///   final engine = JustImageEngine();
/// } on UnsupportedPlatformException catch (e) {
///   print('Unsupported OS: ${e.platform}');
/// }
/// ```
class UnsupportedPlatformException extends JustImageException {
  /// The operating system that was detected.
  final String platform;

  const UnsupportedPlatformException(this.platform)
    : super('Platform "$platform" is not supported');

  @override
  String toString() =>
      'UnsupportedPlatformException: Platform "$platform" is not supported';
}

// ─────────────────────────────────────────
// Batch queue errors
// ─────────────────────────────────────────

/// An operation was attempted on a [BatchQueue] that has already been
/// disposed.
///
/// **Common cause:** calling `enqueue()` after `dispose()`.
///
/// **Fix:** create a new `BatchQueue` if you need to continue processing.
///
/// ```dart
/// final queue = BatchQueue();
/// queue.dispose();
/// // This throws BatchQueueDisposedException:
/// queue.enqueue(pipeline);
/// ```
class BatchQueueDisposedException extends JustImageException {
  const BatchQueueDisposedException()
    : super('BatchQueue has been disposed. Create a new one to continue.');

  @override
  String toString() => 'BatchQueueDisposedException: $message';
}

/// A task was cancelled because the [BatchQueue] was disposed before the
/// task could be executed.
///
/// **Common cause:** calling `dispose()` while tasks are still pending
/// in the queue.
///
/// ```dart
/// final queue = BatchQueue();
/// final future = queue.enqueue(pipeline); // still pending
/// queue.dispose(); // cancels pending tasks
/// try {
///   await future;
/// } on TaskCancelledException {
///   print('Task was cancelled');
/// }
/// ```
class TaskCancelledException extends JustImageException {
  const TaskCancelledException()
    : super('Task was cancelled because the BatchQueue was disposed.');

  @override
  String toString() => 'TaskCancelledException: $message';
}

// ─────────────────────────────────────────
// Empty input error
// ─────────────────────────────────────────

/// An empty byte buffer was provided to the pipeline.
///
/// **Common cause:** reading a 0-byte file, or passing an empty
/// `Uint8List` to [ImagePipeline].
///
/// ```dart
/// import 'dart:typed_data';
///
/// try {
///   await ImagePipeline(Uint8List(0)).execute();
/// } on EmptyInputException catch (e) {
///   print('No data: $e');
/// }
/// ```
class EmptyInputException extends JustImageException {
  const EmptyInputException()
    : super('Input image bytes are empty. Provide a non-empty Uint8List.');

  @override
  String toString() => 'EmptyInputException: $message';
}
