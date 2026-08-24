# Step 2: MusicSource 抽象接口

| 步骤 | 1 |
| :--- | :--- |
| 包 | `core` |
| 依赖 | Step 1（数据模型） |
| 状态 | 待实现 |

---

## 1. 概述

定义 `MusicSource` 抽象接口，作为所有音乐源的统一契约。所有源（本地、规则引擎、插件适配器）必须实现此接口。

## 2. 接口定义

```dart
abstract class MusicSource {
  /// 源信息
  SourceInfo get sourceInfo;

  /// 搜索歌曲
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  });

  /// 获取歌曲详情（播放地址、歌词等）
  Future<Song> getSongDetail(String id);

  /// 获取歌曲播放 URL
  Future<String> getSongUrl(String id);

  /// 获取歌词
  Future<Lyrics?> getLyrics(String id);

  /// 获取专辑详情
  Future<Album?> getAlbum(String id);

  /// 获取艺术家详情
  Future<Artist?> getArtist(String id);

  /// 获取歌单
  Future<Playlist?> getPlaylist(String id);

  /// 初始化源（如加载配置、建立连接）
  Future<void> init();

  /// 释放源资源
  Future<void> dispose();
}
```

## 3. 默认实现

不提供默认实现，各源自行实现全部方法。

## 4. 包结构变更

```
packages/core/lib/src/sources/
└── abstract_music_source.dart
```