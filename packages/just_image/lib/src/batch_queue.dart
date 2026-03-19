import 'dart:async';
import 'dart:collection';

import 'exceptions.dart';
import 'image_format.dart';
import 'image_pipeline.dart';
import 'image_result.dart';

/// Internal task wrapper with priority for the batch queue.
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
    // Higher priority first.
    final cmp = other.priority.value.compareTo(priority.value);
    if (cmp != 0) return cmp;
    // FIFO within the same priority level.
    return id.compareTo(other.id);
  }
}

/// Priority-based batch processing queue.
///
/// Enqueue multiple images and process them in parallel, leveraging
/// the Rust thread pool (rayon) inside background isolates.
///
/// ```dart
/// final queue = BatchQueue(concurrency: 4);
///
/// final futures = images.map((bytes) =>
///   queue.enqueue(
///     ImagePipeline(bytes).resize(800, 600).toFormat(ImageFormat.webp),
///   ),
/// );
///
/// final results = await Future.wait(futures);
/// queue.dispose();
/// ```
class BatchQueue {
  /// Maximum number of tasks running in parallel.
  final int concurrency;

  final SplayTreeSet<_BatchTask> _queue = SplayTreeSet<_BatchTask>();
  int _runningCount = 0;
  int _nextId = 0;
  bool _disposed = false;

  BatchQueue({this.concurrency = 4});

  /// Enqueues a pipeline for processing.
  ///
  /// Returns a [Future] that completes with the result once the task
  /// finishes. Tasks are scheduled according to [priority].
  ///
  /// Throws [BatchQueueDisposedException] if the queue has already
  /// been disposed.
  ///
  /// ```dart
  /// final result = await queue.enqueue(
  ///   ImagePipeline(bytes).resize(800, 600),
  ///   priority: TaskPriority.high,
  /// );
  /// ```
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

  /// Processes the next task if there is available capacity.
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

  /// Number of tasks waiting in the queue.
  int get pendingCount => _queue.length;

  /// Number of tasks currently being executed.
  int get runningCount => _runningCount;

  /// Whether this queue has been disposed.
  bool get isDisposed => _disposed;

  /// Disposes the queue.
  ///
  /// Tasks that are already running will finish, but no new tasks
  /// will be started. Pending tasks are cancelled with a
  /// [TaskCancelledException].
  void dispose() {
    _disposed = true;
    for (final task in _queue) {
      task.completer.completeError(const TaskCancelledException());
    }
    _queue.clear();
  }
}
