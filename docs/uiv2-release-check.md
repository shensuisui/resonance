# uiv2 发版前集成检查（真实手势 + 逐页截图 + 双份报告）

按 flutter-release-integration-check skill 落地：Flan 驱动、步骤 DSL、双份报告、单一入口。
**发版前手动执行，不接 CI、不进 test/。**

## 一、一条命令

    .\release_check\run_release_check.ps1              # 三断点巡检 + 功能用例（默认 full）
    .\release_check\run_release_check.ps1 -Mode smoke  # 只跑功能用例
    .\release_check\run_release_check.ps1 -Mode sweep  # 只跑三断点巡检

退出码：0 全通过 / 1 有用例失败 / 2 环境或前置错误。

入口做的事：预检 → detached 启动 App（抓 VM service URI）→ 三档 resize 巡检 → 功能用例（阶段间重启）→ 矩阵报告 → 归档日志 → 精确清理。

## 二、目录结构（对齐 skill §3）

    release_check/
      run_release_check.ps1      # 唯一入口
      run_app.ps1                # detached 启动 + URI 提取 + 精确清理
      bin/driver.dart            # MCP 客户端 + 步骤 DSL 解释器
      lib/mcp_client.dart        # 自建 MCP stdio 客户端（initialize / tools/list / tools/call）
      lib/vm_client.dart         # VM service 客户端（调 debug-only 服务扩展）
      lib/report.dart            # results.json → report.md / 矩阵报告
      lib/resize_window.ps1      # Win32 MoveWindow 改真实窗口尺寸
      config/test_plan.yaml      # 功能用例（入库）
      config/sweep_plan.yaml     # 三断点页面巡检用例
      config/test_plan.local.yaml# 账号等局部配置（不入库）

产物：build/release_check/&lt;时间戳&gt;/{report.md, results.json, analysis.md, screenshots/, logs/}，以及各尺寸子目录。

## 三、驱动层：两条通道

| 通道 | 用途 |
| --- | --- |
| MCP（flan_mcp 子进程） | connect / get_interactive_elements / tap / enter_text / scroll_to / take_screenshots / get_logs / get_errors / hot_reload |
| VM service（直连 ws） | ext.flutter.releasecheck.state（状态回读）、ext.flutter.releasecheck.cmd（navigate / dismiss / theme 等） |

两个扩展由 App 侧在 kDebugMode 分支注册（resonance_app/lib/config/release_check_extensions.dart），release 树摇剔除。
flutter_driver 与 RESONANCE_DRIVER 通道已整条移除。

## 四、判定口径

| 状态 | 条件 |
| --- | --- |
| PASS | 所有步骤成功 + 断言满足 + 无新增异常 |
| WARN | 步骤成功，但 get_errors 相对基线有新增 |
| FAIL | 任一步失败（找不到元素 / 断言不成立） |
| TIMEOUT | 等待类步骤超时（默认 12s/步） |
| SKIP | 标了 soft / optional 的步骤失败 |

## 五、三个必须知道的坑（本轮实测）

1. **recover 要先关模态浮层**：上一条用例打开的 sheet 会盖住页面，元素枚举拿不到文本、tap 落到浮层上。App 侧为此暴露 uiV2NavigatorKey + uiV2DismissOverlays()。
2. **锚点必须首屏可见**：Flan 只返回与视口相交的元素。专辑页「同类型专辑」、艺人页「热门歌曲」在首屏之下，用 Midways/Taylor Swift 这类首屏文本。
3. **阶段之间重启 App**：连续三轮 resize 后应用侧状态会劣化（截图与 route 对不上、点击落旧帧），入口在功能阶段前重启一次。

## 六、交付勾选（skill §12）

| # | 必做项 | 状态 |
| --- | --- | --- |
| 1 | release 不含调试代码 | 部分：binding 与扩展在 kDebugMode 常量分支内；**产物符号扫描未做** |
| 2 | 元素发现配置至少 1 个类型现场命中 | 待补证据：get_interactive_elements 结果里确认 UiV2* 类型出现 |
| 3 | 本项目日志能被读到 | 是：get_logs 有内容（运行日志页 25 条记录即来源） |
| 4 | 冒烟跑通并出报告 | 是：见 build/release_check/2026-11-01T15-59-17 |
| 5 | 失败可复现 | 是：本轮通过 3 个真实失败反推并修掉（浮层/锚点/阶段污染） |
| 6 | 清理干净 | 入口末尾精确清理（run_app.ps1 -Cleanup -Force） |
| 7 | 平时不会被误调 | 用例不在 test/，入口唯一，退出码约定生效 |
