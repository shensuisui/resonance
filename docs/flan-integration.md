# Flan 接入（agent 驱动运行中 App）

按 flutter-agent-drive-app skill 落地。Flan = flan_flutter（App 侧调试层）+ flan_mcp（宿主拉起的 MCP server）。

## 一、一句话现状

- **App 侧已生效**：debug 构建里注册了 23 个 ext.flutter.flan.* 服务扩展（VM service 实测列举）。
- **server 侧已可用**：dart run flan_mcp 用 mcp.yml 的原命令拉起，tools/list 返回 **22 个工具**。
- **宿主已激活**：写入 .dsh/mcp.yml 后，宿主诊断文件出现 scan → attempt(rawName: flan) → active(p96aa87_flan)。
- **工具面已可用**：修正 cwd 后重启会话，22 个 mcp__pa20f42_flan__* 工具全部注入（connect / get_interactive_elements / tap / enter_text / scroll_to / take_screenshots / get_logs / get_errors / hot_reload / 标注与圈选回传）。

## 二、改动清单

| 文件 | 改了什么 | 是否入库 |
| --- | --- | --- |
| resonance_app/pubspec.yaml | flan_flutter ^0.6.1 → dependencies；flan_mcp ^0.6.1 → dev_dependencies；补 logging ^1.3.0 | 是 |
| resonance_app/lib/config/agent_debug_config.dart | 新增：元素发现三张表（可交互类型 / 停遍历 / 取文本）+ maxScreenshotSize: null | 是 |
| resonance_app/lib/main.dart | main() 首段改成 kDebugMode ? FlanBinding.ensureInitialized(cfg) : WidgetsFlutterBinding.ensureInitialized()；enableFlutterDriverExtension 移到 binding 之后；Logger.root.level = Level.ALL | 是 |
| resonance_app/lib/main.dart（日志桥） | SourceLogBus.consolePrinter 是项目日志唯一扇出点，在这里转发到 package:logging（带级别映射） | 是 |
| .dsh/mcp.yml | 托管块内新增 panel-mcp-flan；因本机 fvm 不可用，command 用 dart 绝对路径 | 按团队约定（该文件本仓库已入库） |

**没动业务代码**：没有为 Flan 改任何页面/组件逻辑，只加了 1 个配置文件与入口接线。

## 三、为什么 command 不是 fvm

skill 模板用 fvm dart run flan_mcp。本机 fvm 报 Git is not installed 不可用（这也是原有 dart-mcp-server 条目在本会话中途失效的原因）。最终生效的配置（两处都与第一版不同）：

    command: G:/works/shelli/fm/.fvm/flutter_sdk/bin/dart.bat
    args: [run, flan_mcp]
    cwd: ./resonance_app/

**cwd 是真正的关键点**：dart run <包名> 只用**当前目录**的 .dart_tool/package_config.json 解析包名。
本仓库是 monorepo（Flutter 工程在 resonance_app/），第一版写 cwd: .（仓库根）时根下没有 package_config，
server 起来就退出——宿主诊断里有 attempt、没有 active，零工具，错误只在 server 的 stderr 里。
改成 cwd: ./resonance_app/ 后立刻 attempt → active。该要点已写进 skill（flutter-agent-drive-app 7.1 与 pitfalls #2）。

## 四、release 安全性

- binding 分支是 if (kDebugMode) 常量分支，release 由树摇剔除调试层。
- enableFlutterDriverExtension 仍由 --dart-define=RESONANCE_DRIVER 单独控制，生产不传即无。
- **未做**：release 产物符号扫描，列入遗留。

## 五、遗留登记

| 遗留项 | 类型 | 影响 | 建议处理时机 |
| --- | --- | --- | --- |
| 本会话拿不到 flan 工具面 | 会话级 | 需要新会话才能驱动 | 下一步就做 |
| release 产物未做符号扫描 | 未验证 | 无法证明调试层被树摇 | 正式发版前 |
| release_check/bin/driver.mjs 仍是自写 flutter_driver 客户端 | 待迁移 | 与 skill 指定实现不一致 | 新会话里用 Flan 工具重写步骤 DSL |
| 元素发现配置未现场命中验证 | 未验证 | 三张表可能未生效 | 新会话跑 get_interactive_elements 确认 |
| 圈选回传（能力 7）未实测 | 未验证 | 未知 | 需真人在 App 内操作 |
