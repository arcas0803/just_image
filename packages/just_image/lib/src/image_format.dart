/// Image formats supported by the engine.
///
/// ```dart
/// pipeline.toFormat(ImageFormat.webp).quality(85);
/// ```
enum ImageFormat {
  jpeg('jpeg'),
  png('png'),
  webp('webp'),
  avif('avif'),
  tiff('tiff'),
  bmp('bmp');

  const ImageFormat(this.value);
  final String value;
}

/// Flip direction.
enum FlipDirection { horizontal, vertical }

/// Task priority for the batch queue.
///
/// Higher-priority tasks are dequeued first.
enum TaskPriority implements Comparable<TaskPriority> {
  low(0),
  normal(1),
  high(2),
  critical(3);

  const TaskPriority(this.value);
  final int value;

  @override
  int compareTo(TaskPriority other) => value.compareTo(other.value);
}
