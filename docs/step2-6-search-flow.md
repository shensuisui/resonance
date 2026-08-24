# Step 6: 初始规则文件 + 搜索流程打通

| 步骤 | 6 |
| :--- | :--- |
| 包 | `fm_app` + `crawler` |
| 依赖 | Step 1–5 |
| 状态 | 待实现 |

---

## 1. 概述

配置初始规则文件，集成 SourceManager + RuleBasedMusicSource，实现完整搜索链路。

## 2. 初始规则文件

`fm_app/assets/rules/example.json` 包含一个示例音乐源规则配置，支持：
- 搜索（分页）
- 歌曲详情
- 歌词获取
- 歌单导入

## 3. 搜索流程集成

在 `fm_app` 启动时：

```dart
void main() async {
  // 1. 初始化表达式引擎
  initExprEngine();

  // 2. 创建 SourceManager
  final manager = SourceManager();

  // 3. 注册本地源
  manager.registerSource(LocalScanSource());
  manager.registerSource(LocalCustomSource(songDao));
  manager.registerSource(FavoriteSource(favoritesDao, manager));

  // 4. 从 assets/rules/ 加载规则源
  final ruleConfigs = RuleLoader.loadAllFromDirectory('assets/rules/');
  for (final config in ruleConfigs) {
    manager.registerSource(RuleBasedMusicSource(config));
  }

  // 5. 初始化所有源
  await manager.initAll();

  // 6. 搜索
  final results = await manager.searchAll(keyword: '周杰伦');
}
```

## 4. 依赖关系更新

```
fm_app → ui → core + player + crawler
```

`fm_app/pubspec.yaml` 已添加 `crawler` 依赖。