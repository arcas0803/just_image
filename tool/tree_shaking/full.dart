// Copyright (c) 2026 just_image contributors.
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:just_image/just_image.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    throw ArgumentError('Expected input and output paths.');
  }
  final result = await ImagePipeline.file(File(arguments[0]))
      .resize(320, 180)
      .filter(ArtisticFilterName.cinematic)
      .encode(OutputFormat.webp)
      .run();
  await File(arguments[1]).writeAsBytes(result.data);
}
