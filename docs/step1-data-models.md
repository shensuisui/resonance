# Step 1: 数据模型定义

| 步骤 | 1 |
| :--- | :--- |
| 包 | `core` |
| 状态 | 待实现 |

---

## 1. 概述

定义 `core` 包中的核心数据模型，作为整个应用的数据基础。所有模型为不可变数据类（`immutable`），使用 `==` / `hashCode` 和 `copyWith` 模式。

## 2. 模型列表

### 2.1 Song（歌曲）

```dart
class Song {
  final String id;           // 源内歌曲 ID
  final String sourceId;     // 来源标识，(id, sourceId) 组成全局唯一键
  final String title;        // 歌名
  final String artist;       // 艺术家
  final String? album;       // 专辑名
  final String? coverUrl;    // 封面 URL
  final int? duration;       // 时长（秒）
  final String? playUrl;     // 播放地址（可能有时效）
  final String? lyricUrl;    // 歌词文件地址
  final String? lyric;       // 歌词文本（若已获取）
  final String? localPath;   // 本地缓存路径
  final Map<String, dynamic> extra; // 源自定义扩展字段
}
```

- `globalKey` getter: `"$sourceId:$id"` 全局唯一键
- `==` / `hashCode` 基于 `(id, sourceId)` 比较

### 2.2 Album（专辑）

```dart
class Album {
  final String id;           // 源内专辑 ID
  final String sourceId;     // 来源标识
  final String title;        // 专辑名
  final String artist;       // 艺术家
  final String? coverUrl;    // 封面 URL
  final List<Song> songs;    // 歌曲列表（可能为空或部分加载）
  final int? songCount;      // 专辑总曲数
  final Map<String, dynamic> extra;
}
```

### 2.3 Artist（艺术家）

```dart
class Artist {
  final String id;
  final String sourceId;
  final String name;
  final String? avatar;
  final String? description;
  final Map<String, dynamic> extra;
}
```

### 2.4 Lyrics（歌词）

```dart
class Lyrics {
  final String songId;
  final String sourceId;
  final List<LyricLine> lines; // 时间戳 + 文本行
  final bool isLrc;            // 是否为 LRC 格式
}

class LyricLine {
  final Duration time;         // 歌词时间戳
  final String text;           // 歌词文本
}
```

### 2.5 Playlist（歌单）

```dart
class Playlist {
  final String id;             // UUID（本地歌单）或源内 ID（导入歌单）
  final String name;           // 歌单名称
  final List<String> songKeys; // 歌曲全局键列表 ["sourceId1:id1", "sourceId2:id2"]
  final String? sourceId;      // 若为导入源歌单，记录来源 ID
  final String? sourcePlaylistId; // 源歌单原始 ID
  final String? coverUrl;
  final DateTime createdTime;
  final DateTime modifiedTime;
}
```

### 2.6 SearchResult（搜索结果）

```dart
class SearchResult {
  final List<Song> songs;
  final bool hasMore;           // 是否有更多页
  final int? nextPage;          // 下一页页码（page 分页）
  final int? nextOffset;        // 下一页偏移（offset 分页）
  final String? nextCursor;     // 下一页游标（cursor 分页）
  final String sourceId;        // 来源标识
}
```

### 2.7 PlayMode（播放模式枚举）

```dart
enum PlayMode {
  listLoop,     // 列表循环
  singleLoop,   // 单曲循环
  shuffle,      // 随机播放
  sequential,   // 顺序播放（播完停止）
}
```

### 2.8 PlayerState（播放器状态）

```dart
enum PlayerState {
  idle,         // 空闲
  loading,      // 加载中
  playing,      // 播放中
  paused,       // 已暂停
  stopped,      // 已停止
  error,        // 播放出错
}
```

### 2.9 SourceInfo（源信息）

```dart
class SourceInfo {
  final String id;          // 唯一标识，如 "local_scan", "netease"
  final String name;        // 显示名称，如 "本地音乐", "网易云音乐"
  final String? iconUrl;    // 图标 URL
  final SourceType type;    // 源类型
  final bool enabled;       // 是否启用
}

enum SourceType {
  local,        // 本地源（扫描/自建/最喜欢）
  rule,         // 规则引擎源
  plugin,       // 插件适配器源
}
```

## 3. 包结构变更

```
packages/core/lib/src/
├── models/
│   ├── song.dart
│   ├── album.dart
│   ├── artist.dart
│   ├── lyrics.dart
│   ├── playlist.dart
│   ├── search_result.dart
│   └── source_info.dart
├── enums/
│   ├── play_mode.dart
│   ├── player_state.dart
│   └── source_type.dart
└── core_base.dart        # 已有，保留
```

## 4. 测试用例

- Song 的 `==` / `hashCode` 正确性
- Song.globalKey 格式正确
- 各个模型的 `copyWith` 不修改原对象
- 各个模型的不可变性