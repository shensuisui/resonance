# Step 5: 插件下载 + 适配器

| 步骤 | 5 |
| :--- | :--- |
| 包 | `crawler` |
| 依赖 | Step 2（HTTP）、Step 4（RuleBasedMusicSource） |
| 状态 | 待实现 |

---

## 1. 概述

从远程 URL 下载插件文件到本地，解析插件格式，转换为 MusicSource。

## 2. PluginDownloader

```dart
class PluginDownloader {
  /// 从 URL 下载插件文件到本地路径
  Future<String?> downloadPlugin(String url, String savePath);

  /// 从默认源地址下载插件列表
  Future<List<PluginInfo>> fetchDefaultPlugins();
}
```

默认源地址：

| 适配器 | 地址 |
|--------|------|
| 落雪音乐 | `https://fastly.jsdelivr.net/gh/Huibq/keep-alive/render_api.js` |
| MusicFree | `https://fastly.jsdelivr.net/gh/Huibq/keep-alive/Music_Free/myPlugins.json` |

## 3. PluginManager

```dart
class PluginManager {
  /// 从目录加载所有本地插件
  List<MusicSource> loadPluginsFromDirectory(String dirPath);

  /// 加载单个插件文件
  MusicSource? loadPlugin(String filePath);
}
```

## 4. 适配器

### MusicFreeAdapter

MusicFree 插件格式为 JSON，可直接解析为 `RuleConfig`：

```dart
class MusicFreeAdapter {
  static RuleConfig? convertToRuleConfig(Map<String, dynamic> pluginJson);
}
```

### LxMusicAdapter

落雪插件为 JS 格式，当前版本无法执行 JS 表达式，返回提示信息：

```dart
class LxMusicAdapter {
  /// 尝试解析 lx 插件（当前版本仅检查格式，返回 stub 源）
  static MusicSource? tryCreate(String filePath);
}
```

## 5. 包结构

```
packages/crawler/lib/src/
├── http/
├── engine/
├── rule_based_source.dart
└── adapters/
    ├── plugin_downloader.dart
    ├── plugin_manager.dart
    ├── musicfree_adapter.dart
    └── lxmusic_adapter.dart
```

## 6. 测试用例

- PluginDownloader：占位符替换
- MusicFreeAdapter：JSON 转换为 RuleConfig
- PluginManager：从目录加载插件