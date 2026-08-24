# Step 8: SourceManager 基础框架

| 步骤 | 8 |
| :--- | :--- |
| 包 | `core` |
| 依赖 | Step 2（MusicSource 接口） |
| 状态 | 待实现 |

---

## 1. 概述

`SourceManager` 管理所有音乐源的注册、启用/禁用、聚合搜索调度。作为上层（UI）与各源之间的桥梁。

## 2. 核心设计

```dart
class SourceManager {
  final Map<String, MusicSource> _sources = {};
  final Map<String, bool> _enabledStatus = {};

  /// 注册源
  void registerSource(MusicSource source);

  /// 取消注册源
  void unregisterSource(String sourceId);

  /// 启用/禁用源
  void setSourceEnabled(String sourceId, bool enabled);

  /// 获取源是否启用
  bool isSourceEnabled(String sourceId);

  /// 获取所有已注册源
  List<MusicSource> getAllSources();

  /// 获取所有已启用源
  List<MusicSource> getEnabledSources();

  /// 获取指定源
  MusicSource? getSource(String sourceId);

  /// 聚合搜索：并行搜索所有已启用源
  Future<List<SearchResult>> searchAll({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  });

  /// 获取指定源的歌曲详情
  Future<Song> getSongDetail(String sourceId, String songId);

  /// 获取指定源的歌曲播放 URL
  Future<String> getSongUrl(String sourceId, String songId);

  /// 获取指定源的歌词
  Future<Lyrics?> getLyrics(String sourceId, String songId);

  /// 初始化所有已注册源
  Future<void> initAll();

  /// 释放所有源
  Future<void> disposeAll();
}
```

## 3. 聚合搜索设计

```dart
/// 并行搜索所有已启用源
Future<List<SearchResult>> searchAll({
  required String keyword,
  int page = 1,
  int pageSize = 20,
}) async {
  final sources = getEnabledSources();
  final results = await Future.wait(
    sources.map((s) => s.search(
      keyword: keyword,
      page: page,
      pageSize: pageSize,
    )),
    eagerError: false, // 单个源失败不影响其他源
  );
  return results;
}
```

- 使用 `Future.wait` 并行发起搜索
- 单个源失败不影响其他源的结果
- 结果按源分组返回，由 UI 层决定如何合并展示

## 4. 包结构变更

```
packages/core/lib/src/services/
└── source_manager.dart
```

## 5. 测试用例

- 注册/取消注册源
- 启用/禁用源
- 聚合搜索并行调用所有已启用源
- 单个源搜索失败不影响其他源
- 获取各源接口的正确路由