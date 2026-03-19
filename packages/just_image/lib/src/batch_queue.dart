import 'dart:async';
import 'dart:collection';

import 'exceptions.dart';
import 'image_format.dart';
import 'image_pipeline.dart';
import 'image_result.dart';

/// Tarea de procesamiento en la cola con prioridad.
class _BatchTask implements Comparable<_BatchTask> {
  final int id;
  final TaskPriority priority;
  final ImagePipeline pipeline;
  final Completer<ImageResult> completer;

  _BatchTask({
    required this.id,
    required this.priority,
    required this.pipeline,
    required this.completer,
  });

  @override
  int compareTo(_BatchTask other) {
    // Mayor prioridad primero
    final cmp = other.priority.value.compareTo(priority.value);
    if (cmp != 0) return cmp;
    // FIFO para misma prioridad
    return id.compareTo(other.id);
  }
}

/// Cola de procesamiento por lotes con prioridades.
///
/// Permite encolar múltiples imágenes y procesarlas en paralelo,
/// aprovechando el pool de hilos de Rust (rayon) en background isolates.
///
/// ```dart
/// final queue = BatchQueue(concurrency: 4);
/// final futures = images.map((bytes) =>
///   queue.enqueue(
///     ImagePipeline(bytes).resize(800, 600).toFormat(ImageFormat.webp),
///   ),
/// );
/// final results = await Future.wait(futures);
/// queue.dispose();
/// ```
class BatchQueue {
  /// Número máximo de tareas ejecutándose en paralelo.
  final int concurrency;

  final SplayTreeSet<_BatchTask> _queue = SplayTreeSet<_BatchTask>();
  int _runningCount = 0;
  int _nextId = 0;
  bool _disposed = false;

  BatchQueue({this.concurrency = 4});

  /// Encola un pipeline para procesamiento.
  /// Devuelve un Future que se completa cuando la tarea finaliza.
  Future<ImageResult> enqueue(
    ImagePipeline pipeline, {
    TaskPriority priority = TaskPriority.normal,
  }) {
    if (_disposed) {
      throw const BatchQueueDisposedException();
    }

    final completer = Completer<ImageResult>();
    final task = _BatchTask(
      id: _nextId++,
      priority: priority,
      pipeline: pipeline,
      completer: completer,
    );

    _queue.add(task);
    _processNext();

    return completer.future;
  }

  /// Procesa la siguiente tarea en la cola si hay capacidad.
  void _processNext() {
    while (_runningCount < concurrency && _queue.isNotEmpty) {
      final task = _queue.first;
      _queue.remove(task);
      _runningCount++;

      task.pipeline
          .execute()
          .then((result) {
            task.completer.complete(result);
          })
          .catchError((Object error) {
            task.completer.completeError(error);
          })
          .whenComplete(() {
            _runningCount--;
            if (!_disposed) {
              _processNext();
            }
          });
    }
  }

  /// Número de tareas pendientes en cola.
  int get pendingCount => _queue.length;

  /// Número de tareas ejecutándose actualmente.
  int get runningCount => _runningCount;

  /// Indica si la cola ha sido desechada.
  bool get isDisposed => _disposed;

  /// Libera la cola. Las tareas en ejecución continuarán pero no se
  /// iniciarán nuevas. Las tareas pendientes se cancelan con error.
  void dispose() {
    _disposed = true;
    for (final task in _queue) {
      task.completer.completeError(const TaskCancelledException());
    }
    _queue.clear();
  }
}
