// Copyright (c) 2026 just_image contributors.
// SPDX-License-Identifier: MIT

import 'package:meta/meta.dart';

import '../native_bridge.dart';

/// Internal execution strategy used to preserve feature-level FFI reachability.
@internal
abstract interface class NativePipelineExecutor {
  const NativePipelineExecutor();

  PipelineResponse process(NativeBridge bridge, PipelineRequest request);
}

@internal
final class CorePipelineExecutor implements NativePipelineExecutor {
  const CorePipelineExecutor();

  @override
  PipelineResponse process(NativeBridge bridge, PipelineRequest request) =>
      bridge.processCorePipeline(request);
}

@internal
final class StandardPipelineExecutor implements NativePipelineExecutor {
  const StandardPipelineExecutor();

  @override
  PipelineResponse process(NativeBridge bridge, PipelineRequest request) =>
      bridge.processPipeline(request);
}

@internal
final class ExtendedPipelineExecutor implements NativePipelineExecutor {
  const ExtendedPipelineExecutor();

  @override
  PipelineResponse process(NativeBridge bridge, PipelineRequest request) =>
      bridge.processExtendedPipeline(request);
}

@internal
NativePipelineExecutor requireStandard(NativePipelineExecutor current) =>
    current is ExtendedPipelineExecutor
    ? current
    : const StandardPipelineExecutor();

@internal
NativePipelineExecutor requireExtended(NativePipelineExecutor current) =>
    const ExtendedPipelineExecutor();
