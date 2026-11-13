# 迁移脉络（演进历史）

> 记录项目关键演进与「旧→新」对应关系，避免读者误用旧命名/旧能力。来源：evidence/rename、[uiv2-delivery](ui/uiv2-delivery.md) §8、[summary-s1-s3](summaries/summary-s1-s3.md)、[mobile-audioservice](features/mobile-audioservice.md)、[data-import-export](features/data-import-export.md)。
> 状态：现行 ｜ 更新：2026-11-13

## 1. 项目更名
| 旧 | 新 |
|---|---|
| 仓库代号 fm / 壳工程 fm_app | resonance / 回响；壳工程 resonance_app |
| 入口 main.dart + main_v2.dart | 合并为单个 lib/main.dart |
| 驱动开关（旧名） | RESONANCE_DRIVER |

取证：[evidence/rename](evidence/rename/README.md)。

## 2. UI：v1 → uiv2（现役）
- v1「packages/ui」：Material3 + riverpod_generator + Material 路由，**已废弃**（壳工程入口已切 uiv2；包保留在仓库）。
- uiv2「packages/uiv2」：按 OpenDesign 原型还原，自有 hash 路由 / 设计令牌 / SVG 图标，无需代码生成，覆盖手机 / 平板 / 桌面断点。详见 [uiv2-delivery](ui/uiv2-delivery.md)、[prototype-spec](specs/prototype-spec.md)。

## 3. 演示曲库：内置配表 → 独立服务
| 旧 | 新 |
|---|---|
| CatalogMusicSource + 16 专辑配表 + 9 演示歌词 + 静音 WAV（打包进 assets） | demo_source 独立 Dart HTTP 服务；Debug 经普通规则源 demo_catalog 接入，Release 不注册 / 不打包 |

详见 [uiv2-delivery §8](ui/uiv2-delivery.md)、[demo-source](features/demo-source.md)。

## 4. 持久化：内存实现 → SQLite
- 早期持久化为「DAO 接口 + 内存实现」；现已落地 packages/db（sqflite / ffi）。详见 [01-data-schema](01-data-schema.md)、[s1](implementation/s1-sqlite-persistence.md)。

## 5. 后台播放：未实现 → audio_service（Android 一期）
- 早期 S3-2「后台播放/锁屏/通知栏」未实现；2026-11 以 audio_service「侧车」接入（一期仅 Android，Windows SMTC / Linux MPRIS 未做）。详见 [mobile-audioservice](features/mobile-audioservice.md)。

## 6. 数据导入导出：无 → 整包备份 + 单歌单导出
- uiv2 原无导入导出；2026-11 新增整包 JSON 备份/还原与单歌单导出（回响 JSON / M3U8 / CSV），并支持 Android「用回响打开 .json」。详见 [data-import-export](features/data-import-export.md)。
