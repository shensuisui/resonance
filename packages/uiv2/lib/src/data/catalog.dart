/// 曲库演示数据 —— 逐字复刻原型 assets/app.js 第 12~290 行的配表。
///
/// 原型的做法是「配表驱动」：专辑、曲目、来源归属、歌单、分类全部是数据表，
/// 逻辑里不留特例。这里保持一致：本文件只放数据与派生结构，不放业务判断。
///
/// 曲目 id 形如 `<albumId>#<no>`，与原型一致；封面路径约定
/// `assets/covers/<albumId>.jpg`（fm_app/assets/covers/ 下随资产打包）。
library;

import 'package:flutter/widgets.dart';

/// 曲库资源根路径（封面）
const String kCoverRoot = 'assets/covers';

/// 专辑 + 曲目标题表（原型 ALBUM_DATA）
class AlbumSeed {
  /// 专辑 id（同时是封面文件名）
  final String id;

  /// 专辑名
  final String title;

  /// 艺人
  final String artist;

  /// 发行年
  final int year;

  /// 流派
  final String genre;

  /// 曲目标题（顺序即曲目号）
  final List<String> tracks;

  /// 构造专辑原始数据
  const AlbumSeed({
    required this.id,
    required this.title,
    required this.artist,
    required this.year,
    required this.genre,
    required this.tracks,
  });
}

/// 专辑配表（原型 ALBUM_DATA 原样搬运）
const List<AlbumSeed> kAlbumSeeds = [
  AlbumSeed(
    id: 'abbey-road',
    title: 'Abbey Road',
    artist: 'The Beatles',
    year: 1969,
    genre: '摇滚',
    tracks: [
      'Come Together', 'Something', "Maxwell's Silver Hammer", "Oh! Darling",
      "Octopus's Garden", 'I Want You (She\u2019s So Heavy)',
      'Here Comes the Sun', 'Because', 'You Never Give Me Your Money',
      'Sun King', 'Mean Mr. Mustard', 'Polythene Pam',
      'She Came in Through the Bathroom Window', 'Golden Slumbers',
      'Carry That Weight', 'The End', 'Her Majesty',
    ],
  ),
  AlbumSeed(
    id: 'random-access-memories',
    title: 'Random Access Memories',
    artist: 'Daft Punk',
    year: 2013,
    genre: '电子',
    tracks: [
      'Give Life Back to Music', 'The Game of Love', 'Giorgio by Moroder',
      'Within', 'Instant Crush', 'Lose Yourself to Dance', 'Touch',
      'Get Lucky', 'Beyond', 'Motherhood', 'Fragments of Time',
      "Doin' It Right", 'Contact',
    ],
  ),
  AlbumSeed(
    id: 'blonde',
    title: 'Blonde',
    artist: 'Frank Ocean',
    year: 2016,
    genre: 'R&B',
    tracks: [
      'Nikes', 'Ivy', 'Pink + White', 'Be Yourself', 'Solo', 'Skyline To',
      'Self Control', 'Good Guy', 'Nights', 'Solo (Reprise)', 'Pretty Sweet',
      'Facebook Story', 'Close to You', 'White Ferrari', 'Seigfried',
      'Godspeed', 'Futura Free',
    ],
  ),
  AlbumSeed(
    id: 'kind-of-blue',
    title: 'Kind of Blue',
    artist: 'Miles Davis',
    year: 1959,
    genre: '爵士',
    tracks: [
      'So What', 'Freddie Freeloader', 'Blue in Green', 'All Blues',
      'Flamenco Sketches',
    ],
  ),
  AlbumSeed(
    id: 'ok-computer',
    title: 'OK Computer',
    artist: 'Radiohead',
    year: 1997,
    genre: '摇滚',
    tracks: [
      'Airbag', 'Paranoid Android', 'Subterranean Homesick Alien',
      'Exit Music (For a Film)', 'Let Down', 'Karma Police', 'Fitter Happier',
      'Electioneering', 'Climbing Up the Walls', 'No Surprises', 'Lucky',
      'The Tourist',
    ],
  ),
  AlbumSeed(
    id: 'midnights',
    title: 'Midnights',
    artist: 'Taylor Swift',
    year: 2022,
    genre: '流行',
    tracks: [
      'Lavender Haze', 'Maroon', 'Anti-Hero', 'Snow on the Beach',
      "You're on Your Own, Kid", 'Midnight Rain', 'Question...?',
      'Vigilante Shit', 'Bejeweled', 'Labyrinth', 'Karma', 'Sweet Nothing',
      'Mastermind',
    ],
  ),
  AlbumSeed(
    id: 'when-we-all-fall-asleep',
    title: 'When We All Fall Asleep, Where Do We Go?',
    artist: 'Billie Eilish',
    year: 2019,
    genre: '流行',
    tracks: [
      '!!!!!!!', 'Bad Guy', 'Xanny', 'You Should See Me in a Crown',
      'All the Good Girls Go to Hell', 'Wish You Were Gay',
      "When the Party's Over", '8', 'My Strange Addiction', 'Bury a Friend',
      'Ilomilo', 'Listen Before I Go', 'I Love You', 'Goodbye',
    ],
  ),
  AlbumSeed(
    id: 'dark-side-of-the-moon',
    title: 'The Dark Side of the Moon',
    artist: 'Pink Floyd',
    year: 1973,
    genre: '摇滚',
    tracks: [
      'Speak to Me', 'Breathe (In the Air)', 'On the Run', 'Time',
      'The Great Gig in the Sky', 'Money', 'Us and Them', 'Any Colour You Like',
      'Brain Damage', 'Eclipse',
    ],
  ),
  AlbumSeed(
    id: 'damn',
    title: 'DAMN.',
    artist: 'Kendrick Lamar',
    year: 2017,
    genre: '嘻哈',
    tracks: [
      'BLOOD.', 'DNA.', 'YAH.', 'ELEMENT.', 'FEEL.', 'LOYALTY.', 'PRIDE.',
      'HUMBLE.', 'LUST.', 'LOVE.', 'XXX.', 'FEAR.', 'GOD.', 'DUCKWORTH.',
    ],
  ),
  AlbumSeed(
    id: 'rumours',
    title: 'Rumours',
    artist: 'Fleetwood Mac',
    year: 1977,
    genre: '摇滚',
    tracks: [
      'Second Hand News', 'Dreams', 'Never Going Back Again', "Don't Stop",
      'Go Your Own Way', 'Songbird', 'The Chain', 'You Make Loving Fun',
      "I Don't Want to Know", 'Oh Daddy', 'Gold Dust Woman',
    ],
  ),
  AlbumSeed(
    id: 'nevermind',
    title: 'Nevermind',
    artist: 'Nirvana',
    year: 1991,
    genre: '摇滚',
    tracks: [
      'Smells Like Teen Spirit', 'In Bloom', 'Come as You Are', 'Breed',
      'Lithium', 'Polly', 'Territorial Pissings', 'Drain You', 'Lounge Act',
      'Stay Away', 'On a Plain', 'Something in the Way',
    ],
  ),
  AlbumSeed(
    id: 'thriller',
    title: 'Thriller',
    artist: 'Michael Jackson',
    year: 1982,
    genre: '流行',
    tracks: [
      "Wanna Be Startin' Somethin'", 'Baby Be Mine', 'The Girl Is Mine',
      'Thriller', 'Beat It', 'Billie Jean', 'Human Nature',
      'P.Y.T. (Pretty Young Thing)', 'The Lady in My Life',
    ],
  ),
  AlbumSeed(
    id: 'back-to-black',
    title: 'Back to Black',
    artist: 'Amy Winehouse',
    year: 2006,
    genre: '灵魂乐',
    tracks: [
      'Rehab', "You Know I'm No Good", 'Me & Mr Jones', 'Just Friends',
      'Back to Black', 'Love Is a Losing Game', 'Tears Dry on Their Own',
      'Wake Up Alone', 'Some Unholy War', 'He Can Only Hold Her',
    ],
  ),
  AlbumSeed(
    id: 'future-nostalgia',
    title: 'Future Nostalgia',
    artist: 'Dua Lipa',
    year: 2020,
    genre: '流行',
    tracks: [
      'Future Nostalgia', "Don't Start Now", 'Cool', 'Physical', 'Levitating',
      'Pretty Please', 'Hallucinate', 'Love Again', 'Break My Heart',
      'Good in Bed', 'Boys Will Be Boys',
    ],
  ),
  AlbumSeed(
    id: 'a-night-at-the-opera',
    title: 'A Night at the Opera',
    artist: 'Queen',
    year: 1975,
    genre: '摇滚',
    tracks: [
      'Death on Two Legs', 'Lazing on a Sunday Afternoon',
      "I'm in Love with My Car", "You're My Best Friend", "'39", 'Sweet Lady',
      'Seaside Rendezvous', "The Prophet's Song", 'Love of My Life',
      'Good Company', 'Bohemian Rhapsody', 'God Save the Queen',
    ],
  ),
  AlbumSeed(
    id: 'blue',
    title: 'Blue',
    artist: 'Joni Mitchell',
    year: 1971,
    genre: '民谣',
    tracks: [
      'All I Want', 'My Old Man', 'Little Green', 'Carey', 'Blue', 'California',
      'This Flight Tonight', 'River', 'A Case of You',
      'The Last Time I Saw Richard',
    ],
  ),
];

/// 本地导入专辑（原型 IMPORTED_ALBUMS）
const List<String> kImportedAlbumIds = [
  'kind-of-blue', 'blue', 'a-night-at-the-opera',
];

/// 本地导入的单曲（原型 IMPORTED_EXTRA）
const List<String> kImportedExtraTrackIds = ['nevermind#11', 'rumours#7'];

/// 已下载专辑（原型 DOWNLOADED_ALBUMS）
const List<String> kDownloadedAlbumIds = [
  'midnights', 'future-nostalgia', 'abbey-road',
];

/// 初始喜欢的曲目（原型 SEED_LIKED）
const List<String> kSeedLikedTrackIds = [
  'abbey-road#7', 'blonde#7', 'dark-side-of-the-moon#4', 'kind-of-blue#1',
];

/// 初始最近播放（原型 SEED_RECENT）
const List<String> kSeedRecentTrackIds = [
  'midnights#3', 'future-nostalgia#2', 'ok-computer#2', 'rumours#3',
  'back-to-black#5',
];

/// 首页推荐曲目（原型 SEED_RECOMMEND）
const List<String> kSeedRecommendTrackIds = [
  'midnights#3', 'future-nostalgia#2', 'ok-computer#2', 'blonde#7',
  'back-to-black#5', 'rumours#3', 'kind-of-blue#1', 'dark-side-of-the-moon#4',
];

/// 音乐源类型标签（原型 SOURCE_TYPES）
const Map<String, String> kSourceTypeLabels = {
  'local': '本地',
  'rule': '规则',
  'plugin': '插件',
};

/// 演示曲目的来源标识
///
/// 原型所有曲目都归在 fy / aiting / yu7 三个演示源下；这里保留该归属（配表原样），
/// 同时给「没有配到源」的曲目一个明确标识，行尾标签会显示「演示曲库」，
/// 避免出现一个查不到、也解释不清的 sourceId。
const String kDemoSourceId = 'demo';

/// 来源展示名回退表（曲目行尾标签用）
const Map<String, String> kSourceDisplayNames = {
  kDemoSourceId: '演示曲库',
  'local': '本地',
  'fy': '枫叶',
  'aiting': '爱听',
  'yu7': 'Yu7',
};

/// 演示音乐源（原型 SOURCE_SEED）
class SourceSeed {
  /// 源 id
  final String id;

  /// 源名
  final String name;

  /// 源类型（rule / plugin）
  final String type;

  /// 构造演示源
  const SourceSeed({required this.id, required this.name, required this.type});
}

/// 演示源清单
const List<SourceSeed> kSourceSeeds = [
  SourceSeed(id: 'fy', name: '枫叶', type: 'rule'),
  SourceSeed(id: 'aiting', name: '爱听', type: 'rule'),
  SourceSeed(id: 'yu7', name: 'Yu7', type: 'plugin'),
];

/// 专辑级来源归属（原型 SOURCE_BY_ALBUM）
const Map<String, String> kSourceByAlbum = {
  'midnights': 'fy',
  'future-nostalgia': 'fy',
  'when-we-all-fall-asleep': 'fy',
  'random-access-memories': 'fy',
  'abbey-road': 'fy',
  'damn': 'fy',
  'ok-computer': 'aiting',
  'blonde': 'aiting',
  'kind-of-blue': 'aiting',
  'nevermind': 'aiting',
  'blue': 'aiting',
  'back-to-black': 'yu7',
  'rumours': 'yu7',
  'dark-side-of-the-moon': 'yu7',
  'thriller': 'yu7',
  'a-night-at-the-opera': 'yu7',
};

/// 单曲级来源覆盖（原型 SOURCE_BY_TRACK）
const Map<String, String> kSourceByTrack = {
  'midnights#3': 'fy',
  'blonde#7': 'aiting',
  'rumours#3': 'yu7',
};

/// 歌单配表（原型 PLAYLIST_DATA）
class PlaylistSeed {
  /// 歌单 id
  final String id;

  /// 歌单名
  final String name;

  /// 一句话描述
  final String desc;

  /// 主题色：渐变起点 / 拼贴占位色
  final Color color;

  /// 深色端（原型 colors[1]）
  final Color colorDark;

  /// 曲目引用（`<albumId>#<no>`）
  final List<String> refs;

  /// 是否自建歌单
  final bool user;

  /// 构造歌单原始数据
  const PlaylistSeed({
    required this.id,
    required this.name,
    required this.desc,
    required this.color,
    required this.colorDark,
    required this.refs,
    this.user = false,
  });
}

/// 歌单配表（含一条自建歌单「通勤路上」，与原型的初始 store.userPlaylists 一致）
const List<PlaylistSeed> kPlaylistSeeds = [
  PlaylistSeed(
    id: 'pl-night-drive',
    name: '深夜公路',
    desc: '低速巡航与霓虹灯影',
    color: Color(0xFFFF5A3C),
    colorDark: Color(0xFF2A1B4D),
    refs: [
      'random-access-memories#8', 'blonde#9', 'ok-computer#6',
      'dark-side-of-the-moon#4', 'back-to-black#5', 'future-nostalgia#2',
      'nevermind#11', 'midnights#6',
    ],
  ),
  PlaylistSeed(
    id: 'pl-focus',
    name: '专注工作',
    desc: '不抢注意力的长线条',
    color: Color(0xFF1F6C7A),
    colorDark: Color(0xFF123A44),
    refs: [
      'kind-of-blue#1', 'kind-of-blue#3', 'dark-side-of-the-moon#7',
      'ok-computer#4', 'blonde#14', 'blue#9', 'random-access-memories#3',
      'rumours#7',
    ],
  ),
  PlaylistSeed(
    id: 'pl-morning',
    name: '清晨唤醒',
    desc: '把窗帘拉开的那一下',
    color: Color(0xFFE0A33C),
    colorDark: Color(0xFFB4452B),
    refs: [
      'abbey-road#7', 'future-nostalgia#5', 'thriller#6', 'midnights#3',
      'a-night-at-the-opera#11', 'rumours#2', 'future-nostalgia#9',
    ],
  ),
  PlaylistSeed(
    id: 'pl-rock-90s',
    name: '九十年代摇滚',
    desc: '失真、贝斯线与嘶吼',
    color: Color(0xFF5A2E2E),
    colorDark: Color(0xFF1B1B22),
    refs: [
      'ok-computer#2', 'nevermind#1', 'nevermind#5', 'ok-computer#10',
      'nevermind#3', 'ok-computer#6', 'nevermind#12',
    ],
  ),
  PlaylistSeed(
    id: 'pl-jazz',
    name: '爵士夜',
    desc: '一杯不加冰的威士忌',
    color: Color(0xFF1F6C7A),
    colorDark: Color(0xFF14171C),
    refs: [
      'kind-of-blue#1', 'kind-of-blue#2', 'kind-of-blue#3', 'kind-of-blue#4',
      'kind-of-blue#5', 'back-to-black#4', 'blue#9', 'blue#10',
    ],
  ),
  PlaylistSeed(
    id: 'pl-today',
    name: '今日推荐',
    desc: '按你的收听习惯生成',
    color: Color(0xFF3B4C9E),
    colorDark: Color(0xFF7A3A63),
    refs: [
      'abbey-road#2', 'blonde#3', 'damn#8', 'when-we-all-fall-asleep#2',
      'future-nostalgia#4', 'rumours#5', 'thriller#5',
      'a-night-at-the-opera#1',
    ],
  ),
  PlaylistSeed(
    id: 'up-commute',
    name: '通勤路上',
    desc: '单程刚好听完',
    color: Color(0xFF3B4C9E),
    colorDark: Color(0xFF14171C),
    refs: [
      'midnights#3', 'future-nostalgia#2', 'abbey-road#7', 'rumours#5',
      'nevermind#2',
    ],
    user: true,
  ),
];

/// 音乐库分栏 → 该来源提供的歌单 id（原型 SOURCE_PLAYLISTS）
const Map<String, List<String>> kSourcePlaylists = {
  'fy': ['pl-today', 'pl-night-drive'],
  'aiting': ['pl-focus', 'pl-jazz'],
  'yu7': ['pl-rock-90s', 'pl-morning'],
};

/// 播放设备选项（原型 DEVICE_OPTIONS）
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

/// 睡眠定时器可选分钟数（原型 openSleepSheet 的 opts）
const List<int> kSleepMinutes = [15, 30, 60, 90];

/// 最近播放上限（原型 RECENT_MAX）
const int kRecentMax = 500;

/// 歌词注记（原型 .np__lyrics-note 文案）
const String kLyricsNote = '示例歌词 · 非原曲文本';

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

/// 曲库派生结构：专辑 / 曲目 / 艺人，全部由配表计算得出。
///
/// 原型在 app.js 里一次性构建 ALBUMS/TRACKS/ARTISTS 三个派生表，
/// 这里用 [Catalog.build] 做同样的事，并提供按 id 查询。
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

  /// 封面资产路径
  final String cover;

  /// 流派
  final String genre;

  /// 时长（秒，按 id 哈希生成，与原型 makeDuration 一致）
  final int duration;

  /// 是否本地曲目
  final bool local;

  /// 是否已下载
  final bool downloaded;

  /// 来源 id（local / fy / aiting / yu7）
  final String sourceId;

  /// 构造曲目
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
}

/// 专辑（派生自 [AlbumSeed]）
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

  /// 封面资产路径
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

/// 艺人（派生自专辑表）
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

/// 曲库 —— 派生表与查询入口。
class Catalog {
  /// 全部专辑（按配表顺序）
  final List<CatalogAlbum> albums;

  /// 全部曲目（按专辑、曲目号顺序）
  final List<CatalogTrack> tracks;

  /// 全部艺人（按名字排序，对应原型 ARTISTS 的 localeCompare 排序）
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

  /// 由配表构建曲库（等价于原型构建 ALBUMS/TRACKS/ARTISTS 的那段代码）。
  factory Catalog.build() {
    final albums = <CatalogAlbum>[];
    final tracks = <CatalogTrack>[];
    final albumById = <String, CatalogAlbum>{};
    final trackById = <String, CatalogTrack>{};

    for (final seed in kAlbumSeeds) {
      final cover = '$kCoverRoot/${seed.id}.jpg';
      final imported = kImportedAlbumIds.contains(seed.id);
      final downloaded = kDownloadedAlbumIds.contains(seed.id);
      final albumTracks = <CatalogTrack>[];
      for (var i = 0; i < seed.tracks.length; i++) {
        final id = '${seed.id}#${i + 1}';
        final track = CatalogTrack(
          id: id,
          no: i + 1,
          title: seed.tracks[i],
          artist: seed.artist,
          albumId: seed.id,
          album: seed.title,
          cover: cover,
          genre: seed.genre,
          duration: makeDuration(id),
          local: imported || kImportedExtraTrackIds.contains(id),
          downloaded: downloaded,
          sourceId: kSourceByTrack[id] ?? kSourceByAlbum[seed.id] ?? 'local',
        );
        albumTracks.add(track);
        tracks.add(track);
        trackById[id] = track;
      }
      final album = CatalogAlbum(
        id: seed.id,
        title: seed.title,
        artist: seed.artist,
        year: seed.year,
        genre: seed.genre,
        cover: cover,
        imported: imported,
        downloaded: downloaded,
        tracks: albumTracks,
      );
      albums.add(album);
      albumById[seed.id] = album;
    }

    // 艺人聚合：同一位艺人的多张专辑合并
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

  /// 批量解析曲目引用（等价原型 resolve()）
  List<CatalogTrack> resolve(List<String> refs) =>
      refs.map((r) => _trackById[r]).whereType<CatalogTrack>().toList();

  /// 列表里显示的行号（等价原型 num = index == null ? t.no : index + 1）
  int displayNo(CatalogTrack track, int index) => index + 1;
}

/// 时长哈希（等价原型 hashStr + makeDuration）
///
/// 原型用 32 位有符号整数溢出模拟 JS 的 `|0`，这里用 Dart 的 int 运算
/// 后按 32 位截断，保证同一 id 得到同一时长（148 + hash*37 % 214）。
int makeDuration(String seed) {
  var h = 0;
  for (var i = 0; i < seed.length; i++) {
    h = (h * 31 + seed.codeUnitAt(i)) & 0x7FFFFFFF;
  }
  return 148 + (h * 37) % 214;
}

/// 秒 → `m:ss`（等价原型 fmt）
String formatDuration(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r < 10 ? '0' : ''}$r';
}

/// 秒 → 中文长描述（等价原型 fmtLong：`2 小时 5 分` / `45 分钟`）
String formatDurationLong(int seconds) {
  var m = (seconds / 60).round();
  final h = m ~/ 60;
  m = m % 60;
  return h > 0 ? '$h 小时 $m 分' : '$m 分钟';
}

/// 字符串哈希（等价原型 hashStr，用于文件夹 id 等）
int hashStr(String s) {
  var h = 0;
  for (var i = 0; i < s.length; i++) {
    h = (h * 31 + s.codeUnitAt(i)) & 0x7FFFFFFF;
  }
  return h;
}
