import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_image/just_image.dart';

void main() => runApp(const JustImageExampleApp());

class JustImageExampleApp extends StatelessWidget {
  const JustImageExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'just_image example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const ProcessingDemo(),
    );
  }
}

class ProcessingDemo extends StatefulWidget {
  const ProcessingDemo({super.key});

  @override
  State<ProcessingDemo> createState() => _ProcessingDemoState();
}

class _ProcessingDemoState extends State<ProcessingDemo> {
  Uint8List? _output;
  String _status = 'Press the button to execute Rust through Native Assets.';
  bool _running = false;

  Future<void> _process() async {
    setState(() {
      _running = true;
      _status = 'Processing in a background isolate…';
    });
    try {
      final result = await ImagePipeline.bytes(createExampleBmp())
          .resize(640, 360)
          .filter(ArtisticFilterName.cinematic)
          .contrast(0.1)
          .encode(OutputFormat.png)
          .run();
      if (!mounted) return;
      setState(() {
        _output = result.data;
        _status =
            '${result.width}×${result.height} · ${result.sizeInBytes} bytes';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Processing failed: $error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('just_image · zero configuration')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: _output == null
                          ? const Center(child: Icon(Icons.image, size: 96))
                          : Image.memory(_output!, fit: BoxFit.contain),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(_status, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _running ? null : _process,
                    icon: _running
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high),
                    label: const Text('Process generated image'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Uint8List createExampleBmp() {
  const width = 320;
  const height = 180;
  const rowSize = width * 3;
  final bytes = Uint8List(54 + rowSize * height);
  final header = ByteData.sublistView(bytes);
  bytes[0] = 0x42;
  bytes[1] = 0x4d;
  header.setUint32(2, bytes.length, Endian.little);
  header.setUint32(10, 54, Endian.little);
  header.setUint32(14, 40, Endian.little);
  header.setInt32(18, width, Endian.little);
  header.setInt32(22, height, Endian.little);
  header.setUint16(26, 1, Endian.little);
  header.setUint16(28, 24, Endian.little);
  header.setUint32(34, rowSize * height, Endian.little);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = 54 + y * rowSize + x * 3;
      bytes[offset] = 220;
      bytes[offset + 1] = 255 * y ~/ height;
      bytes[offset + 2] = 255 * x ~/ width;
    }
  }
  return bytes;
}
