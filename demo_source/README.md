# resonance demo source

本地调试用的演示曲库 HTTP 服务。完整设计与接口约定见 [docs/demo-source.md](../docs/demo-source.md)。

## 启动

```powershell
cd demo_source
..\.fvm\flutter_sdk\bin\dart.bat pub get
..\.fvm\flutter_sdk\bin\dart.bat run bin/server.dart
```

默认监听 `0.0.0.0:8787`。App 在 Debug 模式启动前先运行本服务，否则演示源会被跳过（不影响其它源）。

## 延迟调试

所有数据接口支持 `d` 参数（秒，可小数）：

```text
http://127.0.0.1:8787/search?keyword=blue&d=10
```

也可把延迟写进 `data/rule.json`，让 App 内每次搜索都走慢请求。
