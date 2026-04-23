import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../engine/scene/layer.dart';
import '../../../../engine/widgets/spotify_widget.dart';
import '../../../../shared/providers/providers.dart';
import '../properties_customizer.dart';
import 'toolbox_shared.dart';
import '../ui_primitives.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Left panel — Spotify connection controls
// ─────────────────────────────────────────────────────────────────────────────

class SpotifyToolboxLeft extends ConsumerWidget {
  final SpotifyLayer layer;
  const SpotifyToolboxLeft({super.key, required this.layer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spot = ref.watch(spotifyServiceProvider);
    final service = ref.read(spotifyServiceProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kSurfaceLow,
            borderRadius: const BorderRadius.all(kRadiusMd),
            border: Border.all(color: kBorder),
          ),
          child: spot.isConnected
              ? _NowPlayingCard(spot: spot, onRefresh: service.refresh)
              : spot.isConnecting
                  ? const _ConnectingCard()
                  : _DisconnectedCard(
                      errorMessage: spot.errorMessage,
                      onConnect: service.connect,
                    ),
        ),
        const SizedBox(height: 12),
        if (spot.isConnected) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TbTransportBtn(
                icon: Icons.shuffle_rounded,
                onTap: () => service.toggleShuffle(),
                active: spot.isShuffling,
              ),
              Expanded(
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TbTransportBtn(
                        icon: Icons.skip_previous_rounded,
                        onTap: () => service.skipPrevious(),
                      ),
                      const SizedBox(width: 12),
                      TbTransportBtn(
                        icon: spot.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        filled: true,
                        onTap: () => service.togglePlayPause(),
                      ),
                      const SizedBox(width: 12),
                      TbTransportBtn(
                        icon: Icons.skip_next_rounded,
                        onTap: () => service.skipNext(),
                      ),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: service.disconnect,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        const Color(0xFF1DB954).withOpacity(0.15),
                    borderRadius:
                        const BorderRadius.all(kRadiusSm),
                    border: Border.all(
                        color: const Color(0xFF1DB954)
                            .withOpacity(0.5)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.link_off_rounded,
                          size: 12, color: Color(0xFF1DB954)),
                      SizedBox(width: 4),
                      Text('Disconnect',
                          style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF1DB954))),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.all(kRadiusSm),
                child: LinearProgressIndicator(
                  value: spot.progress,
                  minHeight: 4,
                  backgroundColor: kBorder,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF1DB954)),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(spot.currentPosition),
                      style: const TextStyle(
                          fontSize: 10, color: kTextDim)),
                  Text(_formatDuration(spot.currentDuration),
                      style: const TextStyle(
                          fontSize: 10, color: kTextDim)),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Right panel — layout + visibility rows
// ─────────────────────────────────────────────────────────────────────────────

class SpotifyToolboxRight extends StatelessWidget {
  final SpotifyLayer layer;
  final SceneNotifier n;
  const SpotifyToolboxRight(
      {super.key, required this.layer, required this.n});

  bool get _hasText =>
      layer.layout == SpotifyLayout.artAndText ||
      layer.layout == SpotifyLayout.textOnly;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Layout dropdown ──────────────────────────────────────────
          tbGreenDropdown<SpotifyLayout>(
            SpotifyLayout.values,
            layer.layout,
            (v) => n.updateLayer(layer.copyWith(layout: v)),
          ),
          const SizedBox(height: 8),

          // ── Art layout mode (artOnly only) ───────────────────────────
          if (layer.layout == SpotifyLayout.artOnly) ...[
            tbGreenDropdown<ArtLayoutMode>(
              ArtLayoutMode.values,
              layer.artLayoutMode ?? ArtLayoutMode.stretch,
              (v) => n.updateLayer(layer.copyWith(artLayoutMode: v)),
            ),
            const SizedBox(height: 8),
          ],

          const SizedBox(height: 4),

          // ── Show title ───────────────────────────────────────────────
          if (_hasText)
            _PropertiesToggleRow(
              label: 'Show title',
              color: layer.titleColor,
              value: layer.showTitle,
              initialFontId: layer.fontId,
              initialEffect: layer.titleEffect,              // scroll direction
              initialOverlayEffect: layer.titleOverlayEffect, // overlay
              initialEffectSpeedMs: layer.titleEffectSpeedMs,
              showFont: true,
              showFontEffect: true,
              showLightingEffect: true,
              onPropertiesChanged: (r) => n.updateLayer(layer.copyWith(
                titleColor: r.color,
                fontId: r.fontId,
                titleEffect: r.scrollDirection,           // save scroll
                titleOverlayEffect: r.overlayEffect,      // save overlay
                titleEffectSpeedMs: r.effectSpeedMs,
              )),
              onToggled: (v) => n.updateLayer(layer.copyWith(showTitle: v)),
            ),

          // ── Show artist ──────────────────────────────────────────────
          if (_hasText)
            _PropertiesToggleRow(
                label: 'Show artist',
                color: layer.artistColor,
                value: layer.showArtist,
                initialFontId: layer.fontId,
                initialEffect: layer.artistEffect,               // scroll direction
                initialOverlayEffect: layer.artistOverlayEffect, // overlay
                initialEffectSpeedMs: layer.artistEffectSpeedMs,
                showFont: true,
                showFontEffect: true,
                showLightingEffect: true,
                onPropertiesChanged: (r) => n.updateLayer(layer.copyWith(
                  artistColor: r.color,
                  fontId: r.fontId,
                  artistEffect: r.scrollDirection,          // save scroll
                  artistOverlayEffect: r.overlayEffect,     // save overlay
                  artistEffectSpeedMs: r.effectSpeedMs,
                )),
              onToggled: (v) => n.updateLayer(layer.copyWith(showArtist: v)),
            ),

          // ── Show progress ────────────────────────────────────────────
          _PropertiesToggleRow(
            label: 'Show progress',
            color: layer.progressColor,
            value: layer.showProgress,
            initialFontId: layer.fontId,
            initialEffect: AnimationEffect.none,
            showFont: false,
            showFontEffect: false,
            showLightingEffect: false,
            onPropertiesChanged: (r) =>
                n.updateLayer(layer.copyWith(progressColor: r.color)),
            onToggled: (v) =>
                n.updateLayer(layer.copyWith(showProgress: v)),
          ),
        ],
      );


}

// ─────────────────────────────────────────────────────────────────────────────
// _PropertiesToggleRow
// ─────────────────────────────────────────────────────────────────────────────

class _PropertiesToggleRow extends StatelessWidget {
  final String label;
  final Color color;
  final bool value;
  final LedFontId initialFontId;
  final AnimationEffect initialEffect;
  final AnimationEffect? initialOverlayEffect;  // ← separate overlay init
  final int initialEffectSpeedMs;        
  final bool showFont;
  final bool showFontEffect;
  final bool showLightingEffect;
  final ValueChanged<PropertiesResult> onPropertiesChanged;
  final ValueChanged<bool> onToggled;

  const _PropertiesToggleRow({
    required this.label,
    required this.color,
    required this.value,
    required this.initialFontId,
    required this.initialEffect,
    this.initialOverlayEffect,
    this.initialEffectSpeedMs = 100,     
    this.showFont = true,
    this.showFontEffect = true,
    this.showLightingEffect = false,
    required this.onPropertiesChanged,
    required this.onToggled,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 34,
        child: Row(
          children: [
            GestureDetector(
              onTap: () async {
                final result = await showPropertiesCustomizer(
                  context,
                  initialColor: color,
                  initialFontId: initialFontId,
                  initialEffect: initialEffect,
                  initialOverlayEffect: initialOverlayEffect,  // ← pass through
                  initialEffectSpeedMs: initialEffectSpeedMs,
                  showFont: showFont,
                  showFontEffect: showFontEffect,
                  showLightingEffect: showLightingEffect,
                );
                if (result != null) onPropertiesChanged(result);
              },
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.all(kRadiusSm),
                  border: Border.all(color: Colors.black.withOpacity(0.18)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(label,
                style: const TextStyle(fontSize: 12, color: kTextMuted))),
            Transform.scale(
              scale: 0.5,
              child: Switch(value: value, onChanged: onToggled,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Private card widgets
// ─────────────────────────────────────────────────────────────────────────────

class _AlbumArtThumbnail extends StatelessWidget {
  final Uint32List pixels;
  final int size;
  const _AlbumArtThumbnail({required this.pixels, required this.size});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 60,
        height: 60,
        child:
            CustomPaint(painter: _ArtPainter(pixels: pixels, size: size)),
      );
}

class _ArtPainter extends CustomPainter {
  final Uint32List pixels;
  final int size;
  const _ArtPainter({required this.pixels, required this.size});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    if (pixels.isEmpty || size == 0) return;
    final paint = Paint()..isAntiAlias = false;
    final dW = canvasSize.width / size;
    final dH = canvasSize.height / size;
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final int idx = y * size + x;
        if (idx >= pixels.length) break;
        paint.color = Color(pixels[idx] | 0xFF000000);
        canvas.drawRect(
            Rect.fromLTWH(x * dW, y * dH, dW + 0.5, dH + 0.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ArtPainter old) =>
      old.pixels != pixels || old.size != size;
}

class _NowPlayingCard extends StatelessWidget {
  final SpotifyState spot;
  final VoidCallback onRefresh;
  const _NowPlayingCard(
      {required this.spot, required this.onRefresh});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(kRadiusSm),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.all(kRadiusSm),
              child: spot.albumArtPixels != null
                  ? _AlbumArtThumbnail(
                      pixels: spot.albumArtPixels!,
                      size: spot.albumArtSize)
                  : Container(
                      width: 60,
                      height: 60,
                      color: const Color(0xFF282828),
                      child: const Icon(Icons.music_note_rounded,
                          size: 22, color: Color(0xFF1DB954)),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  spot.currentTrackTitle ?? '—',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.2),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(spot.currentArtist ?? '',
                    style: const TextStyle(
                        fontSize: 11, color: kTextMuted),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
                if (spot.currentAlbum != null) ...[
                  const SizedBox(height: 1),
                  Text(spot.currentAlbum!,
                      style: const TextStyle(
                          fontSize: 9, color: kTextDim),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                ],
              ],
            ),
          ),
          Tooltip(
            message: 'Refresh now playing',
            child: InkWell(
              onTap: onRefresh,
              borderRadius: const BorderRadius.all(kRadiusSm),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.refresh_rounded,
                    size: 15, color: kTextMuted),
              ),
            ),
          ),
        ],
      );
}

class _ConnectingCard extends StatelessWidget {
  const _ConnectingCard();

  @override
  Widget build(BuildContext context) => const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFF1DB954)),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text('Opening Spotify in your browser…',
                style:
                    TextStyle(fontSize: 11, color: kTextMuted)),
          ),
        ],
      );
}

class _DisconnectedCard extends StatelessWidget {
  final String? errorMessage;
  final Future<void> Function() onConnect;
  const _DisconnectedCard(
      {this.errorMessage, required this.onConnect});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.queue_music_rounded,
              size: 28, color: Color(0xFF1DB954)),
          const SizedBox(height: 6),
          const Text('Connect to Spotify',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          if (errorMessage != null)
            Text(errorMessage!,
                style:
                    TextStyle(fontSize: 10, color: Colors.red.shade400),
                textAlign: TextAlign.center)
          else
            const Text(
                'Sign in to display the current track',
                style:
                    TextStyle(fontSize: 10, color: kTextMuted),
                textAlign: TextAlign.center),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.link_rounded, size: 14),
              label: const Text('Connect with Spotify',
                  style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1DB954),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 8),
                shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.all(kRadiusSm)),
              ),
            ),
          ),
        ],
      );
}