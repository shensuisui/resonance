/// 车载歌词：配置、槽位映射与歌词行选择（纯逻辑，便于单测）
///
/// 背景：蓝牙 AVRCP 只传 TITLE/ARTIST/ALBUM 等标准字段，没有歌词字段；
/// 因此把“当前歌词行”写进 title 或 artist，让车机在对应行显示。
library;

import 'lyrics.dart';

/// 显示范围
enum CarLyricsScope {
  /// 关闭（不注入）
  off,

  /// 仅车载（识别为车机时注入）
  car,

  /// 所有蓝牙设备都注入
  all,
}

/// 歌词显示位置
enum CarLyricsSlot {
  /// 第一行（title）
  title,

  /// 第二行（artist）
  artist,
}

/// 设置键（设备本地）
abstract final class CarLyricsSettingsKeys {
  /// 显示范围
  static const String scope = 'car_lyrics_scope';

  /// 显示位置
  static const String slot = 'car_lyrics_slot';

  /// 反序列化显示范围（未知值按 off）
  static CarLyricsScope scopeFrom(String? value) => switch (value) {
        'car' => CarLyricsScope.car,
        'all' => CarLyricsScope.all,
        _ => CarLyricsScope.off,
      };

  /// 序列化显示范围
  static String scopeValue(CarLyricsScope value) => switch (value) {
        CarLyricsScope.off => 'off',
        CarLyricsScope.car => 'car',
        CarLyricsScope.all => 'all',
      };

  /// 反序列化显示位置（未知值按 title）
  static CarLyricsSlot slotFrom(String? value) =>
      value == 'artist' ? CarLyricsSlot.artist : CarLyricsSlot.title;

  /// 序列化显示位置
  static String slotValue(CarLyricsSlot value) => switch (value) {
        CarLyricsSlot.title => 'title',
        CarLyricsSlot.artist => 'artist',
      };
}

/// 车载歌词配置
class CarLyricsConfig {
  /// 显示范围
  final CarLyricsScope scope;

  /// 显示位置
  final CarLyricsSlot slot;

  /// 构造
  const CarLyricsConfig({
    this.scope = CarLyricsScope.off,
    this.slot = CarLyricsSlot.title,
  });

  /// 从设置值还原
  factory CarLyricsConfig.fromSettings({String? scope, String? slot}) =>
      CarLyricsConfig(
        scope: CarLyricsSettingsKeys.scopeFrom(scope),
        slot: CarLyricsSettingsKeys.slotFrom(slot),
      );

  /// 复制
  CarLyricsConfig copyWith({CarLyricsScope? scope, CarLyricsSlot? slot}) =>
      CarLyricsConfig(scope: scope ?? this.scope, slot: slot ?? this.slot);

  @override
  bool operator ==(Object other) =>
      other is CarLyricsConfig && other.scope == scope && other.slot == slot;

  @override
  int get hashCode => Object.hash(scope, slot);
}

/// 要写入系统媒体元数据的两个字段（null 表示不改）
class CarLyricsMetadata {
  /// 第一行
  final String? title;

  /// 第二行
  final String? artist;

  /// 构造
  const CarLyricsMetadata({this.title, this.artist});

  @override
  bool operator ==(Object other) =>
      other is CarLyricsMetadata && other.title == title && other.artist == artist;

  @override
  int get hashCode => Object.hash(title, artist);

  @override
  String toString() => 'CarLyricsMetadata(title: $title, artist: $artist)';
}

/// 歌曲信息行：`歌手 - 歌名`（缺一取另一个；都空返回空串）
String formatSongInfo({required String title, required String artist}) {
  final t = title.trim();
  final a = artist.trim();
  if (a.isEmpty) return t;
  if (t.isEmpty) return a;
  return '$a - $t';
}

/// 计算应写入的元数据；返回 null 表示不注入（恢复系统默认）
///
/// 规则：
///   * scope=off → 不注入；
///   * 未连接蓝牙音频 → 不注入（避免通知栏/锁屏无故变歌词）；
///   * scope=car 且未识别为车机 → 不注入；
///   * 当前没有歌词行（空行/未取到）→ 不注入。
CarLyricsMetadata? resolveCarLyricsMetadata({
  required CarLyricsConfig config,
  required bool bluetoothConnected,
  required bool carDetected,
  required String? lyricLine,
  required String songTitle,
  required String songArtist,
}) {
  if (config.scope == CarLyricsScope.off) return null;
  if (!bluetoothConnected) return null;
  if (config.scope == CarLyricsScope.car && !carDetected) return null;
  final line = lyricLine?.trim() ?? '';
  if (line.isEmpty) return null;

  final info = formatSongInfo(title: songTitle, artist: songArtist);
  return switch (config.slot) {
    CarLyricsSlot.title => CarLyricsMetadata(title: line, artist: info),
    CarLyricsSlot.artist => CarLyricsMetadata(title: info, artist: line),
  };
}

/// 二分查找当前播放位置对应的歌词行下标（无则 null）
///
/// 只返回 `time <= position` 的最后一行；空文本行会被跳过（正常 LRC 常有空行）。
int? carLyricLineIndexAt(List<LyricLine> lines, Duration position) {
  if (lines.isEmpty) return null;
  final ms = position.inMilliseconds;
  var lo = 0;
  var hi = lines.length - 1;
  var found = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (lines[mid].time.inMilliseconds <= ms) {
      found = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  if (found < 0) return null;
  // 从 found 往前找最近的非空行（空行不显示）
  for (var i = found; i >= 0; i--) {
    if (lines[i].text.trim().isNotEmpty) return i;
  }
  return null;
}
