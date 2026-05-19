import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../engine/renderer/font_organizer.dart';
import '../../../../engine/scene/layer.dart';
import '../../../../shared/providers/providers.dart';
import 'toolbox_shared.dart';
import '../ui_primitives.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TextToolboxLeft — plain StatelessWidget (style / content properties only)
// ─────────────────────────────────────────────────────────────────────────────

class TextToolboxLeft extends StatelessWidget {
  final TextLayer layer;
  final SceneNotifier n;
  const TextToolboxLeft({super.key, required this.layer, required this.n});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            tbColorBtn(context, layer.color,
                (c) => n.updateLayer(layer.copyWith(color: c))),
            const SizedBox(width: 8),
            Text('Text Color',
                style: TextStyle(fontSize: 11, color: context.tTextMuted)),
          ]),

          // Highlight color — only shown while Speed Reading is on
          if (layer.speedReading) ...[
            const SizedBox(height: 6),
            Row(children: [
              tbColorBtn(
                context,
                layer.speedReadingColor,
                (c) => n.updateLayer(layer.copyWith(speedReadingColor: c)),
              ),
              const SizedBox(width: 8),
              Text('Highlight Color',
                  style: TextStyle(fontSize: 11, color: context.tTextMuted)),
            ]),
          ],

          const SizedBox(height: 10),
          const TbLabel('Font Style'),
          const SizedBox(height: 4),
          TbDropdown<LedFontId>(
            values: LedFontId.values,
            current: layer.fontId,
            onChange: (v) => n.updateLayer(layer.copyWith(fontId: v)),
            labelFor: (v) => LedFontLibrary.get(v).name,
          ),
          const SizedBox(height: 8),
          const TbLabel('Display Text'),
          const SizedBox(height: 4),
          TbTextField(
              value: layer.text,
              onSubmitted: (v) => n.updateLayer(layer.copyWith(text: v))),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// TextToolboxRight
//
// StatefulWidget so it can own the HardwareKeyboard handler lifecycle for
// the "Keyboard Interactive" feature.
//
// Behaviour when keyboardInteractive == true:
//   • Printable characters  → appended to layer.text (original case preserved)
//   • Backspace             → removes last character
//   • Space                 → clears layer.text entirely
//   • Returns true so the event is consumed and won't trigger app hotkeys.
// ─────────────────────────────────────────────────────────────────────────────

class TextToolboxRight extends StatefulWidget {
  final TextLayer layer;
  final SceneNotifier n;
  const TextToolboxRight({super.key, required this.layer, required this.n});

  @override
  State<TextToolboxRight> createState() => _TextToolboxRightState();
}

class _TextToolboxRightState extends State<TextToolboxRight> {
  bool _handlerAttached = false;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (widget.layer.keyboardInteractive) _attachHandler();
  }

  @override
  void didUpdateWidget(TextToolboxRight old) {
    super.didUpdateWidget(old);
    final wasActive = old.layer.keyboardInteractive;
    final isActive  = widget.layer.keyboardInteractive;
    if (!wasActive && isActive)  _attachHandler();
    if (wasActive  && !isActive) _detachHandler();
  }

  @override
  void dispose() {
    _detachHandler();
    super.dispose();
  }

  // ── Keyboard handler ─────────────────────────────────────────────────────

  void _attachHandler() {
    if (_handlerAttached) return;
    HardwareKeyboard.instance.addHandler(_onKey);
    _handlerAttached = true;
  }

  void _detachHandler() {
    if (!_handlerAttached) return;
    HardwareKeyboard.instance.removeHandler(_onKey);
    _handlerAttached = false;
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final key = event.logicalKey;

    // Space → clear
    if (key == LogicalKeyboardKey.space) {
      widget.n.updateLayer(widget.layer.copyWith(text: ''));
      return true;
    }

    // Backspace → remove last character
    if (key == LogicalKeyboardKey.backspace) {
      final current = widget.layer.text;
      if (current.isNotEmpty) {
        widget.n.updateLayer(
          widget.layer.copyWith(text: current.substring(0, current.length - 1)),
        );
      }
      return true;
    }

    // Printable character → append as-is (original case preserved)
    final char = event.character;
    if (char != null && char.isNotEmpty && !char.contains(RegExp(r'[\x00-\x1F]'))) {
      widget.n.updateLayer(
        widget.layer.copyWith(text: widget.layer.text + char),
      );
      return true;
    }

    return false;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Animation effect ───────────────────────────────────────────────
          tbGreenDropdown<AnimationEffect>(
              context,
              AnimationEffect.values,
              widget.layer.effect,
              (v) => widget.n.updateLayer(widget.layer.copyWith(effect: v))),
          const SizedBox(height: 12),
          if (widget.layer.effect != AnimationEffect.none) ...[
            const TbLabel('Speed'),
            TbSpeedSlider(
                value: widget.layer.effectSpeedMs.toDouble(),
                onChanged: (v) => widget.n
                    .updateLayer(widget.layer.copyWith(effectSpeedMs: v.round()))),
            const SizedBox(height: 12),
          ],

          // ── Opacity ────────────────────────────────────────────────────────
          const TbLabel('Opacity'),
          Slider(
              value: widget.layer.opacity,
              min: 0,
              max: 1,
              onChanged: (v) =>
                  widget.n.updateLayer(widget.layer.copyWith(opacity: v))),

          const SizedBox(height: 6),

          // ── Keyboard Interactive ───────────────────────────────────────────
          TbToggleRow(
            label: 'Keyboard Interactive',
            value: widget.layer.keyboardInteractive,
            onChanged: (v) => widget.n
                .updateLayer(widget.layer.copyWith(keyboardInteractive: v)),
          ),
          if (widget.layer.keyboardInteractive) ...[
            const SizedBox(height: 3),
            Text(
              'Type to update · Backspace to delete · Space to clear',
              style: TextStyle(
                fontSize: 9,
                color: context.tTextDim,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],

          const SizedBox(height: 6),

          // ── Speed Reading ─────────────────────────────────────────────────
          TbToggleRow(
            label: 'Speed Reading',
            value: widget.layer.speedReading,
            onChanged: (v) => widget.n
                .updateLayer(widget.layer.copyWith(speedReading: v)),
          ),

          const SizedBox(height: 6),

          // ── Double Pixel ──────────────────────────────────────────────────
          TbToggleRow(
            label: 'Double Pixel',
            value: widget.layer.doublePixel,
            onChanged: (v) => widget.n
                .updateLayer(widget.layer.copyWith(doublePixel: v)),
          ),


        ],
      );
}