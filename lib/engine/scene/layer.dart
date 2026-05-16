import 'dart:ui';

import '../../engine/renderer/font_organizer.dart';
import '../../engine/widgets/spotify_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

export '../../engine/renderer/font_organizer.dart' show LedFontId;

enum LayerType { text, clock, gif, spotify, finance, pomodoro, slotMachine}
enum AnimationEffect { none, blink, scrollLeft, scrollRight, pulse, fade, burst }
enum TextAlignment { left, center, right }
enum ClockFormat { h24, h12 }
enum MediaLayout { letterbox, fill, stretch }
enum SpotifyLayout { artAndText, textOnly, artOnly }
enum FinanceLayout { priceAndGraph, priceOnly, graphOnly }
enum PomodoroState { focus, shortBreak, longBreak }
enum PomodoroLayout { splitLayout, minimalist}

// ─────────────────────────────────────────────────────────────────────────────
// Base Layer
// ─────────────────────────────────────────────────────────────────────────────

abstract class Layer {
  final String id;
  final String name;
  final bool visible;
  final int zIndex;
  final double opacity;
  final Offset offset;
  LayerType get type;
  const Layer({required this.id, required this.name, this.visible = true,
      this.zIndex = 0, this.opacity = 1.0, this.offset = Offset.zero});
  Layer copyWith({String? id, String? name, bool? visible, int? zIndex,
      double? opacity, Offset? offset});
  Map<String, dynamic> toJson();
}

// ─────────────────────────────────────────────────────────────────────────────
// Text Layer
// ─────────────────────────────────────────────────────────────────────────────

class TextLayer extends Layer {
  final String text;
  final Color color;
  final LedFontId fontId;
  final double fontSize;
  final TextAlignment alignment;
  final AnimationEffect effect;
  final int effectSpeedMs;

  const TextLayer({
    required super.id, required super.name, required this.text,
    this.color = const Color(0xFF21C32C), this.fontId = LedFontId.polymorph,
    this.fontSize = 8, this.alignment = TextAlignment.center,
    this.effect = AnimationEffect.none, this.effectSpeedMs = 100,
    super.visible, super.zIndex, super.opacity, super.offset,
  });

  @override LayerType get type => LayerType.text;

  @override
  TextLayer copyWith({String? id, String? name, String? text, Color? color,
      LedFontId? fontId, double? fontSize, TextAlignment? alignment,
      AnimationEffect? effect, int? effectSpeedMs, bool? visible, int? zIndex,
      double? opacity, Offset? offset}) =>
      TextLayer(
        id: id ?? this.id, name: name ?? this.name, text: text ?? this.text,
        color: color ?? this.color, fontId: fontId ?? this.fontId,
        fontSize: fontSize ?? this.fontSize, alignment: alignment ?? this.alignment,
        effect: effect ?? this.effect, effectSpeedMs: effectSpeedMs ?? this.effectSpeedMs,
        visible: visible ?? this.visible, zIndex: zIndex ?? this.zIndex,
        opacity: opacity ?? this.opacity, offset: offset ?? this.offset,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'text', 'id': id, 'name': name, 'text': text,
        'color': color.value, 'fontId': fontId.name, 'fontSize': fontSize,
        'alignment': alignment.name, 'effect': effect.name,
        'effectSpeedMs': effectSpeedMs, 'visible': visible, 'zIndex': zIndex,
        'opacity': opacity, 'offsetX': offset.dx, 'offsetY': offset.dy,
      };

  factory TextLayer.fromJson(Map<String, dynamic> j) => TextLayer(
        id: j['id'] as String, name: j['name'] as String,
        text: j['text'] as String, color: Color(j['color'] as int),
        fontId: LedFontId.values.byName(_migrateFontId(
            j['fontId'] as String? ?? j['fontStyle'] as String? ?? 'polymorph')),
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 8,
        alignment: TextAlignment.values.byName(j['alignment'] as String? ?? 'center'),
        effect: AnimationEffect.values.byName(j['effect'] as String? ?? 'none'),
        effectSpeedMs: j['effectSpeedMs'] as int? ?? 100,
        visible: j['visible'] as bool? ?? true, zIndex: j['zIndex'] as int? ?? 0,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
        offset: Offset((j['offsetX'] as num?)?.toDouble() ?? 0,
            (j['offsetY'] as num?)?.toDouble() ?? 0),
      );
}

String _migrateFontId(String raw) {
  switch (raw) {
    case 'matrixType': return 'polymorph';
    case 'led': return 'brickwork';
    default:
      return LedFontId.values.any((e) => e.name == raw) ? raw : 'polymorph';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Clock Layer
// ─────────────────────────────────────────────────────────────────────────────
 
class ClockLayer extends Layer {
  final Color color;
  final Color hoursColor;
  final Color minutesColor;
  final Color secondsColor;
  final Color dateColor;
  final Color colonColor;
  final Color ampmColor;
  final ClockFormat format;
  final bool showDate;
  final bool showSeconds;
  final bool blinkColon;
  final String timezone;
  final LedFontId fontId;
 
  const ClockLayer({
    required super.id, required super.name,
    this.color = const Color(0xFF21C32C),
    this.hoursColor = const Color(0xFF21C32C),
    this.minutesColor = const Color(0xFF21C32C),
    this.secondsColor = const Color(0xFF21C32C),
    this.dateColor = const Color(0xFF21C32C),
    this.colonColor = const Color(0xFF21C32C),
    this.ampmColor = const Color(0xFF21C32C),
    this.format = ClockFormat.h24,
    this.showDate = false, this.showSeconds = false, this.blinkColon = true,
    this.timezone = 'local', this.fontId = LedFontId.polymorph,
    super.visible, super.zIndex, super.opacity, super.offset,
  });
 
  @override LayerType get type => LayerType.clock;
 
  @override
  ClockLayer copyWith({String? id, String? name, Color? color,
      Color? hoursColor, Color? minutesColor, Color? secondsColor,
      Color? dateColor, Color? colonColor, Color? ampmColor,
      ClockFormat? format,
      bool? showDate, bool? showSeconds,
      bool? blinkColon, String? timezone, LedFontId? fontId,
      bool? visible, int? zIndex, double? opacity, Offset? offset}) =>
      ClockLayer(
        id: id ?? this.id, name: name ?? this.name,
        color: color ?? this.color, hoursColor: hoursColor ?? this.hoursColor,
        minutesColor: minutesColor ?? this.minutesColor,
        secondsColor: secondsColor ?? this.secondsColor,
        dateColor: dateColor ?? this.dateColor, colonColor: colonColor ?? this.colonColor,
        ampmColor: ampmColor ?? this.ampmColor,
        format: format ?? this.format,
        showDate: showDate ?? this.showDate, showSeconds: showSeconds ?? this.showSeconds,
        blinkColon: blinkColon ?? this.blinkColon, timezone: timezone ?? this.timezone,
        fontId: fontId ?? this.fontId, visible: visible ?? this.visible,
        zIndex: zIndex ?? this.zIndex, opacity: opacity ?? this.opacity,
        offset: offset ?? this.offset,
      );
 
  @override
  Map<String, dynamic> toJson() => {
        'type': 'clock', 'id': id, 'name': name, 'color': color.value,
        'hoursColor': hoursColor.value, 'minutesColor': minutesColor.value,
        'secondsColor': secondsColor.value, 'dateColor': dateColor.value,
        'colonColor': colonColor.value, 'ampmColor': ampmColor.value,
        'format': format.name,
        'showDate': showDate, 'showSeconds': showSeconds,
        'blinkColon': blinkColon, 'timezone': timezone, 'fontId': fontId.name,
        'visible': visible, 'zIndex': zIndex, 'opacity': opacity,
        'offsetX': offset.dx, 'offsetY': offset.dy,
      };
 
  factory ClockLayer.fromJson(Map<String, dynamic> j) => ClockLayer(
        id: j['id'] as String, name: j['name'] as String,
        color: Color(j['color'] as int? ?? 0xFF21C32C),
        hoursColor: Color(j['hoursColor'] as int? ?? j['color'] as int? ?? 0xFF21C32C),
        minutesColor: Color(j['minutesColor'] as int? ?? j['color'] as int? ?? 0xFF21C32C),
        secondsColor: Color(j['secondsColor'] as int? ?? j['color'] as int? ?? 0xFF21C32C),
        dateColor: Color(j['dateColor'] as int? ?? j['color'] as int? ?? 0xFF21C32C),
        colonColor: Color(j['colonColor'] as int? ?? j['color'] as int? ?? 0xFF21C32C),
        // Migrate old saves: fall back to minutesColor, then color
        ampmColor: Color(j['ampmColor'] as int? ?? j['minutesColor'] as int? ?? j['color'] as int? ?? 0xFF21C32C),
        format: ClockFormat.values.byName(j['format'] as String? ?? 'h24'),
        // 'alignment' key is silently ignored for forward-compat with old saves
        showDate: j['showDate'] as bool? ?? false,
        showSeconds: j['showSeconds'] as bool? ?? false,
        blinkColon: j['blinkColon'] as bool? ?? true,
        timezone: j['timezone'] as String? ?? 'local',
        fontId: LedFontId.values.byName(_migrateFontId(j['fontId'] as String? ?? 'polymorph')),
        visible: j['visible'] as bool? ?? true, zIndex: j['zIndex'] as int? ?? 0,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
        offset: Offset((j['offsetX'] as num?)?.toDouble() ?? 0,
            (j['offsetY'] as num?)?.toDouble() ?? 0),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// GIF / Image Layer
// ─────────────────────────────────────────────────────────────────────────────

class GifLayer extends Layer {
  final String? filePath;
  final MediaLayout layout;
  final bool dithering;
  final bool grayscale;
  final bool invertColor;
  final double? fpsOverride;

  const GifLayer({
    required super.id, required super.name, this.filePath,
    this.layout = MediaLayout.letterbox, this.dithering = true,
    this.grayscale = false, this.invertColor = false, this.fpsOverride,
    super.visible, super.zIndex, super.opacity, super.offset,
  });

  @override LayerType get type => LayerType.gif;

  @override
  GifLayer copyWith({String? id, String? name, String? filePath,
      bool clearFilePath = false, MediaLayout? layout, bool? dithering,
      bool? grayscale, bool? invertColor, double? fpsOverride,
      bool? visible, int? zIndex, double? opacity, Offset? offset}) =>
      GifLayer(
        id: id ?? this.id, name: name ?? this.name,
        filePath: clearFilePath ? null : (filePath ?? this.filePath),
        layout: layout ?? this.layout, dithering: dithering ?? this.dithering,
        grayscale: grayscale ?? this.grayscale, invertColor: invertColor ?? this.invertColor,
        fpsOverride: fpsOverride ?? this.fpsOverride,
        visible: visible ?? this.visible, zIndex: zIndex ?? this.zIndex,
        opacity: opacity ?? this.opacity, offset: offset ?? this.offset,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'gif', 'id': id, 'name': name, 'filePath': filePath,
        'layout': layout.name, 'dithering': dithering, 'grayscale': grayscale,
        'invertColor': invertColor, 'fpsOverride': fpsOverride,
        'visible': visible, 'zIndex': zIndex, 'opacity': opacity,
        'offsetX': offset.dx, 'offsetY': offset.dy,
      };

  factory GifLayer.fromJson(Map<String, dynamic> j) => GifLayer(
        id: j['id'] as String, name: j['name'] as String,
        filePath: j['filePath'] as String?,
        layout: MediaLayout.values.byName(j['layout'] as String? ?? 'letterbox'),
        dithering: j['dithering'] as bool? ?? true,
        grayscale: j['grayscale'] as bool? ?? false,
        invertColor: j['invertColor'] as bool? ?? false,
        fpsOverride: (j['fpsOverride'] as num?)?.toDouble(),
        visible: j['visible'] as bool? ?? true, zIndex: j['zIndex'] as int? ?? 0,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
        offset: Offset((j['offsetX'] as num?)?.toDouble() ?? 0,
            (j['offsetY'] as num?)?.toDouble() ?? 0),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Spotify Layer  ← NOW WITH SEPARATE SCROLL + OVERLAY FIELDS
// ─────────────────────────────────────────────────────────────────────────────

class SpotifyLayer extends Layer {
  final SpotifyLayout layout;
  final bool showTitle;
  final bool showArtist;
  final bool showProgress;
  final Color textColor;
  final Color titleColor;
  final Color artistColor;
  final Color progressColor;
  final double fps;
  final ArtLayoutMode? artLayoutMode;
  final LedFontId fontId;

  // ── Per-element scroll direction (base transport) ──────────────────────────
  final AnimationEffect titleEffect;         // none | scrollLeft | scrollRight
  final int titleEffectSpeedMs;
  final AnimationEffect artistEffect;        // none | scrollLeft | scrollRight
  final int artistEffectSpeedMs;

  // ── Per-element overlay effect (alpha modulation on top of scroll) ─────────
  final AnimationEffect titleOverlayEffect;  // none | blink | pulse | fade | burst
  final AnimationEffect artistOverlayEffect; // none | blink | pulse | fade | burst

  const SpotifyLayer({
    required super.id, required super.name,
    this.layout = SpotifyLayout.artAndText,
    this.showTitle = true, this.showArtist = true, this.showProgress = true,
    this.textColor = const Color(0xFFFFFFFF),
    this.titleColor = const Color(0xFFFFFFFF),
    this.artistColor = const Color(0xFFFFFFFF),
    this.progressColor = const Color(0xFF21C32C),
    this.fps = 10,
    super.visible, super.zIndex, super.opacity, super.offset,
    this.artLayoutMode, this.fontId = LedFontId.polymorph,
    this.titleEffect = AnimationEffect.scrollLeft,
    this.titleEffectSpeedMs = 100,
    this.artistEffect = AnimationEffect.scrollLeft,
    this.artistEffectSpeedMs = 100,
    this.titleOverlayEffect = AnimationEffect.none,
    this.artistOverlayEffect = AnimationEffect.none,
  });

  @override LayerType get type => LayerType.spotify;

  @override
  SpotifyLayer copyWith({
    String? id, String? name, SpotifyLayout? layout,
    bool? showTitle, bool? showArtist, bool? showProgress,
    Color? textColor, Color? titleColor, Color? artistColor, Color? progressColor,
    double? fps, bool? visible, int? zIndex, double? opacity, Offset? offset,
    ArtLayoutMode? artLayoutMode, LedFontId? fontId,
    AnimationEffect? titleEffect, int? titleEffectSpeedMs,
    AnimationEffect? artistEffect, int? artistEffectSpeedMs,
    AnimationEffect? titleOverlayEffect,
    AnimationEffect? artistOverlayEffect,
  }) =>
      SpotifyLayer(
        id: id ?? this.id, name: name ?? this.name,
        layout: layout ?? this.layout,
        showTitle: showTitle ?? this.showTitle,
        showArtist: showArtist ?? this.showArtist,
        showProgress: showProgress ?? this.showProgress,
        textColor: textColor ?? this.textColor,
        titleColor: titleColor ?? this.titleColor,
        artistColor: artistColor ?? this.artistColor,
        progressColor: progressColor ?? this.progressColor,
        fps: fps ?? this.fps,
        visible: visible ?? this.visible, zIndex: zIndex ?? this.zIndex,
        opacity: opacity ?? this.opacity, offset: offset ?? this.offset,
        artLayoutMode: artLayoutMode ?? this.artLayoutMode,
        fontId: fontId ?? this.fontId,
        titleEffect: titleEffect ?? this.titleEffect,
        titleEffectSpeedMs: titleEffectSpeedMs ?? this.titleEffectSpeedMs,
        artistEffect: artistEffect ?? this.artistEffect,
        artistEffectSpeedMs: artistEffectSpeedMs ?? this.artistEffectSpeedMs,
        titleOverlayEffect: titleOverlayEffect ?? this.titleOverlayEffect,
        artistOverlayEffect: artistOverlayEffect ?? this.artistOverlayEffect,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'spotify', 'id': id, 'name': name, 'layout': layout.name,
        'showTitle': showTitle, 'showArtist': showArtist, 'showProgress': showProgress,
        'textColor': textColor.value, 'titleColor': titleColor.value,
        'artistColor': artistColor.value, 'progressColor': progressColor.value,
        'fps': fps, 'visible': visible, 'zIndex': zIndex, 'opacity': opacity,
        'offsetX': offset.dx, 'offsetY': offset.dy, 'fontId': fontId.name,
        'titleEffect': titleEffect.name,
        'titleEffectSpeedMs': titleEffectSpeedMs,
        'artistEffect': artistEffect.name,
        'artistEffectSpeedMs': artistEffectSpeedMs,
        'titleOverlayEffect': titleOverlayEffect.name,
        'artistOverlayEffect': artistOverlayEffect.name,
      };

  factory SpotifyLayer.fromJson(Map<String, dynamic> j) {
    final legacy = _migrateSpotifyEffect(j['textEffect'] as String?);
    final legacySpeed = j['textEffectSpeedMs'] as int? ?? 100;

    return SpotifyLayer(
      id: j['id'] as String, name: j['name'] as String,
      layout: SpotifyLayout.values.byName(j['layout'] as String? ?? 'artAndText'),
      showTitle: j['showTitle'] as bool? ?? true,
      showArtist: j['showArtist'] as bool? ?? true,
      showProgress: j['showProgress'] as bool? ?? true,
      textColor: Color(j['textColor'] as int? ?? 0xFFFFFFFF),
      titleColor: Color(j['titleColor'] as int? ?? 0xFFFFFFFF),
      artistColor: Color(j['artistColor'] as int? ?? 0xFFFFFFFF),
      progressColor: Color(j['progressColor'] as int? ?? 0xFF21C32C),
      fps: (j['fps'] as num?)?.toDouble() ?? 10,
      visible: j['visible'] as bool? ?? true, zIndex: j['zIndex'] as int? ?? 0,
      opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
      offset: Offset((j['offsetX'] as num?)?.toDouble() ?? 0,
          (j['offsetY'] as num?)?.toDouble() ?? 0),
      fontId: LedFontId.values.byName(_migrateFontId(j['fontId'] as String? ?? 'polymorph')),
      titleEffect: j.containsKey('titleEffect')
          ? AnimationEffect.values.byName(j['titleEffect'] as String)
          : legacy,
      titleEffectSpeedMs: j['titleEffectSpeedMs'] as int? ?? legacySpeed,
      artistEffect: j.containsKey('artistEffect')
          ? AnimationEffect.values.byName(j['artistEffect'] as String)
          : legacy,
      artistEffectSpeedMs: j['artistEffectSpeedMs'] as int? ?? legacySpeed,
      titleOverlayEffect: AnimationEffect.values.byName(
          j['titleOverlayEffect'] as String? ?? 'none'),
      artistOverlayEffect: AnimationEffect.values.byName(
          j['artistOverlayEffect'] as String? ?? 'none'),
    );
  }
}

AnimationEffect _migrateSpotifyEffect(String? raw) {
  switch (raw) {
    case 'scroll':  return AnimationEffect.scrollLeft;
    case 'blink':   return AnimationEffect.blink;
    case 'pulse':   return AnimationEffect.pulse;
    case 'fade':    return AnimationEffect.fade;
    case 'static_': return AnimationEffect.none;
    default:
      try { return AnimationEffect.values.byName(raw ?? 'scrollLeft'); }
      catch (_) { return AnimationEffect.scrollLeft; }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pomodoro Layer
// ─────────────────────────────────────────────────────────────────────────────

class PomodoroLayer extends Layer {
  final int focusDurationMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;
  final int sessionsBeforeLongBreak;
  final PomodoroLayout layout;
  final bool showSeconds;
  final bool showSession;
  final bool blinkColor;
  final Color focusColor;
  final Color breakColor;
  final Color longBreakColor;
  final double fps;
  final PomodoroState currentState;

  const PomodoroLayer({
    required super.id, required super.name,
    this.focusDurationMinutes = 25, this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15, this.sessionsBeforeLongBreak = 4,
    this.layout = PomodoroLayout.splitLayout,
    this.showSeconds = true, this.showSession = false, this.blinkColor = true,
    this.focusColor = const Color(0xFFFFCC00),
    this.breakColor = const Color(0xFF21C32C),
    this.longBreakColor = const Color.fromARGB(255, 40, 86, 185),
    this.fps = 10, this.currentState = PomodoroState.focus,
    super.visible, super.zIndex, super.opacity, super.offset,
  });

  @override LayerType get type => LayerType.pomodoro;

  Color get activeColor => switch (currentState) {
        PomodoroState.focus => focusColor,
        PomodoroState.shortBreak => breakColor,
        PomodoroState.longBreak => longBreakColor,
      };

  @override
  PomodoroLayer copyWith({String? id, String? name,
      int? focusDurationMinutes, int? shortBreakMinutes, int? longBreakMinutes,
      int? sessionsBeforeLongBreak, PomodoroLayout? layout,
      bool? showSeconds, bool? showSession, bool? blinkColor,
      Color? focusColor, Color? breakColor, Color? longBreakColor,
      double? fps, PomodoroState? currentState,
      bool? visible, int? zIndex, double? opacity, Offset? offset}) =>
      PomodoroLayer(
        id: id ?? this.id, name: name ?? this.name,
        focusDurationMinutes: focusDurationMinutes ?? this.focusDurationMinutes,
        shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
        longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
        sessionsBeforeLongBreak: sessionsBeforeLongBreak ?? this.sessionsBeforeLongBreak,
        layout: layout ?? this.layout, showSeconds: showSeconds ?? this.showSeconds,
        showSession: showSession ?? this.showSession, blinkColor: blinkColor ?? this.blinkColor,
        focusColor: focusColor ?? this.focusColor, breakColor: breakColor ?? this.breakColor,
        longBreakColor: longBreakColor ?? this.longBreakColor,
        fps: fps ?? this.fps, currentState: currentState ?? this.currentState,
        visible: visible ?? this.visible, zIndex: zIndex ?? this.zIndex,
        opacity: opacity ?? this.opacity, offset: offset ?? this.offset,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'pomodoro', 'id': id, 'name': name,
        'focusDurationMinutes': focusDurationMinutes,
        'shortBreakMinutes': shortBreakMinutes, 'longBreakMinutes': longBreakMinutes,
        'sessionsBeforeLongBreak': sessionsBeforeLongBreak, 'layout': layout.name,
        'showSeconds': showSeconds, 'showSession': showSession, 'blinkColor': blinkColor,
        'focusColor': focusColor.value, 'breakColor': breakColor.value,
        'longBreakColor': longBreakColor.value, 'fps': fps,
        'currentState': currentState.name, 'visible': visible, 'zIndex': zIndex,
        'opacity': opacity, 'offsetX': offset.dx, 'offsetY': offset.dy,
      };

  factory PomodoroLayer.fromJson(Map<String, dynamic> j) => PomodoroLayer(
        id: j['id'] as String, name: j['name'] as String,
        focusDurationMinutes: j['focusDurationMinutes'] as int? ?? 25,
        shortBreakMinutes: j['shortBreakMinutes'] as int? ?? 5,
        longBreakMinutes: j['longBreakMinutes'] as int? ?? 15,
        sessionsBeforeLongBreak: j['sessionsBeforeLongBreak'] as int? ?? 4,
        layout: PomodoroLayout.values.byName(j['layout'] as String? ?? 'splitLayout'),
        showSeconds: j['showSeconds'] as bool? ?? true,
        showSession: j['showSession'] as bool? ?? false,
        blinkColor: j['blinkColor'] as bool? ?? true,
        focusColor: Color(j['focusColor'] as int? ?? 0xFFFFCC00),
        breakColor: Color(j['breakColor'] as int? ?? 0xFF21C32C),
        longBreakColor: Color(j['longBreakColor'] as int? ?? 0xFF2856B9),
        fps: (j['fps'] as num?)?.toDouble() ?? 10,
        currentState: PomodoroState.values.byName(j['currentState'] as String? ?? 'focus'),
        visible: j['visible'] as bool? ?? true, zIndex: j['zIndex'] as int? ?? 0,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
        offset: Offset((j['offsetX'] as num?)?.toDouble() ?? 0,
            (j['offsetY'] as num?)?.toDouble() ?? 0),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Slot Machine Layer
// ─────────────────────────────────────────────────────────────────────────────

class SlotMachineLayer extends Layer {
  final Color frameColor;
  final Color winFlashColor;
  final bool  showFrame;
  final int   spinSpeedMs;         // ms per symbol-height of scroll
  final int   spinDurationMs;      // how long reel 0 keeps spinning
  final int   reelStopStaggerMs;   // extra ms per reel before it locks in
  final int   winFlashDurationMs;  // post-spin flash window (0 = no flash)
  final int   winOddsDenominator;  // ~1 in N spins is a forced 3-of-a-kind
  final bool  showDecorations;
  final Color marqueeColor;

  const SlotMachineLayer({
    required super.id, required super.name,
    this.frameColor         = const Color(0xFFEFEFEF),
    this.winFlashColor      = const Color(0xFFFFC107),
    this.showFrame          = true,
    this.spinSpeedMs        = 80,
    this.spinDurationMs     = 1200,
    this.reelStopStaggerMs  = 400,
    this.winFlashDurationMs = 2500,
    this.winOddsDenominator = 8,
    this.showDecorations    = true,
    this.marqueeColor       = const Color(0xFFFFB300),
    super.visible, super.zIndex, super.opacity, super.offset,
  });

  @override LayerType get type => LayerType.slotMachine;

  @override
  SlotMachineLayer copyWith({
    String? id, String? name,
    Color? frameColor, Color? winFlashColor, bool? showFrame,
    int? spinSpeedMs, int? spinDurationMs, int? reelStopStaggerMs,
    int? winFlashDurationMs, int? winOddsDenominator,
    bool? visible, int? zIndex, double? opacity, Offset? offset,
    bool? showDecorations, Color? marqueeColor,
  }) => SlotMachineLayer(
        id: id ?? this.id, name: name ?? this.name,
        frameColor:         frameColor         ?? this.frameColor,
        winFlashColor:      winFlashColor      ?? this.winFlashColor,
        showFrame:          showFrame          ?? this.showFrame,
        spinSpeedMs:        spinSpeedMs        ?? this.spinSpeedMs,
        spinDurationMs:     spinDurationMs     ?? this.spinDurationMs,
        reelStopStaggerMs:  reelStopStaggerMs  ?? this.reelStopStaggerMs,
        winFlashDurationMs: winFlashDurationMs ?? this.winFlashDurationMs,
        winOddsDenominator: winOddsDenominator ?? this.winOddsDenominator,
        visible: visible ?? this.visible, zIndex: zIndex ?? this.zIndex,
        opacity: opacity ?? this.opacity, offset: offset ?? this.offset,
        showDecorations:    showDecorations    ?? this.showDecorations,
        marqueeColor:       marqueeColor       ?? this.marqueeColor,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'slotMachine', 'id': id, 'name': name,
        'frameColor':         frameColor.value,
        'winFlashColor':      winFlashColor.value,
        'showFrame':          showFrame,
        'spinSpeedMs':        spinSpeedMs,
        'spinDurationMs':     spinDurationMs,
        'reelStopStaggerMs':  reelStopStaggerMs,
        'winFlashDurationMs': winFlashDurationMs,
        'winOddsDenominator': winOddsDenominator,
        'visible': visible, 'zIndex': zIndex, 'opacity': opacity,
        'offsetX': offset.dx, 'offsetY': offset.dy,
        'showDecorations':    showDecorations,
        'marqueeColor':       marqueeColor.value,
      };

  factory SlotMachineLayer.fromJson(Map<String, dynamic> j) => SlotMachineLayer(
        id: j['id'] as String, name: j['name'] as String,
        frameColor:    Color(j['frameColor']    as int? ?? 0xFFEFEFEF),
        winFlashColor: Color(j['winFlashColor'] as int? ?? 0xFFFFC107),
        showFrame:     j['showFrame']     as bool? ?? true,
        spinSpeedMs:        j['spinSpeedMs']        as int? ?? 80,
        spinDurationMs:     j['spinDurationMs']     as int? ?? 1200,
        reelStopStaggerMs:  j['reelStopStaggerMs']  as int? ?? 400,
        winFlashDurationMs: j['winFlashDurationMs'] as int? ?? 2500,
        winOddsDenominator: j['winOddsDenominator'] as int? ?? 8,
        visible: j['visible'] as bool? ?? true, zIndex: j['zIndex'] as int? ?? 0,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
        offset: Offset((j['offsetX'] as num?)?.toDouble() ?? 0,(j['offsetY'] as num?)?.toDouble() ?? 0),
        showDecorations:    j['showDecorations']    as bool? ?? true,
        marqueeColor:       Color(j['marqueeColor'] as int? ?? 0xFFFFB300),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Finance Layer
// ─────────────────────────────────────────────────────────────────────────────

class FinanceLayer extends Layer {
  final String         symbol;             // CoinGecko id e.g. "bitcoin"
  final String         vsCurrency;         // "usd", "eur", ...
  final FinanceLayout  layout;
  final Color          symbolColor;
  final Color          priceColor;
  final Color          upColor;
  final Color          downColor;
  final Color          graphColor;
  final LedFontId      fontId;
  final bool           showSymbol;
  final bool           showChangePercent;
  final int            decimals;
  final int            pollIntervalSec;
 
  const FinanceLayer({
    required super.id,
    required super.name,
    this.symbol            = 'bitcoin',
    this.vsCurrency        = 'usd',
    this.layout            = FinanceLayout.priceAndGraph,
    this.symbolColor       = const Color(0xFFFFFFFF),
    this.priceColor        = const Color(0xFFFFFFFF),
    this.upColor           = const Color(0xFF21C32C),
    this.downColor         = const Color(0xFFE05656),
    this.graphColor        = const Color(0xFF21C32C),
    this.fontId            = LedFontId.polymorph,
    this.showSymbol        = true,
    this.showChangePercent = true,
    this.decimals          = 2,
    this.pollIntervalSec   = 60,
    super.visible,
    super.zIndex,
    super.opacity,
    super.offset,
  });
 
  @override
  LayerType get type => LayerType.finance;
 
  @override
  FinanceLayer copyWith({
    String? id, String? name,
    String? symbol, String? vsCurrency,
    FinanceLayout? layout,
    Color? symbolColor, Color? priceColor, Color? upColor, Color? downColor,
    Color? graphColor,
    LedFontId? fontId,
    bool? showSymbol, bool? showChangePercent,
    int? decimals, int? pollIntervalSec,
    bool? visible, int? zIndex, double? opacity, Offset? offset,
  }) =>
      FinanceLayer(
        id: id ?? this.id,
        name: name ?? this.name,
        symbol: symbol ?? this.symbol,
        vsCurrency: vsCurrency ?? this.vsCurrency,
        layout: layout ?? this.layout,
        symbolColor: symbolColor ?? this.symbolColor,
        priceColor: priceColor ?? this.priceColor,
        upColor: upColor ?? this.upColor,
        downColor: downColor ?? this.downColor,
        graphColor: graphColor ?? this.graphColor,
        fontId: fontId ?? this.fontId,
        showSymbol: showSymbol ?? this.showSymbol,
        showChangePercent: showChangePercent ?? this.showChangePercent,
        decimals: decimals ?? this.decimals,
        pollIntervalSec: pollIntervalSec ?? this.pollIntervalSec,
        visible: visible ?? this.visible,
        zIndex: zIndex ?? this.zIndex,
        opacity: opacity ?? this.opacity,
        offset: offset ?? this.offset,
      );
 
  @override
  Map<String, dynamic> toJson() => {
        'type': 'finance', 'id': id, 'name': name,
        'symbol': symbol, 'vsCurrency': vsCurrency,
        'layout': layout.name,
        'symbolColor': symbolColor.value,
        'priceColor':  priceColor.value,
        'upColor':     upColor.value,
        'downColor':   downColor.value,
        'graphColor':  graphColor.value,
        'fontId': fontId.name,
        'showSymbol': showSymbol,
        'showChangePercent': showChangePercent,
        'decimals': decimals,
        'pollIntervalSec': pollIntervalSec,
        'visible': visible, 'zIndex': zIndex, 'opacity': opacity,
        'offsetX': offset.dx, 'offsetY': offset.dy,
      };
 
  factory FinanceLayer.fromJson(Map<String, dynamic> j) => FinanceLayer(
        id: j['id'] as String,
        name: j['name'] as String,
        symbol: j['symbol'] as String? ?? 'bitcoin',
        vsCurrency: j['vsCurrency'] as String? ?? 'usd',
        layout: FinanceLayout.values.byName(
            j['layout'] as String? ?? 'priceAndGraph'),
        symbolColor: Color(j['symbolColor'] as int? ?? 0xFFFFFFFF),
        priceColor:  Color(j['priceColor']  as int? ?? 0xFFFFFFFF),
        upColor:     Color(j['upColor']     as int? ?? 0xFF21C32C),
        downColor:   Color(j['downColor']   as int? ?? 0xFFE05656),
        graphColor:  Color(j['graphColor']  as int? ?? 0xFF21C32C),
        fontId: LedFontId.values.byName(
            j['fontId'] as String? ?? 'polymorph'),
        showSymbol: j['showSymbol'] as bool? ?? true,
        showChangePercent: j['showChangePercent'] as bool? ?? true,
        decimals: j['decimals'] as int? ?? 2,
        pollIntervalSec: j['pollIntervalSec'] as int? ?? 60,
        visible: j['visible'] as bool? ?? true,
        zIndex: j['zIndex'] as int? ?? 0,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
        offset: Offset(
            (j['offsetX'] as num?)?.toDouble() ?? 0,
            (j['offsetY'] as num?)?.toDouble() ?? 0),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Factory: deserialise any Layer from JSON
// ─────────────────────────────────────────────────────────────────────────────

Layer layerFromJson(Map<String, dynamic> j) {
  switch (j['type'] as String) {
    case 'text':        return TextLayer.fromJson(j);
    case 'clock':       return ClockLayer.fromJson(j);
    case 'gif':         return GifLayer.fromJson(j);
    case 'spotify':     return SpotifyLayer.fromJson(j);
    case 'finance':  return FinanceLayer.fromJson(j);
    case 'pomodoro':    return PomodoroLayer.fromJson(j);
    case 'slotMachine': return SlotMachineLayer.fromJson(j);   
    default: throw ArgumentError('Unknown layer type: ${j['type']}');
  }
}