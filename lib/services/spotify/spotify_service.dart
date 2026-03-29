import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/widgets/spotify_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Spotify state model
// ─────────────────────────────────────────────────────────────────────────────

class SpotifyState {
  final bool isConnected;
  final String? currentTrackTitle;
  final String? currentArtist;
  final double progress;
  final bool isPlaying;
  final String? errorMessage;

  const SpotifyState({
    this.isConnected  = false,
    this.currentTrackTitle,
    this.currentArtist,
    this.progress     = 0,
    this.isPlaying    = false,
    this.errorMessage,
  });

  /// Build a [SpotifyTrack] suitable for the renderer.
  SpotifyTrack toTrack() => SpotifyTrack(
        title:    currentTrackTitle ?? '',
        artist:   currentArtist ?? '',
        progress: progress,
        isPlaying: isPlaying,
      );

  SpotifyState copyWith({
    bool? isConnected,
    String? currentTrackTitle,
    String? currentArtist,
    double? progress,
    bool? isPlaying,
    String? errorMessage,
  }) =>
      SpotifyState(
        isConnected: isConnected ?? this.isConnected,
        currentTrackTitle: currentTrackTitle ?? this.currentTrackTitle,
        currentArtist: currentArtist ?? this.currentArtist,
        progress: progress ?? this.progress,
        isPlaying: isPlaying ?? this.isPlaying,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Spotify service notifier
// ─────────────────────────────────────────────────────────────────────────────

/// Manages Spotify OAuth and current-track polling.
///
/// In this iteration [connect] simulates OAuth and [refresh] returns a
/// hard-coded demo track. Replace the body of both methods with a real
/// Spotify Web API call once client credentials are available.
///
/// The renderer reads [SpotifyState.toTrack()] via [matrixRendererProvider]
/// which injects the track into [MatrixRenderer.currentTrack] before each
/// render call.
class SpotifyServiceNotifier extends Notifier<SpotifyState> {
  @override
  SpotifyState build() => const SpotifyState();

  /// Initiate Spotify OAuth.
  /// TODO: replace with url_launcher + OAuth PKCE flow.
  Future<void> connect() async {
    // Simulate a short auth round-trip.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    state = state.copyWith(isConnected: true);
    await refresh();
  }

  /// Disconnect and clear track state.
  void disconnect() {
    state = const SpotifyState();
  }

  /// Fetch the currently playing track from the Spotify Web API.
  /// TODO: replace stub with real HTTP call to
  ///   GET https://api.spotify.com/v1/me/player/currently-playing
  Future<void> refresh() async {
    if (!state.isConnected) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    state = state.copyWith(
      currentTrackTitle: 'Come Together',
      currentArtist:     'The Beatles',
      progress:          0.42,
      isPlaying:         true,
    );
  }
}

final spotifyServiceProvider =
    NotifierProvider<SpotifyServiceNotifier, SpotifyState>(
  SpotifyServiceNotifier.new,
);