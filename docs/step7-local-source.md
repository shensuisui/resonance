# Step 7: 本地文件源

| 步骤 | 7 |
| :--- | :--- |
| 包 | `core` |
| 依赖 | Step 1（数据模型）、Step 2（MusicSource 接口） |
| 状态 | 待实现 |

---

## 1. 概述

`LocalScanSource` 实现 `MusicSource` 接口，扫描设备指定目录下的音频文件，提取元数据，构建本地曲库。

## 2. 功能范围

### 2.1 支持的音频格式
- MP3（ID3v1/ID3v2 tag）
- FLAC（Vorbis comment）
- AAC / M4A（MP4 metadata）
- WAV（RIFF metadata）
- OGG Vorbis

### 2.2 核心能力

```dart
class LocalScanSource implements MusicSource {
  @override
  SourceInfo get sourceInfo => SourceInfo(
    id: 'local_scan',
    name: '本地音乐',
    type: SourceType.local,
    enabled: true,
  );

  /// 扫描目录，返回增量更新的歌曲列表
  Future<List<Song>> scanDirectory(String path);

  /// 重新扫描全部（忽略已有缓存）
  Future<List<Song>> rescanAll();

  /// 获取已扫描的歌曲列表
  Future<List<Song>> getScannedSongs();

  /// 搜索已扫描的歌曲
  @override
  Future<SearchResult> search({required String keyword, int page = 1, int pageSize = 20});

  /// 获取歌曲详情（本地文件直接返回）
  @override
  Future<Song> getSongDetail(String id);

  /// 获取播放 URL（本地文件路径）
  @override
  Future<String> getSongUrl(String id);

  /// 获取歌词（从本地文件嵌入的歌词 tag 或同目录 .lrc 文件）
  @override
  Future<Lyrics?> getLyrics(String id);
}
```

### 2.3 元数据提取

使用 `flutter_media_metadata` 或 `ffmpeg` 等库提取音频文件元数据：

| 文件格式 | 元数据位置 |
| :--- | :--- |
| MP3 | ID3v2 tag（标题、艺术家、专辑、封面、时长） |
| FLAC | Vorbis comment 块 |
| M4A | MP4 metadata atoms |
| WAV | RIFF INFO chunk |

### 2.4 增量扫描策略

- 记录已扫描文件的修改时间戳（mtime）
- 扫描时跳过 mtime 未变化的文件
- 检测已删除的文件并从曲库移除
- 新增文件自动加入

## 3. 数据结构

本地扫描结果存储在 SQLite 中（复用 Step 6 的持久化层），`sourceId` 固定为 `'local_scan'`。

## 4. 包结构变更

```
packages/core/lib/src/sources/
├── abstract_music_source.dart  # 已有
├── local_scan_source.dart      # 新增
└── local_scan_helper.dart      # 新增：扫描辅助工具
```

## 5. 测试用例

- Mock 文件系统验证扫描逻辑
- 不同格式文件的元数据提取正确性
- 增量扫描跳过未变更文件
- 搜索本地歌曲匹配
- 歌词文件（.lrc）自动关联