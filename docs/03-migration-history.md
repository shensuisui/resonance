# 迁移脉络（演进历史）

> 记录关键演进与「旧→新」对应关系（以代码为准，2026-11-13 校准）。来源：evidence/rename、[uiv2-delivery](ui/uiv2-delivery.md)、[summary-s1-s3](summaries/summary-s1-s3.md)、[mobile-audioservice](features/mobile-audioservice.md)、[data-import-export](features/data-import-export.md)。

## 1. 项目更名
| 旧 | 新 |
|---|---|
| 仓库代号 fm / 壳工程 fm_app | resonance / 回响；壳工程 resonance_app |
| 入口 main.dart + main_v2.dart | 合并为单个 lib/main.dart |
| 驱动开关（旧名，已废弃并移除） | RESONANCE_DRIVER（壳工程无读取；`run_app.ps1` 默认不再传） |

取证：[evidence/rename](evidence/rename/README.md)。

## 2. UI：v1 → uiv2（现役）
- v1「packages/ui」：Material3 + riverpod_generator + Material 路由，**已废弃**（壳工程不再依赖；包保留在仓库）。
- uiv2「packages/uiv2」：**go_router**（StatefulShellRoute.indexedStack 保活一级页）+ 设计令牌 + SVG 图标；**15 个页面**；覆盖手机/平板/桌面断点。详见 [uiv2-delivery](ui/uiv2-delivery.md)、[prototype-spec](specs/prototype-spec.md)。
- （业务层仍经 navProvider 门面调用 go_router。）

## 3. 演示曲库：内置配表 → 独立服务
| 旧 | 新 |
|---|---|
| CatalogMusicSource + 16 专辑配表 + 9 演示歌词 + WAV（打包进 assets） | demo_source 独立 Dart HTTP 服务；Debug 经普通规则源 demo_catalog 接入，Release 不注册/不打包 |

详见 [uiv2-delivery](ui/uiv2-delivery.md)、[demo-source](features/demo-source.md)。（catalog.dart 现仅保留展示模型/常量，不含配表数据。）

## 4. 持久化：内存实现 → SQLite（schema v4）
- 早期「DAO 接口 + 内存实现」；现落地 packages/db（sqflite / ffi），7 张表、版本 v4。详见 [01-data-schema](01-data-schema.md)、[s1](implementation/s1-sqlite-persistence.md)。

## 5. 后台播放：未实现 → audio_service 侧车
- 早期 S3-2 未实现；现以 audio_service 侧车接入：**Android 已接线且配置齐全**；**iOS 仅初始化 handler（Info.plist 缺 UIBackgroundModes，暂不可用）**。详见 [mobile-audioservice](features/mobile-audioservice.md)。

## 6. 数据导入导出：无 → 整包备份 + 单歌单导出
- uiv2 原无导入导出；现落地整包 JSON 备份/还原 + 单歌单导出，并支持 Android「用回响打开 .json」。详见 [data-import-export](features/data-import-export.md)。

## 7. 播放进度：新增
- 新增 play_progress 表（一个队列一行），支持跨会话续播；见 [01-data-schema](01-data-schema.md)。
