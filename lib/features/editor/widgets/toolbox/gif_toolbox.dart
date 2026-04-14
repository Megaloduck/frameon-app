import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../engine/scene/layer.dart';
import '../../../../shared/providers/providers.dart';
import '../gif_bytes_provider.dart';
import 'toolbox_shared.dart';
import '../ui_primitives.dart';

class GifToolboxLeft extends ConsumerStatefulWidget {
  final GifLayer layer;
  final SceneNotifier n;
  const GifToolboxLeft({super.key, required this.layer, required this.n});

  @override
  ConsumerState<GifToolboxLeft> createState() => _GifToolboxLeftState();
}

class _GifToolboxLeftState extends ConsumerState<GifToolboxLeft> {
  bool _loading = false;

  Future<void> _pick() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gif', 'png', 'jpg', 'jpeg'],
        withData: true,
      );
    } catch (e) {
      _snack('Picker error: $e');
      return;
    }

    if (result == null || !mounted) return;
    final pf = result.files.single;

    setState(() => _loading = true);
    try {
      Uint8List? bytes = pf.bytes;
      if ((bytes == null || bytes.isEmpty) && !kIsWeb && pf.path != null) {
        bytes = await compute<String, Uint8List>(
            (path) => File(path).readAsBytesSync(), pf.path!);
      }
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        _snack('Could not read file.');
        return;
      }

      final String key = pf.path ?? pf.name;
      ref.read(gifBytesProvider.notifier).set(key, bytes);
      ref.read(matrixRendererProvider).addAssetBytes(key, bytes);
      widget.n.updateLayer(widget.layer.copyWith(filePath: key));
    } catch (e) {
      if (mounted) _snack('Failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _remove() {
    final key = widget.layer.filePath;
    if (key == null) return;
    ref.read(gifBytesProvider.notifier).remove(key);
    ref.read(matrixRendererProvider).removeAsset(key);
    widget.n.updateLayer(widget.layer.copyWith(clearFilePath: true));
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.layer.filePath;
    final hasFile = key != null;
    final allBytes = ref.watch(gifBytesProvider);
    final bytes = hasFile ? allBytes[key] : null;
    final fileName =
        hasFile ? key.split('/').last.split('\\').last : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(children: [
          Expanded(
            child: Text('JPG · PNG · GIF',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.08,
                    color: kTextDim)),
          ),
        ]),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _loading ? null : _pick,
          child: Container(
            height: 115,
            decoration: BoxDecoration(
              color: hasFile ? Colors.black : kSurfaceLow,
              borderRadius: const BorderRadius.all(kRadiusMd),
              border: hasFile
                  ? null
                  : Border.all(color: kBorder, style: BorderStyle.solid),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasFile && bytes != null
                ? Stack(fit: StackFit.expand, children: [
                    Image.memory(bytes,
                        fit: BoxFit.cover, gaplessPlayback: true),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: _pick,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius:
                                const BorderRadius.all(kRadiusSm),
                          ),
                          child: const Text('CHANGE',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ),
                    ),
                  ])
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_loading)
                        const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: kGreen))
                      else
                        const Icon(Icons.upload_file_rounded,
                            size: 28, color: kTextDim),
                      const SizedBox(height: 6),
                      Text(_loading ? 'Loading…' : 'Click to upload',
                          style: const TextStyle(
                              fontSize: 11, color: kTextDim)),
                    ],
                  ),
          ),
        ),
        if (hasFile) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: Text(fileName ?? '',
                      style: const TextStyle(
                          fontSize: 11, color: kTextMuted),
                      overflow: TextOverflow.ellipsis)),
              GestureDetector(
                onTap: _remove,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.close_rounded,
                        size: 14, color: Colors.red.shade400),
                    const SizedBox(width: 2),
                    Text('Remove',
                        style: TextStyle(
                            fontSize: 11, color: Colors.red.shade400)),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class GifToolboxRight extends StatelessWidget {
  final GifLayer layer;
  final SceneNotifier n;
  const GifToolboxRight({super.key, required this.layer, required this.n});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tbGreenDropdown<MediaLayout>(MediaLayout.values, layer.layout,
              (v) => n.updateLayer(layer.copyWith(layout: v))),
          const SizedBox(height: 10),
          TbToggleRow(
              label: 'Dithering',
              value: layer.dithering,
              onChanged: (v) =>
                  n.updateLayer(layer.copyWith(dithering: v))),
          TbToggleRow(
              label: 'Grayscale',
              value: layer.grayscale,
              onChanged: (v) =>
                  n.updateLayer(layer.copyWith(grayscale: v))),
          TbToggleRow(
              label: 'Invert color',
              value: layer.invertColor,
              onChanged: (v) =>
                  n.updateLayer(layer.copyWith(invertColor: v))),
          const SizedBox(height: 8),
          const TbLabel('Custom FPS'),
          TbSpeedSlider(
              value: layer.fpsOverride ?? 100,
              onChanged: (v) =>
                  n.updateLayer(layer.copyWith(fpsOverride: v))),
        ],
      );
}