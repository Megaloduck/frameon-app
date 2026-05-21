// lib/services/spotify/spotify_service.dart
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

  /// Wall-clock time when [currentPosition] was last set from the Spotify API.
  /// Used to compensate for render + transfer latency in [toTrack()].
  final DateTime? positionCapturedAt;

  SpotifyState({
    this.status             = SpotifyConnectionStatus.disconnected,
    this.currentTrackTitle,
    this.currentArtist,
    this.currentAlbum,
    this.albumArtUrl,
    this.albumArtPixels,
    this.albumArtSize       = 32,
    this.progress           = 0,
    this.isPlaying          = false,
    this.errorMessage,
    this.trackId,
    this.currentPosition    = Duration.zero,
    this.currentDuration    = Duration.zero,
    this.isShuffling        = false,
    this.positionCapturedAt,
  });

  bool get isConnected  => status == SpotifyConnectionStatus.connected;
  bool get isConnecting => status == SpotifyConnectionStatus.connecting;

  /// [currentPosition] compensated for time elapsed since the API reported it.
  ///
  /// Every millisecond between the API call and when the ESP32 shows frame 0
  /// is latency the progress bar must account for:
  ///   • Debounce delay        (~120 ms in TimelineNotifier)
  ///   • Frame render loop     (one await per frame × N frames)
  ///   • CRC computation       (background isolate)
  ///   • USB serial transfer   (~1.2 MB at 921600 baud ≈ 10–13 s)
  ///
  /// Reading DateTime.now() at export time (inside toTrack()) bakes in the
  /// real elapsed time so frame 0's progress bar is accurate.
  Duration get livePosition {
    if (!isPlaying || positionCapturedAt == null) return currentPosition;
    final elapsed = DateTime.now().difference(positionCapturedAt!);
    final live    = currentPosition + elapsed;
    return live > currentDuration ? currentDuration : live;
  }

  SpotifyTrack toPreviewTrack() => SpotifyTrack(
        title:     currentTrackTitle ?? '',
        artist:    currentArtist ?? '',
        artPixels: albumArtPixels,
        artWidth:  albumArtPixels != null ? albumArtSize : 0,
        artHeight: albumArtPixels != null ? albumArtSize : 0,
        progress:  progress,
        isPlaying: isPlaying,
      );

  /// Called inside TimelineNotifier.build() at render time.
  /// elapsedMs adds per-frame render time so frame N's progress bar matches
  /// the real playback position when the ESP32 displays it.
  SpotifyTrack toTrack() => SpotifyTrack(
        title:           currentTrackTitle ?? '',
        artist:          currentArtist ?? '',
        artPixels:       albumArtPixels,
        artWidth:        albumArtPixels != null ? albumArtSize : 0,
        artHeight:       albumArtPixels != null ? albumArtSize : 0,
        startPositionMs: livePosition.inMilliseconds,
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
    DateTime?   positionCapturedAt,
    bool        clearError = false,
    bool        clearArt   = false,
  }) =>
      SpotifyState(
        status:             status            ?? this.status,
        currentTrackTitle:  currentTrackTitle ?? this.currentTrackTitle,
        currentArtist:      currentArtist     ?? this.currentArtist,
        currentAlbum:       currentAlbum      ?? this.currentAlbum,
        albumArtUrl:        albumArtUrl       ?? this.albumArtUrl,
        albumArtPixels:     clearArt  ? null  : (albumArtPixels ?? this.albumArtPixels),
        albumArtSize:       albumArtSize      ?? this.albumArtSize,
        progress:           progress          ?? this.progress,
        isPlaying:          isPlaying         ?? this.isPlaying,
        errorMessage:       clearError ? null : (errorMessage   ?? this.errorMessage),
        trackId:            trackId           ?? this.trackId,
        currentPosition:    currentPosition   ?? this.currentPosition,
        currentDuration:    currentDuration   ?? this.currentDuration,
        isShuffling:        isShuffling       ?? this.isShuffling,
        positionCapturedAt: positionCapturedAt ?? this.positionCapturedAt,
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

  static const _pollInterval = Duration(seconds: 3);

  /// Last known volume (0–100%).  Initialised at 50% until adjusted by a
  /// BTN3/BTN5 long press.  Updated after every volumeUp / volumeDown call.
  /// NOTE: also requires adding to SpotifyApiClient — see setVolume() below.
  int _lastKnownVolume = 50;

  @override
  SpotifyState build() => SpotifyState();

  // ── Connection ────────────────────────────────────────────────────────────

  Future<void> connect() async {
    state = state.copyWith(
      status:     SpotifyConnectionStatus.connecting,
      clearError: true,
    );
    try {
      final ok = await _auth.authorize();
      if (!ok) {
        state = state.copyWith(
          status:       SpotifyConnectionStatus.error,
          errorMessage: 'Authorization was cancelled or failed. Please try again.',
        );
        return;
      }
      state = state.copyWith(status: SpotifyConnectionStatus.connected);
      await refresh();
      _startPolling();
    } catch (e) {
      state = state.copyWith(
        status:       SpotifyConnectionStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  void disconnect() {
    _stopPolling();
    _auth.clear();
    state = SpotifyState();
  }

  // ── Polling ───────────────────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => refresh());

    // Advance progress locally every second — no network call needed.
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!state.isPlaying) return;
      if (state.currentDuration.inMilliseconds == 0) return;
      final newPos = state.currentPosition + const Duration(seconds: 1);
      if (newPos > state.currentDuration) return;
      state = state.copyWith(
        currentPosition:    newPos,
        positionCapturedAt: DateTime.now(),
        progress: (newPos.inMilliseconds / state.currentDuration.inMilliseconds)
            .clamp(0.0, 1.0),
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

  /// Refresh Spotify playback state from the API.
  ///
  /// Called by the 3-second poll timer, by album-art resync, by each
  /// transport action, and by the joystick short tap (Spotify context)
  /// — "Refresh now playing" in the controller spec.
  Future<void> refresh() async {
    final token = await _auth.validAccessToken;
    if (token == null) return;

    // Snapshot the time before the API call so positionCapturedAt reflects
    // when the position was valid, not when we processed the response.
    final capturedAt = DateTime.now();

    // Fire both calls in parallel.
    final results = await Future.wait([
      _client.getNowPlaying(token),
      _client.getShuffleState(token),
    ]);

    final np           = results[0] as SpotifyNowPlaying?;
    final shuffleState = results[1] as bool?;

    if (np == null) {
      state = state.copyWith(
        status:    SpotifyConnectionStatus.connected,
        isPlaying: false,
      );
      return;
    }

    final trackChanged = np.trackId != state.trackId;

    state = state.copyWith(
      status:             SpotifyConnectionStatus.connected,
      currentTrackTitle:  np.title,
      currentArtist:      np.artist,
      currentAlbum:       np.album,
      albumArtUrl:        np.albumArtUrl,
      progress:           np.progress,
      isPlaying:          np.isPlaying,
      trackId:            np.trackId,
      currentPosition:    np.currentPosition,
      currentDuration:    np.currentDuration,
      isShuffling:        shuffleState ?? state.isShuffling,
      positionCapturedAt: capturedAt,
      clearArt:           trackChanged,
    );

    if (trackChanged) {
      // Sync immediately with text — don't wait for art.
      _autoSyncToDevice();

      // Fetch art in background; re-sync once pixels are ready.
      if (np.albumArtUrl != null) {
        _fetchAlbumArtAndResync(np.albumArtUrl!);
      }
    } else if (np.isPlaying) {
      // Re-sync every poll so the device re-anchors to real playback position.
      _autoSyncToDevice();

      // ── Next-song preload ─────────────────────────────────────────────
      // Send a next-song packet when ~12 s remain (10 s firmware swap
      // threshold + ~1.8 s transfer time).  The firmware swaps it seamlessly
      // at the 10 s mark — no gap, no manual re-send needed.
      final int remainingMs = np.currentDuration.inMilliseconds
                            - np.currentPosition.inMilliseconds;
      if (remainingMs > 0 && remainingMs <= 12000 && !_nextSongSent) {
        _nextSongSent = true;
        _sendNextSongPreload();
      }
      if (remainingMs > 15000) _nextSongSent = false;
    }
  }

  // ── Auto-sync ─────────────────────────────────────────────────────────────

  void _autoSyncToDevice() {
    ref.invalidate(timelineProvider);
    final device = ref.read(deviceConnectionProvider);
    if (device.isConnected && !device.isSending) {
      ref.read(deviceConnectionProvider.notifier).sendToDevice();
    }
  }

  // ── Album art ─────────────────────────────────────────────────────────────

  Future<void> _fetchAlbumArtAndResync(String url) async {
    final result = await _client.fetchAlbumArt(url);
    if (result == null) return;

    state = state.copyWith(
      albumArtPixels: result.pixels,
      albumArtSize:   result.width,
    );

    // The first sync (text-only) may still be sending when art arrives.
    // Poll up to 20 × 500 ms = 10 s.  If still busy, the next regular
    // poll (3 s) will pick up the art.
    for (int i = 0; i < 20; i++) {
      final device = ref.read(deviceConnectionProvider);
      if (!device.isConnected) return;
      if (!device.isSending)   break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    _autoSyncToDevice();
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  /// BTN4 short — Play / Pause (all contexts)
  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await _doAction((t) => _client.pause(t));
    } else {
      await _doAction((t) => _client.play(t));
    }
  }

  /// BTN5 short (Spotify context) — Next song
  Future<void> skipNext() => _doAction(
        (t) => _client.skipNext(t),
        delay: const Duration(milliseconds: 600),
      );

  /// BTN3 short (Spotify context) — Previous song
  Future<void> skipPrevious() => _doAction(
        (t) => _client.skipPrevious(t),
        delay: const Duration(milliseconds: 600),
      );

  /// Joystick long hold (Spotify context) — Shuffle / Unshuffle
  Future<void> toggleShuffle() async {
    final token = await _auth.validAccessToken;
    if (token == null) return;
    await _client.toggleShuffle(token, !state.isShuffling);
    await refresh();
  }

  // ── Volume (BTN3/BTN5 long in Spotify context) ────────────────────────────
  //
  // NOTE: also add to SpotifyApiClient (spotify_api_client.dart):
  //
  //   Future<bool> setVolume(String token, int percent) =>
  //       _put(token, 'volume?volume_percent=$percent');
  //

  /// BTN5 long (Spotify context) — Volume +10%
  Future<void> volumeUp() => _adjustVolume(10);

  /// BTN3 long (Spotify context) — Volume −10%
  Future<void> volumeDown() => _adjustVolume(-10);

  Future<void> _adjustVolume(int delta) async {
    final newVol = (_lastKnownVolume + delta).clamp(0, 100);
    await _doAction((t) => _client.setVolume(t, newVol));
    _lastKnownVolume = newVol;
  }

  // ── Shared action helper ──────────────────────────────────────────────────

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

  // ── Next-song preload ─────────────────────────────────────────────────────

  bool _nextSongSent = false;

  /// Build and send a next-song preload packet to the firmware.
  ///
  /// Uses a zeroed SpotifyTrack (startPositionMs=0, trackDurationMs=0) because
  /// Spotify's public API doesn't expose the upcoming queue.  The packet
  /// carries the same visual frames as the current track but with the bar
  /// reset to 0, which looks natural for a new song starting.  When Spotify
  /// actually changes tracks the next normal poll sends a fresh packet with
  /// the real track data.
  ///
  /// Fire-and-forget — failures are swallowed in sendNextSong().
  Future<void> _sendNextSongPreload() async {
    final device = ref.read(deviceConnectionProvider);
    if (!device.isConnected || device.isSending) return;

    ref.invalidate(timelineProvider);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final timeline = ref.read(timelineProvider).value;
    if (timeline == null || timeline.frameCount == 0) return;

    await ref.read(deviceConnectionProvider.notifier).sendNextSong(
      timeline,
      startPositionMs: 0,
      trackDurationMs: 0, // unknown — firmware skips bar overdraw
    );
  }

  @override
  void dispose() => _stopPolling();
}

final spotifyServiceProvider =
    NotifierProvider<SpotifyServiceNotifier, SpotifyState>(
  SpotifyServiceNotifier.new,
);