import 'dart:ui';

// ─────────────────────────────────────────────────────────────────────────────
// Layer Type Enum
// ─────────────────────────────────────────────────────────────────────────────

enum LayerType { text, clock, gif, spotify, pomodoro }

// ─────────────────────────────────────────────────────────────────────────────
// Animation Effects
// ─────────────────────────────────────────────────────────────────────────────

enum AnimationEffect { none, blink, scrollLeft, scrollRight }

// ─────────────────────────────────────────────────────────────────────────────
// Base Layer
// ─────────────────────────────────────────────────────────────────────────────

/// Abstract base for every compositable layer in the scene.
/// Each subclass carries its own widget-specific configuration.
abstract class Layer {
  /// Unique ID (UUID v4 string or incremental for simplicity).
  final String id;

  /// Display name shown in the layer panel.
  String name;

  /// Whether this layer is visible (eye icon in UI).
  bool visible;

  /// Z-order position (lower = further back). Managed by [Scene].
  int zIndex;

  /// Opacity 0.0–1.0.
  double opacity;

  /// Position offset within the matrix canvas (pixels).
  Offset offset;

  LayerType get type;

  Layer({
    required this.id,
    required this.name,
    this.visible = true,
    this.zIndex = 0,
    this.opacity = 1.0,
    this.offset = Offset.zero,
  });

  /// Produce a deep copy with optional field overrides.
  Layer copyWith();

  /// Serialise to JSON-safe map.
  Map<String, dynamic> toJson();
}

// ─────────────────────────────────────────────────────────────────────────────
// Text Layer
// ─────────────────────────────────────────────────────────────────────────────

enum FontStyle { matrixType, led }

enum TextAlignment { left, center, right }

class TextLayer extends Layer {
  String text;
  Color color;
  FontStyle fontStyle;
  double fontSize;
  TextAlignment alignment;
  AnimationEffect effect;
  int effectSpeedMs;

  TextLayer({
    required super.id,
    required super.name,
    required this.text,
    this.color = const Color(0xFF21C32C),
    this.fontStyle = FontStyle.matrixType,
    this.fontSize = 8,
    this.alignment = TextAlignment.center,
    this.effect = AnimationEffect.none,
    this.effectSpeedMs = 100,
    super.visible,
    super.zIndex,
    super.opacity,
    super.offset,
  });

  @override
  LayerType get type => LayerType.text;

  @override
  TextLayer copyWith({
    String? id,
    String? name,
    String? text,
    Color? color,
    FontStyle? fontStyle,
    double? fontSize,
    TextAlignment? alignment,
    AnimationEffect? effect,
    int? effectSpeedMs,
    bool? visible,
    int? zIndex,
    double? opacity,
    Offset? offset,
  }) =>
      TextLayer(
        id: id ?? this.id,
        name: name ?? this.name,
        text: text ?? this.text,
        color: color ?? this.color,
        fontStyle: fontStyle ?? this.fontStyle,
        fontSize: fontSize ?? this.fontSize,
        alignment: alignment ?? this.alignment,
        effect: effect ?? this.effect,
        effectSpeedMs: effectSpeedMs ?? this.effectSpeedMs,
        visible: visible ?? this.visible,
        zIndex: zIndex ?? this.zIndex,
        opacity: opacity ?? this.opacity,
        offset: offset ?? this.offset,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'text',
        'id': id,
        'name': name,
        'text': text,
        'color': color.value,
        'fontStyle': fontStyle.name,
        'fontSize': fontSize,
        'alignment': alignment.name,
        'effect': effect.name,
        'effectSpeedMs': effectSpeedMs,
        'visible': visible,
        'zIndex': zIndex,
        'opacity': opacity,
        'offsetX': offset.dx,
        'offsetY': offset.dy,
      };

  factory TextLayer.fromJson(Map<String, dynamic> j) => TextLayer(
        id: j['id'] as String,
        name: j['name'] as String,
        text: j['text'] as String,
        color: Color(j['color'] as int),
        fontStyle:
            FontStyle.values.byName(j['fontStyle'] as String? ?? 'matrixType'),
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 8,
        alignment: TextAlignment.values
            .byName(j['alignment'] as String? ?? 'center'),
        effect: AnimationEffect.values
            .byName(j['effect'] as String? ?? 'none'),
        effectSpeedMs: j['effectSpeedMs'] as int? ?? 100,
        visible: j['visible'] as bool? ?? true,
        zIndex: j['zIndex'] as int? ?? 0,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
        offset: Offset(
          (j['offsetX'] as num?)?.toDouble() ?? 0,
          (j['offsetY'] as num?)?.toDouble() ?? 0,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Clock Layer
// ─────────────────────────────────────────────────────────────────────────────

enum ClockFormat { h24, h12 }

enum ClockAlignment { left, center, right }

class ClockLayer extends Layer {
  Color color;
  ClockFormat format;
  ClockAlignment alignment;
  bool showDate;
  bool showSeconds;
  bool blinkColon;
  /// Timezone label (e.g. "Bangkok", "UTC", "America/New_York").
  String timezone;

  ClockLayer({
    required super.id,
    required super.name,
    this.color = const Color(0xFF21C32C),
    this.format = ClockFormat.h24,
    this.alignment = ClockAlignment.center,
    this.showDate = false,
    this.showSeconds = false,
    this.blinkColon = true,
    this.timezone = 'local',
    super.visible,
    super.zIndex,
    super.opacity,
    super.offset,
  });

  @override
  LayerType get type => LayerType.clock;

  @override
  ClockLayer copyWith({
    String? id,
    String? name,
    Color? color,
    ClockFormat? format,
    ClockAlignment? alignment,
    bool? showDate,
    bool? showSeconds,
    bool? blinkColon,
    String? timezone,
    bool? visible,
    int? zIndex,
    double? opacity,
    Offset? offset,
  }) =>
      ClockLayer(
        id: id ?? this.id,
        name: name ?? this.name,
        color: color ?? this.color,
        format: format ?? this.format,
        alignment: alignment ?? this.alignment,
        showDate: showDate ?? this.showDate,
        showSeconds: showSeconds ?? this.showSeconds,
        blinkColon: blinkColon ?? this.blinkColon,
        timezone: timezone ?? this.timezone,
        visible: visible ?? this.visible,
        zIndex: zIndex ?? this.zIndex,
        opacity: opacity ?? this.opacity,
        offset: offset ?? this.offset,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'clock',
        'id': id,
        'name': name,
        'color': color.value,
        'format': format.name,
        'alignment': alignment.name,
        'showDate': showDate,
        'showSeconds': showSeconds,
        'blinkColon': blinkColon,
        'timezone': timezone,
        'visible': visible,
        'zIndex': zIndex,
        'opacity': opacity,
        'offsetX': offset.dx,
        'offsetY': offset.dy,
      };

  factory ClockLayer.fromJson(Map<String, dynamic> j) => ClockLayer(
        id: j['id'] as String,
        name: j['name'] as String,
        color: Color(j['color'] as int),
        format: ClockFormat.values.byName(j['format'] as String? ?? 'h24'),
        alignment: ClockAlignment.values
            .byName(j['alignment'] as String? ?? 'center'),
        showDate: j['showDate'] as bool? ?? false,
        showSeconds: j['showSeconds'] as bool? ?? false,
        blinkColon: j['blinkColon'] as bool? ?? true,
        timezone: j['timezone'] as String? ?? 'local',
        visible: j['visible'] as bool? ?? true,
        zIndex: j['zIndex'] as int? ?? 0,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
        offset: Offset(
          (j['offsetX'] as num?)?.toDouble() ?? 0,
          (j['offsetY'] as num?)?.toDouble() ?? 0,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// GIF / Image Layer
// ─────────────────────────────────────────────────────────────────────────────

enum MediaLayout { letterbox, fill, stretch }

class GifLayer extends Layer {
  /// Absolute path or asset URI to the GIF/PNG/JPG file.
  String? filePath;
  MediaLayout layout;
  bool dithering;
  bool grayscale;
  bool invertColor;
  /// Frames-per-second override (null = use GIF's native timing).
  double? fpsOverride;

  GifLayer({
    required super.id,
    required super.name,
    this.filePath,
    this.layout = MediaLayout.letterbox,
    this.dithering = true,
    this.grayscale = false,
    this.invertColor = false,
    this.fpsOverride,
    super.visible,
    super.zIndex,
    super.opacity,
    super.offset,
  });

  @override
  LayerType get type => LayerType.gif;

  @override
  GifLayer copyWith({
    String? id,
    String? name,
    String? filePath,
    MediaLayout? layout,
    bool? dithering,
    bool? grayscale,
    bool? invertColor,
    double? fpsOverride,
    bool? visible,
    int? zIndex,
    double? opacity,
    Offset? offset,
  }) =>
      GifLayer(
        id: id ?? this.id,
        name: name ?? this.name,
        filePath: filePath ?? this.filePath,
        layout: layout ?? this.layout,
        dithering: dithering ?? this.dithering,
        grayscale: grayscale ?? this.grayscale,
        invertColor: invertColor ?? this.invertColor,
        fpsOverride: fpsOverride ?? this.fpsOverride,
        visible: visible ?? this.visible,
        zIndex: zIndex ?? this.zIndex,
        opacity: opacity ?? this.opacity,
        offset: offset ?? this.offset,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'gif',
        'id': id,
        'name': name,
        'filePath': filePath,
        'layout': layout.name,
        'dithering': dithering,
        'grayscale': grayscale,
        'invertColor': invertColor,
        'fpsOverride': fpsOverride,
        'visible': visible,
        'zIndex': zIndex,
        'opacity': opacity,
        'offsetX': offset.dx,
        'offsetY': offset.dy,
      };

  factory GifLayer.fromJson(Map<String, dynamic> j) => GifLayer(
        id: j['id'] as String,
        name: j['name'] as String,
        filePath: j['filePath'] as String?,
        layout:
            MediaLayout.values.byName(j['layout'] as String? ?? 'letterbox'),
        dithering: j['dithering'] as bool? ?? true,
        grayscale: j['grayscale'] as bool? ?? false,
        invertColor: j['invertColor'] as bool? ?? false,
        fpsOverride: (j['fpsOverride'] as num?)?.toDouble(),
        visible: j['visible'] as bool? ?? true,
        zIndex: j['zIndex'] as int? ?? 0,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
        offset: Offset(
          (j['offsetX'] as num?)?.toDouble() ?? 0,
          (j['offsetY'] as num?)?.toDouble() ?? 0,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Spotify Layer
// ─────────────────────────────────────────────────────────────────────────────

enum SpotifyLayout { artAndText, textOnly, artOnly }

class SpotifyLayer extends Layer {
  SpotifyLayout layout;
  bool showTitle;
  bool showArtist;
  bool showProgress;
  Color textColor;
  /// fps for artwork animation
  double fps;

  SpotifyLayer({
    required super.id,
    required super.name,
    this.layout = SpotifyLayout.artAndText,
    this.showTitle = true,
    this.showArtist = true,
    this.showProgress = true,
    this.textColor = const Color(0xFFFFFFFF),
    this.fps = 10,
    super.visible,
    super.zIndex,
    super.opacity,
    super.offset,
  });

  @override
  LayerType get type => LayerType.spotify;

  @override
  SpotifyLayer copyWith({
    String? id,
    String? name,
    SpotifyLayout? layout,
    bool? showTitle,
    bool? showArtist,
    bool? showProgress,
    Color? textColor,
    double? fps,
    bool? visible,
    int? zIndex,
    double? opacity,
    Offset? offset,
  }) =>
      SpotifyLayer(
        id: id ?? this.id,
        name: name ?? this.name,
        layout: layout ?? this.layout,
        showTitle: showTitle ?? this.showTitle,
        showArtist: showArtist ?? this.showArtist,
        showProgress: showProgress ?? this.showProgress,
        textColor: textColor ?? this.textColor,
        fps: fps ?? this.fps,
        visible: visible ?? this.visible,
        zIndex: zIndex ?? this.zIndex,
        opacity: opacity ?? this.opacity,
        offset: offset ?? this.offset,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'spotify',
        'id': id,
        'name': name,
        'layout': layout.name,
        'showTitle': showTitle,
        'showArtist': showArtist,
        'showProgress': showProgress,
        'textColor': textColor.value,
        'fps': fps,
        'visible': visible,
        'zIndex': zIndex,
        'opacity': opacity,
        'offsetX': offset.dx,
        'offsetY': offset.dy,
      };

  factory SpotifyLayer.fromJson(Map<String, dynamic> j) => SpotifyLayer(
        id: j['id'] as String,
        name: j['name'] as String,
        layout: SpotifyLayout.values
            .byName(j['layout'] as String? ?? 'artAndText'),
        showTitle: j['showTitle'] as bool? ?? true,
        showArtist: j['showArtist'] as bool? ?? true,
        showProgress: j['showProgress'] as bool? ?? true,
        textColor: Color(j['textColor'] as int? ?? 0xFFFFFFFF),
        fps: (j['fps'] as num?)?.toDouble() ?? 10,
        visible: j['visible'] as bool? ?? true,
        zIndex: j['zIndex'] as int? ?? 0,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
        offset: Offset(
          (j['offsetX'] as num?)?.toDouble() ?? 0,
          (j['offsetY'] as num?)?.toDouble() ?? 0,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Pomodoro Layer
// ─────────────────────────────────────────────────────────────────────────────

enum PomodoroState { focus, shortBreak, longBreak }

enum PomodoroLayout { defaultTimer }

class PomodoroLayer extends Layer {
  int focusDurationMinutes;
  int shortBreakMinutes;
  int longBreakMinutes;
  int sessionsBeforeLongBreak;
  PomodoroLayout layout;
  bool showSeconds;
  bool showSession;
  bool blinkColor;
  Color focusColor;
  Color breakColor;
  double fps;

  PomodoroLayer({
    required super.id,
    required super.name,
    this.focusDurationMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
    this.sessionsBeforeLongBreak = 4,
    this.layout = PomodoroLayout.defaultTimer,
    this.showSeconds = true,
    this.showSession = false,
    this.blinkColor = true,
    this.focusColor = const Color(0xFFFFCC00),
    this.breakColor = const Color(0xFF21C32C),
    this.fps = 10,
    super.visible,
    super.zIndex,
    super.opacity,
    super.offset,
  });

  @override
  LayerType get type => LayerType.pomodoro;

  @override
  PomodoroLayer copyWith({
    String? id,
    String? name,
    int? focusDurationMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    int? sessionsBeforeLongBreak,
    PomodoroLayout? layout,
    bool? showSeconds,
    bool? showSession,
    bool? blinkColor,
    Color? focusColor,
    Color? breakColor,
    double? fps,
    bool? visible,
    int? zIndex,
    double? opacity,
    Offset? offset,
  }) =>
      PomodoroLayer(
        id: id ?? this.id,
        name: name ?? this.name,
        focusDurationMinutes:
            focusDurationMinutes ?? this.focusDurationMinutes,
        shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
        longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
        sessionsBeforeLongBreak:
            sessionsBeforeLongBreak ?? this.sessionsBeforeLongBreak,
        layout: layout ?? this.layout,
        showSeconds: showSeconds ?? this.showSeconds,
        showSession: showSession ?? this.showSession,
        blinkColor: blinkColor ?? this.blinkColor,
        focusColor: focusColor ?? this.focusColor,
        breakColor: breakColor ?? this.breakColor,
        fps: fps ?? this.fps,
        visible: visible ?? this.visible,
        zIndex: zIndex ?? this.zIndex,
        opacity: opacity ?? this.opacity,
        offset: offset ?? this.offset,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'pomodoro',
        'id': id,
        'name': name,
        'focusDurationMinutes': focusDurationMinutes,
        'shortBreakMinutes': shortBreakMinutes,
        'longBreakMinutes': longBreakMinutes,
        'sessionsBeforeLongBreak': sessionsBeforeLongBreak,
        'layout': layout.name,
        'showSeconds': showSeconds,
        'showSession': showSession,
        'blinkColor': blinkColor,
        'focusColor': focusColor.value,
        'breakColor': breakColor.value,
        'fps': fps,
        'visible': visible,
        'zIndex': zIndex,
        'opacity': opacity,
        'offsetX': offset.dx,
        'offsetY': offset.dy,
      };

  factory PomodoroLayer.fromJson(Map<String, dynamic> j) => PomodoroLayer(
        id: j['id'] as String,
        name: j['name'] as String,
        focusDurationMinutes: j['focusDurationMinutes'] as int? ?? 25,
        shortBreakMinutes: j['shortBreakMinutes'] as int? ?? 5,
        longBreakMinutes: j['longBreakMinutes'] as int? ?? 15,
        sessionsBeforeLongBreak:
            j['sessionsBeforeLongBreak'] as int? ?? 4,
        layout: PomodoroLayout.values
            .byName(j['layout'] as String? ?? 'defaultTimer'),
        showSeconds: j['showSeconds'] as bool? ?? true,
        showSession: j['showSession'] as bool? ?? false,
        blinkColor: j['blinkColor'] as bool? ?? true,
        focusColor: Color(j['focusColor'] as int? ?? 0xFFFFCC00),
        breakColor: Color(j['breakColor'] as int? ?? 0xFF21C32C),
        fps: (j['fps'] as num?)?.toDouble() ?? 10,
        visible: j['visible'] as bool? ?? true,
        zIndex: j['zIndex'] as int? ?? 0,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
        offset: Offset(
          (j['offsetX'] as num?)?.toDouble() ?? 0,
          (j['offsetY'] as num?)?.toDouble() ?? 0,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Factory: deserialise any Layer from JSON
// ─────────────────────────────────────────────────────────────────────────────

Layer layerFromJson(Map<String, dynamic> j) {
  switch (j['type'] as String) {
    case 'text':
      return TextLayer.fromJson(j);
    case 'clock':
      return ClockLayer.fromJson(j);
    case 'gif':
      return GifLayer.fromJson(j);
    case 'spotify':
      return SpotifyLayer.fromJson(j);
    case 'pomodoro':
      return PomodoroLayer.fromJson(j);
    default:
      throw ArgumentError('Unknown layer type: ${j['type']}');
  }
}