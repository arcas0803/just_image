import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_image_flutter/just_image_flutter.dart';
import 'package:share_plus/share_plus.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Entry point
// ═══════════════════════════════════════════════════════════════════════════

void main() => runApp(const JustImageExampleApp());

class JustImageExampleApp extends StatelessWidget {
  const JustImageExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'just_image Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Home Page — TabController + 4 tabs
// ═══════════════════════════════════════════════════════════════════════════

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late final TabController _tabController;
  late final JustImageEngine _engine;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _engine = JustImageEngine();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('just_image Demo'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.image_outlined), text: 'Single'),
            Tab(icon: Icon(Icons.auto_awesome), text: 'Filters'),
            Tab(icon: Icon(Icons.blur_on), text: 'BlurHash'),
            Tab(icon: Icon(Icons.photo_library_outlined), text: 'Batch'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SingleTab(engine: _engine),
          FiltersTab(engine: _engine),
          BlurHashTab(engine: _engine),
          BatchTab(engine: _engine),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

String _fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

Future<Uint8List?> _pickImage(ImagePicker picker) async {
  final file = await picker.pickImage(source: ImageSource.gallery);
  if (file == null) return null;
  return file.readAsBytes();
}

Future<List<Uint8List>> _pickMultipleImages(ImagePicker picker) async {
  final files = await picker.pickMultiImage();
  final results = <Uint8List>[];
  for (final f in files) {
    results.add(await f.readAsBytes());
  }
  return results;
}

Future<void> _shareBytes(Uint8List data, String format) async {
  await Share.shareXFiles([
    XFile.fromData(
      data,
      mimeType: 'image/$format',
      name: 'just_image_result.$format',
    ),
  ]);
}

// ═══════════════════════════════════════════════════════════════════════════
// Shared Widgets
// ═══════════════════════════════════════════════════════════════════════════

class _ImagePreview extends StatelessWidget {
  final Uint8List bytes;
  final String? label;

  const _ImagePreview({required this.bytes, this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(label!, style: Theme.of(context).textTheme.labelMedium),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(bytes, fit: BoxFit.contain, height: 200),
        ),
      ],
    );
  }
}

class _ResultInfoCard extends StatelessWidget {
  final ImageResult result;
  final Duration elapsed;
  final VoidCallback? onShare;

  const _ResultInfoCard({
    required this.result,
    required this.elapsed,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                result.data,
                fit: BoxFit.contain,
                height: 200,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${result.width} x ${result.height}  |  ${_fmtBytes(result.sizeInBytes)}  |  ${result.format.toUpperCase()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Processed in ${elapsed.inMilliseconds} ms',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            if (onShare != null) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: onShare,
                icon: const Icon(Icons.share),
                label: const Text('Share'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: value.toStringAsFixed(2),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 50, child: Text(value.toStringAsFixed(2))),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 1 — Single Image Processing
// ═══════════════════════════════════════════════════════════════════════════

class SingleTab extends StatefulWidget {
  final JustImageEngine engine;
  const SingleTab({super.key, required this.engine});

  @override
  State<SingleTab> createState() => _SingleTabState();
}

class _SingleTabState extends State<SingleTab>
    with AutomaticKeepAliveClientMixin {
  final _picker = ImagePicker();

  Uint8List? _inputBytes;
  ImageResult? _result;
  Duration? _elapsed;
  bool _processing = false;
  String? _error;

  // Settings
  ImageFormat _format = ImageFormat.jpeg;
  double _quality = 90;
  bool _doResize = false;
  double _resizeW = 1920;
  double _resizeH = 1080;
  double _rotateDeg = 0;
  FlipDirection? _flipDir;
  double _blur = 0;
  double _sharpen = 0;
  double _brightness = 0;
  double _contrast = 0;
  bool _sobel = false;
  String? _filterName;
  bool _doThumbnail = false;
  double _thumbW = 300;
  double _thumbH = 300;
  bool _autoOrient = true;
  bool _preserveMetadata = true;
  bool _preserveIcc = true;

  @override
  bool get wantKeepAlive => true;

  Future<void> _pick() async {
    final bytes = await _pickImage(_picker);
    if (bytes != null) {
      setState(() {
        _inputBytes = bytes;
        _result = null;
        _elapsed = null;
        _error = null;
      });
    }
  }

  Future<void> _process() async {
    if (_inputBytes == null) return;
    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final sw = Stopwatch()..start();

      var pipeline = widget.engine
          .load(_inputBytes!)
          .toFormat(_format)
          .quality(_quality.round())
          .autoOrient(_autoOrient)
          .preserveMetadata(_preserveMetadata)
          .preserveIcc(_preserveIcc);

      if (_doResize) {
        pipeline = pipeline.resize(_resizeW.round(), _resizeH.round());
      }
      if (_rotateDeg != 0) {
        pipeline = pipeline.rotate(_rotateDeg);
      }
      if (_flipDir != null) {
        pipeline = pipeline.flip(_flipDir!);
      }
      if (_blur > 0) {
        pipeline = pipeline.blur(_blur);
      }
      if (_sharpen > 0) {
        pipeline = pipeline.sharpen(_sharpen);
      }
      if (_brightness != 0) {
        pipeline = pipeline.brightness(_brightness);
      }
      if (_contrast != 0) {
        pipeline = pipeline.contrast(_contrast);
      }
      if (_sobel) {
        pipeline = pipeline.sobel();
      }
      if (_filterName != null) {
        pipeline = pipeline.filter(_filterName!);
      }
      if (_doThumbnail) {
        pipeline = pipeline.thumbnail(_thumbW.round(), _thumbH.round());
      }

      final result = await pipeline.execute();
      sw.stop();

      setState(() {
        _result = result;
        _elapsed = sw.elapsed;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final filters = widget.engine.availableFilters;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Pick button
        FilledButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Pick Image'),
        ),
        const SizedBox(height: 12),

        // Input preview
        if (_inputBytes != null)
          _ImagePreview(
            bytes: _inputBytes!,
            label: 'Original  |  ${_fmtBytes(_inputBytes!.length)}',
          ),
        const SizedBox(height: 16),

        // -- Settings --
        if (_inputBytes != null) ...[
          Text(
            'Output Settings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),

          // Format
          DropdownButtonFormField<ImageFormat>(
            initialValue: _format,
            decoration: const InputDecoration(
              labelText: 'Format',
              border: OutlineInputBorder(),
            ),
            items: ImageFormat.values
                .map(
                  (f) => DropdownMenuItem(
                    value: f,
                    child: Text(f.value.toUpperCase()),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _format = v!),
          ),
          const SizedBox(height: 8),

          // Quality
          Row(
            children: [
              const Text('Quality'),
              Expanded(
                child: Slider(
                  value: _quality,
                  min: 1,
                  max: 100,
                  divisions: 99,
                  label: _quality.round().toString(),
                  onChanged: (v) => setState(() => _quality = v),
                ),
              ),
              SizedBox(width: 40, child: Text('${_quality.round()}')),
            ],
          ),

          // Resize
          SwitchListTile(
            title: const Text('Resize'),
            value: _doResize,
            onChanged: (v) => setState(() => _doResize = v),
          ),
          if (_doResize) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Width',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(
                      text: _resizeW.round().toString(),
                    ),
                    onChanged: (v) => _resizeW = double.tryParse(v) ?? _resizeW,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Height',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(
                      text: _resizeH.round().toString(),
                    ),
                    onChanged: (v) => _resizeH = double.tryParse(v) ?? _resizeH,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Rotate
          Row(
            children: [
              const Text('Rotate'),
              Expanded(
                child: Slider(
                  value: _rotateDeg,
                  min: 0,
                  max: 360,
                  divisions: 72,
                  label: '${_rotateDeg.round()} deg',
                  onChanged: (v) => setState(() => _rotateDeg = v),
                ),
              ),
              SizedBox(width: 48, child: Text('${_rotateDeg.round()} deg')),
            ],
          ),

          // Flip
          Row(
            children: [
              const Text('Flip: '),
              ChoiceChip(
                label: const Text('None'),
                selected: _flipDir == null,
                onSelected: (_) => setState(() => _flipDir = null),
              ),
              const SizedBox(width: 4),
              ChoiceChip(
                label: const Text('H'),
                selected: _flipDir == FlipDirection.horizontal,
                onSelected: (_) =>
                    setState(() => _flipDir = FlipDirection.horizontal),
              ),
              const SizedBox(width: 4),
              ChoiceChip(
                label: const Text('V'),
                selected: _flipDir == FlipDirection.vertical,
                onSelected: (_) =>
                    setState(() => _flipDir = FlipDirection.vertical),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Effects
          Text('Effects', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),

          _SliderRow(
            label: 'Blur',
            value: _blur,
            min: 0,
            max: 20,
            divisions: 40,
            onChanged: (v) => setState(() => _blur = v),
          ),
          _SliderRow(
            label: 'Sharpen',
            value: _sharpen,
            min: 0,
            max: 10,
            divisions: 20,
            onChanged: (v) => setState(() => _sharpen = v),
          ),
          _SliderRow(
            label: 'Brightness',
            value: _brightness,
            min: -1,
            max: 1,
            divisions: 40,
            onChanged: (v) => setState(() => _brightness = v),
          ),
          _SliderRow(
            label: 'Contrast',
            value: _contrast,
            min: -1,
            max: 1,
            divisions: 40,
            onChanged: (v) => setState(() => _contrast = v),
          ),

          SwitchListTile(
            title: const Text('Sobel Edge Detection'),
            value: _sobel,
            onChanged: (v) => setState(() => _sobel = v),
          ),

          // Filter
          DropdownButtonFormField<String?>(
            initialValue: _filterName,
            decoration: const InputDecoration(
              labelText: 'Artistic Filter',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('None')),
              ...filters.map((f) => DropdownMenuItem(value: f, child: Text(f))),
            ],
            onChanged: (v) => setState(() => _filterName = v),
          ),
          const SizedBox(height: 8),

          // Thumbnail
          SwitchListTile(
            title: const Text('Thumbnail'),
            value: _doThumbnail,
            onChanged: (v) => setState(() => _doThumbnail = v),
          ),
          if (_doThumbnail) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Max Width',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(
                      text: _thumbW.round().toString(),
                    ),
                    onChanged: (v) => _thumbW = double.tryParse(v) ?? _thumbW,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Max Height',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(
                      text: _thumbH.round().toString(),
                    ),
                    onChanged: (v) => _thumbH = double.tryParse(v) ?? _thumbH,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Config switches
          Text('Config', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            title: const Text('Auto Orient (EXIF)'),
            value: _autoOrient,
            onChanged: (v) => setState(() => _autoOrient = v),
          ),
          SwitchListTile(
            title: const Text('Preserve Metadata'),
            value: _preserveMetadata,
            onChanged: (v) => setState(() => _preserveMetadata = v),
          ),
          SwitchListTile(
            title: const Text('Preserve ICC Profile'),
            value: _preserveIcc,
            onChanged: (v) => setState(() => _preserveIcc = v),
          ),

          const SizedBox(height: 12),

          // Process button
          FilledButton.icon(
            onPressed: _processing ? null : _process,
            icon: _processing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_processing ? 'Processing...' : 'Process'),
          ),
        ],

        // Error
        if (_error != null) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        ],

        // Result
        if (_result != null && _elapsed != null) ...[
          const SizedBox(height: 16),
          Text('Result', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _ResultInfoCard(
            result: _result!,
            elapsed: _elapsed!,
            onShare: () => _shareBytes(_result!.data, _result!.format),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 2 — Filters Gallery
// ═══════════════════════════════════════════════════════════════════════════

class FiltersTab extends StatefulWidget {
  final JustImageEngine engine;
  const FiltersTab({super.key, required this.engine});

  @override
  State<FiltersTab> createState() => _FiltersTabState();
}

class _FiltersTabState extends State<FiltersTab>
    with AutomaticKeepAliveClientMixin {
  final _picker = ImagePicker();

  Uint8List? _inputBytes;
  bool _generating = false;
  String? _error;

  // filter name -> (result, elapsed)
  final Map<String, (ImageResult, Duration)> _previews = {};

  @override
  bool get wantKeepAlive => true;

  Future<void> _pick() async {
    final bytes = await _pickImage(_picker);
    if (bytes != null) {
      setState(() {
        _inputBytes = bytes;
        _previews.clear();
        _error = null;
      });
      await _generatePreviews();
    }
  }

  Future<void> _generatePreviews() async {
    if (_inputBytes == null) return;
    setState(() {
      _generating = true;
      _error = null;
    });

    final filters = widget.engine.availableFilters;
    try {
      final futures = filters.map((name) async {
        final sw = Stopwatch()..start();
        final result = await widget.engine
            .load(_inputBytes!)
            .thumbnail(300, 300)
            .filter(name)
            .toFormat(ImageFormat.jpeg)
            .quality(80)
            .execute();
        sw.stop();
        return (name, result, sw.elapsed);
      });

      final results = await Future.wait(futures);
      for (final (name, result, elapsed) in results) {
        _previews[name] = (result, elapsed);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      setState(() => _generating = false);
    }
  }

  Future<void> _applyFullSize(String filterName) async {
    if (_inputBytes == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final sw = Stopwatch()..start();
      final result = await widget.engine
          .load(_inputBytes!)
          .filter(filterName)
          .toFormat(ImageFormat.jpeg)
          .quality(90)
          .execute();
      sw.stop();

      if (!mounted) return;
      Navigator.of(context).pop();

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                filterName.toUpperCase(),
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              _ResultInfoCard(
                result: result,
                elapsed: sw.elapsed,
                onShare: () => _shareBytes(result.data, result.format),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: _generating ? null : _pick,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Pick Image'),
        ),
        const SizedBox(height: 12),

        if (_inputBytes != null)
          _ImagePreview(
            bytes: _inputBytes!,
            label: 'Original  |  ${_fmtBytes(_inputBytes!.length)}',
          ),

        if (_generating) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 8),
          const Center(child: Text('Generating 15 filter previews...')),
        ],

        if (_error != null) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!),
            ),
          ),
        ],

        if (_previews.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Tap a filter to apply at full size',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.8,
            ),
            itemCount: _previews.length,
            itemBuilder: (context, index) {
              final entry = _previews.entries.elementAt(index);
              final name = entry.key;
              final (result, elapsed) = entry.value;
              return GestureDetector(
                onTap: () => _applyFullSize(name),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Image.memory(result.data, fit: BoxFit.cover),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          children: [
                            Text(
                              name,
                              style: Theme.of(context).textTheme.labelSmall,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${elapsed.inMilliseconds}ms',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 3 — BlurHash
// ═══════════════════════════════════════════════════════════════════════════

class BlurHashTab extends StatefulWidget {
  final JustImageEngine engine;
  const BlurHashTab({super.key, required this.engine});

  @override
  State<BlurHashTab> createState() => _BlurHashTabState();
}

class _BlurHashTabState extends State<BlurHashTab>
    with AutomaticKeepAliveClientMixin {
  final _picker = ImagePicker();
  final _hashController = TextEditingController();

  Uint8List? _inputBytes;
  bool _encoding = false;
  bool _decoding = false;
  String? _encodedHash;
  ImageResult? _decodedResult;
  String? _error;

  double _componentsX = 4;
  double _componentsY = 3;
  double _decodeWidth = 32;
  double _decodeHeight = 32;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _hashController.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final bytes = await _pickImage(_picker);
    if (bytes != null) {
      setState(() {
        _inputBytes = bytes;
        _encodedHash = null;
        _decodedResult = null;
        _error = null;
      });
    }
  }

  Future<void> _encode() async {
    if (_inputBytes == null) return;
    setState(() {
      _encoding = true;
      _error = null;
    });

    try {
      final hash = await widget.engine.blurHashEncode(
        _inputBytes!,
        componentsX: _componentsX.round(),
        componentsY: _componentsY.round(),
      );
      setState(() {
        _encodedHash = hash;
        _hashController.text = hash;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _encoding = false);
    }
  }

  Future<void> _decode() async {
    final hash = _hashController.text.trim();
    if (hash.isEmpty) return;
    setState(() {
      _decoding = true;
      _error = null;
    });

    try {
      final result = await widget.engine.blurHashDecode(
        hash,
        width: _decodeWidth.round(),
        height: _decodeHeight.round(),
      );
      setState(() => _decodedResult = result);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _decoding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // -- ENCODE SECTION --
        Text('Encode', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),

        FilledButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Pick Image to Encode'),
        ),
        const SizedBox(height: 12),

        if (_inputBytes != null)
          _ImagePreview(
            bytes: _inputBytes!,
            label: 'Original  |  ${_fmtBytes(_inputBytes!.length)}',
          ),
        const SizedBox(height: 8),

        _SliderRow(
          label: 'Comp X',
          value: _componentsX,
          min: 1,
          max: 9,
          divisions: 8,
          onChanged: (v) => setState(() => _componentsX = v),
        ),
        _SliderRow(
          label: 'Comp Y',
          value: _componentsY,
          min: 1,
          max: 9,
          divisions: 8,
          onChanged: (v) => setState(() => _componentsY = v),
        ),

        FilledButton.tonalIcon(
          onPressed: _inputBytes == null || _encoding ? null : _encode,
          icon: _encoding
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.tag),
          label: Text(_encoding ? 'Encoding...' : 'Encode'),
        ),
        const SizedBox(height: 8),

        if (_encodedHash != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      _encodedHash!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _encodedHash!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Hash copied!')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],

        const Divider(height: 32),

        // -- DECODE SECTION --
        Text('Decode', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),

        TextField(
          controller: _hashController,
          decoration: const InputDecoration(
            labelText: 'BlurHash string',
            border: OutlineInputBorder(),
            hintText: 'Paste or encode a BlurHash...',
          ),
        ),
        const SizedBox(height: 8),

        _SliderRow(
          label: 'Width',
          value: _decodeWidth,
          min: 4,
          max: 256,
          divisions: 63,
          onChanged: (v) => setState(() => _decodeWidth = v),
        ),
        _SliderRow(
          label: 'Height',
          value: _decodeHeight,
          min: 4,
          max: 256,
          divisions: 63,
          onChanged: (v) => setState(() => _decodeHeight = v),
        ),

        FilledButton.tonalIcon(
          onPressed: _decoding ? null : _decode,
          icon: _decoding
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.image),
          label: Text(_decoding ? 'Decoding...' : 'Decode'),
        ),
        const SizedBox(height: 12),

        if (_decodedResult != null) ...[
          Text(
            'Decoded Preview',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_inputBytes != null)
                Expanded(
                  child: _ImagePreview(bytes: _inputBytes!, label: 'Original'),
                ),
              if (_inputBytes != null) const SizedBox(width: 12),
              Expanded(
                child: _ImagePreview(
                  bytes: _decodedResult!.data,
                  label:
                      'BlurHash ${_decodedResult!.width} x ${_decodedResult!.height}',
                ),
              ),
            ],
          ),
        ],

        if (_error != null) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 4 — Batch Processing
// ═══════════════════════════════════════════════════════════════════════════

class BatchTab extends StatefulWidget {
  final JustImageEngine engine;
  const BatchTab({super.key, required this.engine});

  @override
  State<BatchTab> createState() => _BatchTabState();
}

class _BatchTabState extends State<BatchTab>
    with AutomaticKeepAliveClientMixin {
  final _picker = ImagePicker();

  final List<Uint8List> _inputs = [];
  final List<(ImageResult, Duration)?> _results = [];
  bool _processing = false;
  int _completed = 0;
  String? _error;

  // Shared settings
  ImageFormat _format = ImageFormat.webp;
  double _quality = 80;
  bool _doResize = false;
  double _resizeW = 1280;
  double _resizeH = 720;
  String? _filterName;

  @override
  bool get wantKeepAlive => true;

  Future<void> _pickMultiple() async {
    final images = await _pickMultipleImages(_picker);
    if (images.isNotEmpty) {
      setState(() {
        _inputs.addAll(images);
        _results.addAll(List.filled(images.length, null));
        _error = null;
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _inputs.removeAt(index);
      _results.removeAt(index);
    });
  }

  void _clearAll() {
    setState(() {
      _inputs.clear();
      _results.clear();
      _completed = 0;
      _error = null;
    });
  }

  Future<void> _processBatch() async {
    if (_inputs.isEmpty) return;
    setState(() {
      _processing = true;
      _completed = 0;
      _results.fillRange(0, _results.length, null);
      _error = null;
    });

    final queue = widget.engine.createBatch(concurrency: 4);

    try {
      final futures = <Future<void>>[];

      for (var i = 0; i < _inputs.length; i++) {
        final index = i;
        var pipeline = widget.engine
            .load(_inputs[i])
            .toFormat(_format)
            .quality(_quality.round());

        if (_doResize) {
          pipeline = pipeline.resize(_resizeW.round(), _resizeH.round());
        }
        if (_filterName != null) {
          pipeline = pipeline.filter(_filterName!);
        }

        final sw = Stopwatch()..start();
        final future = queue.enqueue(pipeline).then((result) {
          sw.stop();
          if (mounted) {
            setState(() {
              _results[index] = (result, sw.elapsed);
              _completed++;
            });
          }
        });
        futures.add(future);
      }

      await Future.wait(futures);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      queue.dispose();
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _shareAll() async {
    final files = <XFile>[];
    for (var i = 0; i < _results.length; i++) {
      final r = _results[i];
      if (r != null) {
        final (result, _) = r;
        files.add(
          XFile.fromData(
            result.data,
            mimeType: 'image/${result.format}',
            name: 'batch_$i.${result.format}',
          ),
        );
      }
    }
    if (files.isNotEmpty) {
      await Share.shareXFiles(files);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final filters = widget.engine.availableFilters;
    final allDone = _results.isNotEmpty && _results.every((r) => r != null);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Pick & Clear
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _processing ? null : _pickMultiple,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text('Pick Images (${_inputs.length})'),
              ),
            ),
            if (_inputs.isNotEmpty) ...[
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _processing ? null : _clearAll,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        // Input thumbnails
        if (_inputs.isNotEmpty)
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _inputs.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _inputs[i],
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _processing ? null : () => _removeImage(i),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(2),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // Result badge
                    if (_results[i] != null)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(2),
                          child: const Icon(
                            Icons.check,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),

        // -- Shared Settings --
        if (_inputs.isNotEmpty) ...[
          Text(
            'Batch Settings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),

          DropdownButtonFormField<ImageFormat>(
            initialValue: _format,
            decoration: const InputDecoration(
              labelText: 'Format',
              border: OutlineInputBorder(),
            ),
            items: ImageFormat.values
                .map(
                  (f) => DropdownMenuItem(
                    value: f,
                    child: Text(f.value.toUpperCase()),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _format = v!),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              const Text('Quality'),
              Expanded(
                child: Slider(
                  value: _quality,
                  min: 1,
                  max: 100,
                  divisions: 99,
                  label: _quality.round().toString(),
                  onChanged: (v) => setState(() => _quality = v),
                ),
              ),
              SizedBox(width: 40, child: Text('${_quality.round()}')),
            ],
          ),

          SwitchListTile(
            title: const Text('Resize'),
            value: _doResize,
            onChanged: (v) => setState(() => _doResize = v),
          ),
          if (_doResize) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Width',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(
                      text: _resizeW.round().toString(),
                    ),
                    onChanged: (v) => _resizeW = double.tryParse(v) ?? _resizeW,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Height',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(
                      text: _resizeH.round().toString(),
                    ),
                    onChanged: (v) => _resizeH = double.tryParse(v) ?? _resizeH,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          DropdownButtonFormField<String?>(
            initialValue: _filterName,
            decoration: const InputDecoration(
              labelText: 'Artistic Filter',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('None')),
              ...filters.map((f) => DropdownMenuItem(value: f, child: Text(f))),
            ],
            onChanged: (v) => setState(() => _filterName = v),
          ),
          const SizedBox(height: 12),

          // Progress
          if (_processing) ...[
            LinearProgressIndicator(
              value: _inputs.isNotEmpty ? _completed / _inputs.length : 0,
            ),
            const SizedBox(height: 4),
            Text(
              '$_completed / ${_inputs.length} processed',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
          ],

          // Process button
          FilledButton.icon(
            onPressed: _processing ? null : _processBatch,
            icon: _processing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(
              _processing
                  ? 'Processing...'
                  : 'Process ${_inputs.length} Images',
            ),
          ),

          // Share all
          if (allDone) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _shareAll,
              icon: const Icon(Icons.share),
              label: const Text('Share All Results'),
            ),
          ],
        ],

        // Error
        if (_error != null) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        ],

        // Results
        if (_results.any((r) => r != null)) ...[
          const SizedBox(height: 16),
          Text('Results', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...List.generate(_results.length, (i) {
            final r = _results[i];
            if (r == null) return const SizedBox.shrink();
            final (result, elapsed) = r;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ResultInfoCard(
                result: result,
                elapsed: elapsed,
                onShare: () => _shareBytes(result.data, result.format),
              ),
            );
          }),
        ],
      ],
    );
  }
}
