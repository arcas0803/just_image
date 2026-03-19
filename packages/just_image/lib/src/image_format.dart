/// Formatos de imagen soportados por el motor.
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

/// Tipo de flip.
enum FlipDirection { horizontal, vertical }

/// Prioridad para el batch queue.
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
