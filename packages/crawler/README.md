# crawler — 远程源实现（规则引擎）

规则驱动：一份 JSON 规则即一个音乐源。

## 职责
- 规则引擎：RuleConfig / RuleLoader / RuleExecutor / ResponseHandler。
- RuleBasedMusicSource：把规则包装成 MusicSource。
- HttpClient（dio）：GET / POST、URL 占位符替换、响应模型。
- 插件适配：MusicFree（.mf，JSON 规则）、落雪（.lx，JS 运行时，flutter_inappwebview）。

## 依赖
core、expr、dio、flutter_inappwebview（beta 版，见 pubspec 注释）。

## 测试
在 packages/crawler 下运行 flutter test。
