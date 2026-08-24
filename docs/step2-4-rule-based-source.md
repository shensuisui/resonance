# Step 4: RuleBasedMusicSource

| 步骤 | 4 |
| :--- | :--- |
| 包 | `crawler` |
| 依赖 | Step 2（HTTP）、Step 3（规则执行引擎） |
| 状态 | 待实现 |

---

## 1. 概述

`RuleBasedMusicSource` 实现 `MusicSource` 接口，使用 `RuleExecutor` 驱动规则配置，将一个 JSON 规则文件转换为一个完整的音乐源。

## 2. 接口实现

```dart
class RuleBasedMusicSource implements MusicSource {
  final RuleConfig _ruleConfig;
  final RuleExecutor _executor;

  RuleBasedMusicSource(this._ruleConfig)
      : _executor = RuleExecutor(_ruleConfig);

  @override
  SourceInfo get sourceInfo => SourceInfo(
    id: _ruleConfig.source.id,
    name: _ruleConfig.source.name,
    iconUrl: _ruleConfig.source.icon,
    type: SourceType.rule,
    enabled: true,
  );

  @override
  Future<SearchResult> search({required String keyword, int page = 1, int pageSize = 20}) {
    return _executor.executeSearch(keyword, page: page);
  }

  @override
  Future<Song> getSongDetail(String id) async {
    final fields = await _executor.executeSongDetail(id);
    // 从 fields 构造 Song
  }

  @override
  Future<String> getSongUrl(String id) async {
    final fields = await _executor.executeSongDetail(id);
    return fields['playUrl']?.toString() ?? '';
  }

  @override
  Future<Lyrics?> getLyrics(String id) async {
    final lyric = await _executor.executeLyric(id);
    // 解析 LRC 或返回纯文本
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}
}
```

## 3. 包结构

```
packages/crawler/lib/src/
├── http/
├── engine/
└── rule_based_source.dart       # 新增
```

## 4. 测试用例

- RuleBasedSource 正确实现 MusicSource 接口
- search 委托给 RuleExecutor.executeSearch
- getSongDetail 委托给 RuleExecutor.executeSongDetail