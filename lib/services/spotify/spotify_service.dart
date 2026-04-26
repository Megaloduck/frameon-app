import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/widgets/spotify_widget.dart';
import '../../features/device/device_controller.dart';
import '../../shared/providers/providers.dart';
import 'spotify_auth.dart';
import 'spotify_api_client.dart';

export 'spotify_auth.dart';
export 'spotify_api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

enum SpotifyConnectionStatus { disconnected, connecting, connected, error }

class SpotifyState {
  final SpotifyConnectionStatus status;
  final String?     currentTrackTitle;
  final String?     currentArtist;
  final String?     currentAlbum;
  final String?     albumArtUrl;
  final Uint32List? albumArtPixels;
  final int         albumArtSize;
  final double      progress;
  final bool        isPlaying;
  final String?     errorMessage;
  final String?     trackId;
  final Duration    currentPosition;
  final Duration    currentDuration;
  final bool        isShuffling;

  const SpotifyState({
    this.status            = SpotifyConnectionStatus.disconnected,
    this.currentTrackTitle,
    this.currentArtist,
    this.currentAlbum,
    this.albumArtUrl,
    this.albumArtPixels,
    this.albumArtSize      = 32,
    this.progress          = 0,
    this.isPlaying         = false,
    this.errorMessage,
    this.trackId,
    this.currentPosition   = Duration.zero,
    this.currentDuration   = Duration.zero,
    this.isShuffling       = false,
  });

  bool get isConnected  => status == SpotifyConnectionStatus.connected;
  bool get isConnecting => status == SpotifyConnectionStatus.connecting;

  /// Convert to [SpotifyTrack] for the **live preview**.
  ///
  /// Does NOT set [durationMs] (leaves it 0) so [progressAt()] falls back
  /// to the static [progress] field. The preview uses the ever-growing
  /// ticker elapsedMs — passing durationMs here would make the bar race to 100%.
  SpotifyTrack toPreviewTrack() => SpotifyTrack(
        title:     currentTrackTitle ?? '',
        artist:    currentArtist ?? '',
        artPixels: albumArtPixels,
        artWidth:  albumArtPixels != null ? albumArtSize : 0,
        artHeight: albumArtPixels != null ? albumArtSize : 0,
        // durationMs omitted (defaults to 0) → progressAt() uses progress fallback
        progress:  progress,
        isPlaying: isPlaying,
      );

  /// Convert to [SpotifyTrack] for the **device export**.
  ///
  /// Passes [startPositionMs] and [durationMs] so the renderer computes
  /// per-frame progress linearly on the device.
  SpotifyTrack toTrack() => SpotifyTrack(
        title:           currentTrackTitle ?? '',
        artist:          currentArtist ?? '',
        artPixels:       albumArtPixels,
        artWidth:        albumArtPixels != null ? albumArtSize : 0,
        artHeight:       albumArtPixels != null ? albumArtSize : 0,
        startPositionMs: currentPosition.inMilliseconds,
        durationMs:      currentDuration.inMilliseconds,
        progress:        progress,
        isPlaying:       isPlaying,
      );

  SpotifyState copyWith({
    SpotifyConnectionStatus? status,
    String?     currentTrackTitle,
    String?     currentArtist,
    String?     currentAlbum,
    String?     albumArtUrl,
    Uint32List? albumArtPixels,
    int?        albumArtSize,
    double?     progress,
    bool?       isPlaying,
    String?     errorMessage,
    String?     trackId,
    Duration?   currentPosition,
    Duration?   currentDuration,
    bool?       isShuffling,
    bool        clearError = false,
    bool        clearArt   = false,
  }) =>
      SpotifyState(
        status:            status            ?? this.status,
        currentTrackTitle: currentTrackTitle ?? this.currentTrackTitle,
        currentArtist:     currentArtist     ?? this.currentArtist,
        currentAlbum:      currentAlbum      ?? this.currentAlbum,
        albumArtUrl:       albumArtUrl       ?? this.albumArtUrl,
        albumArtPixels:    clearArt  ? null  : (albumArtPixels ?? this.albumArtPixels),
        albumArtSize:      albumArtSize      ?? this.albumArtSize,
        progress:          progress          ?? this.progress,
        isPlaying:         isPlaying         ?? this.isPlaying,
        errorMessage:      clearError ? null : (errorMessage   ?? this.errorMessage),
        trackId:           trackId           ?? this.trackId,
        currentPosition:   currentPosition   ?? this.currentPosition,
        currentDuration:   currentDuration   ?? this.currentDuration,
        isShuffling:       isShuffling       ?? this.isShuffling,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class SpotifyServiceNotifier extends Notifier<SpotifyState> {
  final _auth   = SpotifyAuth();
  final _client = SpotifyApiClient();
  Timer? _pollTimer;
  Timer? _progressTimer;

  static const _pollInterval = Duration(seconds: 5);

  @override
  SpotifyState build() => const SpotifyState();

  // ── Connection ────────────────────────────────────────────────────────────

  Future<void> connect() async {
    state = state.copyWith(
      status: SpotifyConnectionStatus.connecting,
      clearError: true,
    );
    try {
      final ok = await _auth.authorize();
      if (!ok) {
        state = state.copyWith(
          status: SpotifyConnectionStatus.error,
          errorMessage: 'Authorization was cancelled or failed. Please try again.',
        );
        return;
      }
      state = state.copyWith(status: SpotifyConnectionStatus.connected);
      await refresh();
      _startPolling();
    } catch (e) {
      state = state.copyWith(
        status: SpotifyConnectionStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  void disconnect() {
    _stopPolling();
    _auth.clear();
    state = const SpotifyState();
  }

  // ── Polling ───────────────────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => refresh());

    // Interpolate progress every second so the matrix preview bar moves smoothly.
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!state.isPlaying) return;
      if (state.currentDuration.inMilliseconds == 0) return;
      final newPos = state.currentPosition + const Duration(seconds: 1);
      if (newPos > state.currentDuration) return;
      final newProgress =
          newPos.inMilliseconds / state.currentDuration.inMilliseconds;
      state = state.copyWith(
        currentPosition: newPos,
        progress: newProgress.clamp(0.0, 1.0),
      );
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  // ── Now playing ───────────────────────────────────────────────────────────

  Future<void> refresh() async {
    final token = await _auth.validAccessToken;
    if (token == null) return;

    final np = await _client.getNowPlaying(token);
    if (np == null) {
      state = state.copyWith(
        status:    SpotifyConnectionStatus.connected,
        isPlaying: false,
      );
      return;
    }

    final trackChanged = np.trackId != state.trackId;
    state = state.copyWith(
      status:            SpotifyConnectionStatus.connected,
      currentTrackTitle: np.title,
      currentArtist:     np.artist,
      currentAlbum:      np.album,
      albumArtUrl:       np.albumArtUrl,
      progress:          np.progress,
      isPlaying:         np.isPlaying,
      trackId:           np.trackId,
      currentPosition:   np.currentPosition,
      currentDuration:   np.currentDuration,
      clearArt:          trackChanged,
    );

    final shuffleState = await _client.getShuffleState(token);
    if (shuffleState != null) {
      state = state.copyWith(isShuffling: shuffleState);
    }

    if (trackChanged) {
      // Await art fetch so pixels are in state before we trigger the export.
      if (np.albumArtUrl != null) {
        await _fetchAlbumArt(np.albumArtUrl!);
      }
      _autoSyncToDevice();
    }
  }

  // ── Auto-sync ─────────────────────────────────────────────────────────────

  /// Invalidates the timeline and triggers a device send when track changes.
  ///
  /// ## Why we do NOT touch matrixRendererProvider here
  ///
  /// matrixRendererProvider listens to spotifyServiceProvider during its own
  /// build (via ref.listen). If we called ref.read(matrixRendererProvider)
  /// here, Riverpod would detect:
  ///
  ///   matrixRendererProvider → spotifyServiceProvider → matrixRendererProvider
  ///
  /// ...and throw a CircularDependencyError.
  ///
  /// Instead, renderer.currentTrack is updated through two existing paths
  /// that are already wired without causing a cycle:
  ///
  ///   1. matrixRendererProvider's ref.listen(spotifyServiceProvider) updates
  ///      it whenever state changes — this fires immediately after we set
  ///      state above, before invalidate() triggers a rebuild.
  ///
  ///   2. TimelineNotifier.build() calls ref.read(spotifyServiceProvider) and
  ///      sets renderer.currentTrack itself before calling renderer.render().
  ///
  /// Both paths guarantee the renderer has fresh track data before any frame
  /// is encoded — without introducing a dependency cycle.
  void _autoSyncToDevice() {
    // Invalidating triggers TimelineNotifier.build(), which reads the latest
    // spotifyServiceProvider state and sets renderer.currentTrack directly
    // before calling renderer.render().
    ref.invalidate(timelineProvider);

    final device = ref.read(deviceConnectionProvider);
    if (device.isConnected && !device.isSending) {
      ref.read(deviceConnectionProvider.notifier).sendToDevice();
    }
  }

  // ── Album art ─────────────────────────────────────────────────────────────

  Future<void> _fetchAlbumArt(String url) async {
    final result = await _client.fetchAlbumArt(url);
    if (result == null) return;
    state = state.copyWith(
      albumArtPixels: result.pixels,
      albumArtSize:   result.width,
    );
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await _doAction((t) => _client.pause(t));
    } else {
      await _doAction((t) => _client.play(t));
    }
  }

  Future<void> skipNext() => _doAction(
        (t) => _client.skipNext(t),
        delay: const Duration(milliseconds: 600),
      );

  Future<void> skipPrevious() => _doAction(
        (t) => _client.skipPrevious(t),
        delay: const Duration(milliseconds: 600),
      );

  Future<void> toggleShuffle() async {
    final token = await _auth.validAccessToken;
    if (token == null) return;
    await _client.toggleShuffle(token, !state.isShuffling);
    await refresh();
  }

  Future<void> _doAction(
    Future<bool> Function(String token) action, {
    Duration delay = const Duration(milliseconds: 300),
  }) async {
    final token = await _auth.validAccessToken;
    if (token == null) return;
    await action(token);
    await Future<void>.delayed(delay);
    await refresh();
  }

  @override
  void dispose() => _stopPolling();
}

final spotifyServiceProvider =
    NotifierProvider<SpotifyServiceNotifier, SpotifyState>(
  SpotifyServiceNotifier.new,
);