/// 曲库展示元数据模型。
///
/// 演示曲库的真实数据（搜索、详情、歌词、歌单、播放）已经迁到 demo_source，
/// App 内不再内置任何专辑/曲目/歌词常量。这个文件只保留通用的展示结构：
/// Debug 启动时由壳工程把 `/catalog.json` 注入 [catalogProvider]，
/// Release 默认使用 [Catalog.empty]，页面会自动退化为正常空状态。
library;

/// 演示源固定 id（仅用于把展示元数据映射成带全局键的 Song）
const String kCatalogSourceId = 'demo_catalog';

/// 来源展示名兜底表（真实注册源的名字优先，见 rows.dart）
///
/// 不再写死演示源名：Debug 下规则源会注册成“演示曲库”，
/// Release 里连这个字符串都不需要存在。
const Map<String, String> kSourceDisplayNames = {
  'local': '本地',
};

/// 曲目展示元数据
class CatalogTrack {
  /// 曲目 id（`<albumId>#<no>`）
  final String id;

  /// 专辑内曲目号（1 起）
  final int no;

  /// 曲名
  final String title;

  /// 艺人
  final String artist;

  /// 专辑 id
  final String albumId;

  /// 专辑名
  final String album;

  /// 封面 URL（由演示服务提供，不再是 App 资产路径）
  final String cover;

  /// 流派
  final String genre;

  /// 时长（秒，由演示服务在 JSON 中给出）
  final int duration;

  /// 是否本地曲目
  final bool local;

  /// 是否已下载
  final bool downloaded;

  /// 旧配表里的归属 id（fy / aiting / yu7 / local）
  final String sourceId;

  /// 构造曲目元数据
  const CatalogTrack({
    required this.id,
    required this.no,
    required this.title,
    required this.artist,
    required this.albumId,
    required this.album,
    required this.cover,
    required this.genre,
    required this.duration,
    required this.local,
    required this.downloaded,
    required this.sourceId,
  });

  /// 从 /catalog.json 的曲目项解析
  factory CatalogTrack.fromJson(Map<String, dynamic> json) => CatalogTrack(
        id: json['id'] as String,
        no: (json['no'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        albumId: json['albumId'] as String? ?? '',
        album: json['album'] as String? ?? '',
        cover: json['cover'] as String? ?? '',
        genre: json['genre'] as String? ?? '',
        duration: (json['duration'] as num?)?.toInt() ?? 0,
        local: json['local'] as bool? ?? false,
        downloaded: json['downloaded'] as bool? ?? false,
        sourceId: json['sourceId'] as String? ?? 'local',
      );
}

/// 专辑展示元数据
class CatalogAlbum {
  /// 专辑 id
  final String id;

  /// 专辑名
  final String title;

  /// 艺人
  final String artist;

  /// 发行年
  final int year;

  /// 流派
  final String genre;

  /// 封面 URL
  final String cover;

  /// 是否本地导入
  final bool imported;

  /// 是否已下载
  final bool downloaded;

  /// 曲目
  final List<CatalogTrack> tracks;

  /// 构造专辑
  const CatalogAlbum({
    required this.id,
    required this.title,
    required this.artist,
    required this.year,
    required this.genre,
    required this.cover,
    required this.imported,
    required this.downloaded,
    required this.tracks,
  });
}

/// 艺人（从专辑表派生）
class CatalogArtist {
  /// 艺人名
  final String name;

  /// 该艺人的专辑
  final List<CatalogAlbum> albums;

  /// 该艺人的全部曲目
  final List<CatalogTrack> tracks;

  /// 构造艺人
  const CatalogArtist({
    required this.name,
    required this.albums,
    required this.tracks,
  });
}

/// 曲库展示表与查询入口。
class Catalog {
  /// 全部专辑（按服务端给定顺序）
  final List<CatalogAlbum> albums;

  /// 全部曲目
  final List<CatalogTrack> tracks;

  /// 全部艺人（按名字排序）
  final List<CatalogArtist> artists;

  final Map<String, CatalogAlbum> _albumById;
  final Map<String, CatalogTrack> _trackById;

  Catalog._({
    required this.albums,
    required this.tracks,
    required this.artists,
    required Map<String, CatalogAlbum> albumById,
    required Map<String, CatalogTrack> trackById,
  })  : _albumById = albumById,
        _trackById = trackById;

  /// 空目录：Release 的默认值，页面显示正常空态。
  factory Catalog.empty() => Catalog._(
        albums: const [],
        tracks: const [],
        artists: const [],
        albumById: const {},
        trackById: const {},
      );

  /// 从演示服务的 /catalog.json 构造。
  ///
  /// 响应里的 tracks 是完整曲目项，albums.tracks 只是 id 列表；这样服务端只算一次
  /// 时长/归属，App 不再复制配表推导逻辑。
  factory Catalog.fromJson(Map<String, dynamic> json) {
    final trackById = <String, CatalogTrack>{};
    final tracks = <CatalogTrack>[];
    for (final raw in (json['tracks'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()) {
      final track = CatalogTrack.fromJson(raw);
      trackById[track.id] = track;
      tracks.add(track);
    }

    final albums = <CatalogAlbum>[];
    final albumById = <String, CatalogAlbum>{};
    for (final raw in (json['albums'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()) {
      final ids = (raw['tracks'] as List<dynamic>? ?? const []).cast<String>();
      final album = CatalogAlbum(
        id: raw['id'] as String,
        title: raw['title'] as String? ?? '',
        artist: raw['artist'] as String? ?? '',
        year: (raw['year'] as num?)?.toInt() ?? 0,
        genre: raw['genre'] as String? ?? '',
        cover: raw['cover'] as String? ?? '',
        imported: raw['imported'] as bool? ?? false,
        downloaded: raw['downloaded'] as bool? ?? false,
        tracks: ids
            .map((id) => trackById[id])
            .whereType<CatalogTrack>()
            .toList(growable: false),
      );
      albums.add(album);
      albumById[album.id] = album;
    }

    final artistAlbums = <String, List<CatalogAlbum>>{};
    final artistTracks = <String, List<CatalogTrack>>{};
    for (final album in albums) {
      artistAlbums.putIfAbsent(album.artist, () => <CatalogAlbum>[]).add(album);
      artistTracks
          .putIfAbsent(album.artist, () => <CatalogTrack>[])
          .addAll(album.tracks);
    }
    final artists = artistAlbums.keys
        .map((name) => CatalogArtist(
              name: name,
              albums: artistAlbums[name]!,
              tracks: artistTracks[name]!,
            ))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Catalog._(
      albums: albums,
      tracks: tracks,
      artists: artists,
      albumById: albumById,
      trackById: trackById,
    );
  }

  /// 按 id 取专辑
  CatalogAlbum? album(String id) => _albumById[id];

  /// 按 id 取曲目
  CatalogTrack? track(String id) => _trackById[id];

  /// 批量解析曲目引用
  List<CatalogTrack> resolve(List<String> refs) =>
      refs.map((ref) => _trackById[ref]).whereType<CatalogTrack>().toList();

  /// 列表里显示的行号（等价原型 num = index == null ? t.no : index + 1）
  int displayNo(CatalogTrack track, int index) => index + 1;
}

/// 播放设备选项（纯 UI 常量，与演示曲库数据无关）
class DeviceOption {
  /// 设备名
  final String name;

  /// 设备说明
  final String hint;

  /// 构建设备项
  const DeviceOption(this.name, this.hint);
}

/// 播放设备清单
const List<DeviceOption> kDeviceOptions = [
  DeviceOption('本机扬声器', '这台设备'),
  DeviceOption('客厅音箱', 'Wi-Fi · 上次连接 2 天前'),
  DeviceOption('Bose QC45', '蓝牙'),
];

/// 睡眠定时器可选分钟数
const List<int> kSleepMinutes = [15, 30, 60, 90];

/// 最近播放上限
const int kRecentMax = 500;

/// 曲目排序方式（我喜欢的音乐页）
enum LikedSort {
  /// 最近喜欢（默认，新→旧）
  recent('最近喜欢'),

  /// 按标题
  title('标题'),

  /// 按时长（长→短）
  duration('时长');

  /// 展示名
  final String label;

  const LikedSort(this.label);
}

/// 秒 → `m:ss`
String formatDuration(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r < 10 ? '0' : ''}$r';
}

/// 秒 → 中文长描述（`2 小时 5 分` / `45 分钟`）
String formatDurationLong(int seconds) {
  var m = (seconds / 60).round();
  final h = m ~/ 60;
  m = m % 60;
  return h > 0 ? '$h 小时 $m 分' : '$m 分钟';
}

/// 字符串哈希（用于文件夹 id 等）
int hashStr(String s) {
  var h = 0;
  for (var i = 0; i < s.length; i++) {
    h = (h * 31 + s.codeUnitAt(i)) & 0x7FFFFFFF;
  }
  return h;
}
