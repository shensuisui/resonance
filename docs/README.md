# 文档地图（docs/ README）

> resonance / 回响 项目文档的**唯一阅读入口**。新增文档请归入对应分区并在下方登记；过期文档移入 archive/ 并加「历史归档」横幅。
> 更新：2026-11-19

## 先读这 4 篇（总览 / 真相源）
| 文档 | 说明 | 状态 |
|---|---|---|
| [00-architecture](00-architecture.md) | 现行架构总览（包结构 / 运行流 / 源清单） | 现行 |
| [01-data-schema](01-data-schema.md) | 数据库 schema 现行版 | 现行 |
| [02-glossary](02-glossary.md) | 术语 / 属性表 | 现行 |
| [03-migration-history](03-migration-history.md) | 迁移脉络（旧→新对应） | 现行 |

## 产品
| 文档 | 说明 | 状态 |
|---|---|---|
| [product/prd.md](product/prd.md) | 产品需求文档（目标 / 功能 / 规则格式 / 分期） | 现行(需修订) |

## 规格
| 文档 | 说明 | 状态 |
|---|---|---|
| [specs/prototype-spec.md](specs/prototype-spec.md) | HTML 原型逆向规格（UI 行为基线；数据层已废） | 现行 |
| [specs/source-gdstudio.md](specs/source-gdstudio.md) | GD 音乐台规则源 gdstudio_netease 规格与实测 | 现行 |

## UI
| 文档 | 说明 | 状态 |
|---|---|---|
| [ui/uiv2-delivery.md](ui/uiv2-delivery.md) | uiv2 交付说明（数据接线 / 页面 / 验证 / 测试） | 现行(需修订) |
| [ui/uiv2-release-check.md](ui/uiv2-release-check.md) | 发版前真实手势集成检查工具链 | 现行(交付未闭合) |

## 特性 / 决策
| 文档 | 说明 | 状态 |
|---|---|---|
| [features/mobile-audioservice.md](features/mobile-audioservice.md) | audio_service 后台播放接入（Android 一期） | 现行(一期部分完成) |
| [features/data-import-export.md](features/data-import-export.md) | 数据导入导出（整包备份 + 单歌单导出） | 现行(待真机) |
| [features/offline-cache.md](features/offline-cache.md) | 播放 / 歌词缓存决策 | 现行(已实现，端到端验收记录待补) |
| [features/download.md](features/download.md) | 下载功能重做（A 已下载）：P0–P5 完成，Android 真机集成测试通过 | 现行 |
| [features/demo-source.md](features/demo-source.md) | 演示曲库独立 Dart HTTP 服务 | 现行 |
| [features/build.md](features/build.md) | GitHub Actions 自动打包 | 现行 |
| [features/flan-integration.md](features/flan-integration.md) | Flan（agent 驱动运行 App）接入 | 现行(5 项遗留) |
| [features/webdav-sync.md](features/webdav-sync.md) | WebDAV 云同步设计（快照链留7份/多设备合并/墓碑/表结构 v5；变更感知/基线墓碑；分三期） | 设计稿(未实施) |

## 实现方案
| 文档 | 说明 | 状态 |
|---|---|---|
| [implementation/s1-sqlite-persistence.md](implementation/s1-sqlite-persistence.md) | S1 SQLite 持久化层方案 | 现行(已完成) |
| [implementation/s2-ui-and-ux.md](implementation/s2-ui-and-ux.md) | S2 UI 与用户体验方案 | 现行(已完成) |

## 阶段总结
| 文档 | 说明 | 状态 |
|---|---|---|
| [summaries/summary-s1-s3.md](summaries/summary-s1-s3.md) | S1 / S2 / S3-1 完成总结（权威） | 总结 |

## 证据（只读，GitHub 任务执行结果）
> evidence/ 为既存取证产物，**只读禁改**（唯一例外：audio-service README 的配套路径引用已随本次重组更新）。

| 文件夹 | 内容 |
|---|---|
| [evidence/rename/](evidence/rename/README.md) | 项目更名 + uiv2 默认入口前后对比 |
| [evidence/android-ux-fixes/](evidence/android-ux-fixes/README.md) | Issue#5 安卓五缺陷 before/after |
| [evidence/audio-service-and-import-export/](evidence/audio-service-and-import-export/README.md) | AudioService 集成 + 导入导出取证 |
| [evidence/issue-8/](evidence/issue-8/) | Issue#8 播放状态 before/after（纯图片） |
| [evidence/playerbar-safearea/](evidence/playerbar-safearea/) | 播放条安全区 before/after（纯图片） |

## 归档（历史，仅供追溯）
| 分组 | 文档 |
|---|---|
| 早期 step 计划（14） | [step1](archive/steps/step1-data-models.md)、[step2-music-source](archive/steps/step2-music-source.md)、[step2-1](archive/steps/step2-1-local-sources.md)、[step2-2](archive/steps/step2-2-crawler-http.md)、[step2-3](archive/steps/step2-3-rule-executor.md)、[step2-4](archive/steps/step2-4-rule-based-source.md)、[step2-5](archive/steps/step2-5-plugin-adapters.md)、[step2-6](archive/steps/step2-6-search-flow.md)、[step3](archive/steps/step3-expression-parser.md)、[step4](archive/steps/step4-player-interface.md)、[step5](archive/steps/step5-player-implementation.md)、[step6](archive/steps/step6-persistence.md)、[step7](archive/steps/step7-local-source.md)、[step8](archive/steps/step8-source-manager.md) |
| 早期阶段总结（2） | [summary-phase1](archive/summaries/summary-phase1.md)、[summary-phase2](archive/summaries/summary-phase2.md) |
| v1 UI 方案（1） | [ui-improvement-plan](archive/ui-improvement-plan.md) |

## 状态图例
- **现行**：当前依据，可直接参考。
- **现行(需修订 / 部分完成 / 待真机 / 遗留)**：现行但含已知待办或过时点。
- **总结**：阶段总结（权威口径）。
- **证据**：截图 / 取证说明（只读）。
- **历史归档**：已被取代，仅供追溯（顶部有横幅）。

## 维护约定
- 新增文档归入 product / specs / ui / features / implementation / summaries 对应区，并在此登记。
- 过期文档移入 archive/ 并加「历史归档」横幅。
- evidence/ 保持只读；确需新取证时新建子目录，不改旧目录。