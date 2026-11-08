// Player settings and game configuration (ported from Game.ts).

import 'dart:convert';

import '../chess/types.dart';

enum GameMode { bot, local }

enum GameStatus { playing, checkmate, stalemate, draw, resigned }

enum Quality { high, low }

/// What the menu stores for "your colour": a side or a random pick.
enum HumanColor { white, black, random }

class GameConfig {
  final GameMode mode;
  final Side humanColor;
  final int elo;
  const GameConfig({this.mode = GameMode.bot, this.humanColor = Side.w, this.elo = 1200});

  Map<String, Object> toJson() => {'mode': mode.name, 'humanColor': humanColor.ch, 'elo': elo};

  static GameConfig? fromJson(Object? j) {
    if (j is! Map) return null;
    final mode = j['mode'] == 'local' ? GameMode.local : GameMode.bot;
    final human = j['humanColor'] == 'b' ? Side.b : Side.w;
    final elo = j['elo'] is num ? (j['elo'] as num).round() : 1200;
    return GameConfig(mode: mode, humanColor: human, elo: elo);
  }

  @override
  bool operator ==(Object other) =>
      other is GameConfig && other.mode == mode && other.humanColor == humanColor && other.elo == elo;

  @override
  int get hashCode => Object.hash(mode, humanColor, elo);
}

class Settings {
  final bool sound;
  final bool labels;
  final Quality quality;
  final bool autoFlip;
  final int elo;
  final HumanColor humanColor;
  final GameMode mode;

  const Settings({
    this.sound = true,
    this.labels = true,
    this.quality = Quality.high,
    this.autoFlip = false,
    this.elo = 1200,
    this.humanColor = HumanColor.white,
    this.mode = GameMode.bot,
  });

  Settings copyWith({
    bool? sound,
    bool? labels,
    Quality? quality,
    bool? autoFlip,
    int? elo,
    HumanColor? humanColor,
    GameMode? mode,
  }) =>
      Settings(
        sound: sound ?? this.sound,
        labels: labels ?? this.labels,
        quality: quality ?? this.quality,
        autoFlip: autoFlip ?? this.autoFlip,
        elo: elo ?? this.elo,
        humanColor: humanColor ?? this.humanColor,
        mode: mode ?? this.mode,
      );

  String encode() => jsonEncode({
        'sound': sound,
        'labels': labels,
        'quality': quality.name,
        'autoFlip': autoFlip,
        'elo': elo,
        'humanColor': humanColor.name,
        'mode': mode.name,
      });

  /// Tolerant decoding: anything missing or malformed falls back to the default.
  static Settings decode(String? text) {
    if (text == null || text.isEmpty) return const Settings();
    try {
      final j = jsonDecode(text);
      if (j is! Map) return const Settings();
      T pick<T extends Enum>(List<T> values, Object? v, T d) {
        for (final e in values) {
          if (e.name == v) return e;
        }
        return d;
      }

      return Settings(
        sound: j['sound'] is bool ? j['sound'] as bool : true,
        labels: j['labels'] is bool ? j['labels'] as bool : true,
        quality: pick(Quality.values, j['quality'], Quality.high),
        autoFlip: j['autoFlip'] is bool ? j['autoFlip'] as bool : false,
        elo: j['elo'] is num ? (j['elo'] as num).round().clamp(400, 3200) : 1200,
        humanColor: pick(HumanColor.values, j['humanColor'], HumanColor.white),
        mode: pick(GameMode.values, j['mode'], GameMode.bot),
      );
    } catch (_) {
      return const Settings();
    }
  }

  @override
  bool operator ==(Object other) => other is Settings && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}

String eloName(int e) {
  if (e < 600) return 'Beginner';
  if (e < 1000) return 'Novice';
  if (e < 1400) return 'Casual';
  if (e < 1800) return 'Club player';
  if (e < 2200) return 'Advanced';
  if (e < 2600) return 'Expert';
  if (e < 3000) return 'Master';
  return 'Grandmaster+';
}
