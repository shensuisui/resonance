# Step 1: LocalCustomSource + FavoriteSource

| 步骤 | 1 |
| :--- | :--- |
| 包 | `core` |
| 依赖 | Step 1（数据模型）、Step 2（MusicSource 接口）、Step 6（DAO） |
| 状态 | 待实现 |

---

## 1. LocalCustomSource（自建源）

用户手动添加单首歌曲（本地文件路径或网络 URL），自定义标题、艺术家等信息。

### 接口

```dart
class LocalCustomSource implements MusicSource {
  /// 添加自定义歌曲
  Future<void> addCustomSong(Song song);

  /// 删除自定义歌曲
  Future<void> removeCustomSong(String id);

  /// 获取所有自定义歌曲
  Future<List<Song>> getAllCustomSongs();

  /// 编辑歌曲元信息
  Future<void> updateCustomSong(Song song);
}
```

- `sourceId` 固定为 `'local_custom'`
- 数据通过 SongDao 持久化
- 搜索在本地已存储的歌曲中匹配

### 数据持久化

复用 `SongDao`，`sourceId` 固定为 `'local_custom'`。

---

## 2. FavoriteSource（最喜欢源）

跨源收藏系统。用户在任何源中标记"喜欢"的歌曲，自动汇集到该源。

### 接口

```dart
class FavoriteSource implements MusicSource {
  /// 添加喜欢
  Future<void> addFavorite(String songKey, String sourceId, String songId);

  /// 取消喜欢
  Future<void> removeFavorite(String songKey);

  /// 是否已喜欢
  Future<bool> isFavorite(String songKey);

  /// 获取最喜欢的歌曲列表（通过 SourceManager 回源获取详情）
  Future<List<Song>> getFavoriteSongs();

  /// 需要 SourceManager 引用以回源获取 Song 详情
  final SourceManager sourceManager;
}
```

- `sourceId` 固定为 `'favorite'`
- 只存储 `song_key`（全局唯一键），不复制歌曲文件
- 搜索时匹配已收藏的 song_key
- 获取详情时通过 `SourceManager` 回源到原始 `sourceId` 获取

### 数据持久化

复用 `FavoritesDao`。

---

## 3. 包结构变更

```
packages/core/lib/src/sources/
├── abstract_music_source.dart  # 已有
├── local_scan_source.dart      # 已有
├── local_custom_source.dart    # 新增
└── favorite_source.dart        # 新增
```

## 4. 测试用例

- LocalCustomSource：添加/删除/编辑/搜索自定义歌曲
- FavoriteSource：添加/取消/查询喜欢状态
- FavoriteSource：搜索匹配已收藏的歌曲
- FavoriteSource：回源获取 Song 详情（通过 mock SourceManager）