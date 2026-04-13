import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/widgets/spotify_widget.dart';
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
  final bool isShuffling;

  const SpotifyState({
    this.status            = SpotifyConnectionStatus.disconnected,
    this.currentTrackTitle,
    this.currentArtist,
    this.currentAlbum,  
    this.currentPosition = Duration.zero,   
    this.currentDuration = Duration.zero,     
    this.albumArtUrl,
    this.albumArtPixels,
    this.albumArtSize      = 32,
    this.progress          = 0,
    this.isPlaying         = false,
    this.errorMessage,
    this.trackId,
    this.isShuffling = false,
  });

  bool get isConnected  => status == SpotifyConnectionStatus.connected;
  bool get isConnecting => status == SpotifyConnectionStatus.connecting;

    SpotifyTrack toTrack() => SpotifyTrack(
        title:     currentTrackTitle ?? '',
        artist:    currentArtist ?? '',
        artPixels: albumArtPixels,
        artWidth:  albumArtPixels != null ? albumArtSize : 0,
        artHeight: albumArtPixels != null ? albumArtSize : 0,
        progress:  progress,
        isPlaying: isPlaying,
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
    bool        clearError = false,
    bool        clearArt   = false,
    bool? isShuffling,
  }) => SpotifyState(
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
        isShuffling: isShuffling ?? this.isShuffling,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class SpotifyServiceNotifier extends Notifier<SpotifyState> {
  final _auth   = SpotifyAuth();
  final _client = SpotifyApiClient();
  Timer? _pollTimer;

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
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
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
    currentAlbum:      np.album,  // Add this
    albumArtUrl:       np.albumArtUrl,
    progress:          np.progress,
    isPlaying:         np.isPlaying,
    trackId:           np.trackId,
    currentPosition:   np.currentPosition,  // Add this
    currentDuration:   np.currentDuration,   // Add this
    clearArt:          trackChanged,
  );

  if (trackChanged && np.albumArtUrl != null) {
    _fetchAlbumArt(np.albumArtUrl!);
  }
} 

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

  Future<void> skipNext() =>
      _doAction((t) => _client.skipNext(t), delay: const Duration(milliseconds: 600));

  Future<void> skipPrevious() =>
      _doAction((t) => _client.skipPrevious(t), delay: const Duration(milliseconds: 600));

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
  
  Future<void> toggleShuffle() async {
  final token = await _auth.validAccessToken;
  if (token == null) return;
  await _client.toggleShuffle(token, !state.isShuffling);
  await refresh();
}
  

  @override
  void dispose() => _stopPolling();
}


final spotifyServiceProvider =
    NotifierProvider<SpotifyServiceNotifier, SpotifyState>(
  SpotifyServiceNotifier.new,
);