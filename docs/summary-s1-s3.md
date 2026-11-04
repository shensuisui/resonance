# S1-S3 总结：数据底座 + UI + 本地扫描

| 完成日期 | 2026-08-25 |
|:---|:---|
| 范围 | S1 + S2 + S3-1 |
| 涉及包 | core, db (新), ui, resonance_app |

---

## S1：SQLite 持久化层 ✅

| 步骤 | 内容 | 状态 |
|:---|:---|:---:|
| S1-1 | 创建 packages/db Flutter 包 + SQLite schema | ✅ |
| S1-2 | SQLite DAO 实现 (Song/Playlist/RecentPlays/Favorites/Settings) | ✅ |
| S1-3 | RecentPlaysService (自动加入/去重/移顶/500上限) | ✅ |
| S1-4 | DownloadManager (下载/缓存/队列管理/状态流) | ✅ |
| S1-5 | 测试 (21/21 通过，内存 SQLite FFI) | ✅ |
| S1-6 | resonance_app 接入 SqfliteDatabaseProvider | ✅ |

**关键设计：**
- 跨平台：sqflite (移动) + sqflite_common_ffi (桌面)
- 同步预留：songs 表 updated_at、settings 表 updated_at
- SettingsDao：key-value 存储，支持多设备同步预留
- Cookie 隔离：每个 HttpClient 实例独立 cookie interceptor

## S2：UI 与用户体验 ✅

| 步骤 | 内容 | 状态 |
|:---|:---|:---:|
| S2-1 | Riverpod + 主题系统 (AppSpacing/AppRadius/AppTheme) | ✅ |
| S2-2 | 搜索页 + 全屏播放页 + 迷你播放器 | ✅ |
| S2-3 | 歌单管理 (CRUD) | ✅ |
| S2-4 | 源管理页 + 设置页 + 最近播放/最喜欢 | ✅ |

**主题系统约束（用户要求）：**
- 可切换亮/暗主题，模式持久化到 settings 表
- 禁止魔法值：间距用 AppSpacing.sX，圆角用 AppRadius.sX
- 颜色一律用 Theme.of(context).colorScheme

**页面清单（7 个）：**
- AppShell（底部导航 5 Tab + 迷你播放器）
- SearchPage（跨源聚合搜索）
- PlayerPage（全屏播放：封面/进度/控制/播放模式）
- RecentPlaysPage（最近播放列表）
- PlaylistListPage（歌单 CRUD）
- SourceManagementPage（源列表 + 开关）
- SettingsPage（主题切换 + 扫描目录 + 关于）

## S3-1：本地扫描增强 ✅

| 步骤 | 内容 | 状态 |
|:---|:---|:---:|
| S3-1 | 文件扫描 + 元数据解析 + 持久化 + 增量更新 | ✅ |

**实现：**
- 递归扫描目录，支持 7 种音频格式 (.mp3/.flac/.aac/.wav/.m4a/.ogg/.opus)
- 文件名解析："Artist - Title" 格式 → 退化用父目录名做歌手
- SongDao 持久化：扫描结果存入 SQLite (sourceId='local_scan')
- 增量更新：已扫描文件路径跳过
- SettingsPage 新增扫描目录配置 + 扫描按钮 + 状态显示

## S3-2：后台播放/锁屏/通知栏（可选，未实现）

需要引入 `audio_service` 或 `just_audio_background` 包，涉及平台特定配置。
标记为低优先级，后续按需实现。

---

## 测试统计

| 包 | 测试数 | 结果 |
|:---|:---|:---|
| core | 27 | ✅ |
| expr | 50 | ✅ |
| crawler | 57 (2 skipped) | ✅ |
| db | 21 | ✅ |
| **合计** | **155** | **✅ 全通过** |

## 提交历史

| 提交 | 内容 |
|:---|:---|
| `eecc0ec` | S3-1 本地扫描增强 |
| `00bb046` | S2 UI 与用户体验 |
| `4812060` | S1 SQLite 持久化层 |
| `a5f7af0` | 6uq.cn 规则源 + CSRF preflight |
| `1f78a9b` | 前置流程引擎 + CSS @value 修复 |
| `c1370b2` | 枫叶音乐源 + polyfill 修复 |
| `8e5ba68` | 二期在线源与规则引擎 |
| `7e90d0e` | 一期基础设施 |
| `63aad1a` | 项目初始化 |

## 当前 3 层架构完整度

```
MusicSource 接口
├── 本地源组
│   ├── LocalScanSource    ✅ S3-1 增强（文件扫描 + 持久化）
│   ├── LocalCustomSource  ✅ 二期
│   └── FavoriteSource     ✅ 二期
├── 规则引擎源
│   └── RuleBasedMusicSource  ✅ 二期 + preflight + 分页
└── 插件适配器组
    ├── MusicFreeAdapter    ✅ 二期
    └── LxMusicAdapter      ✅ JS 运行时（flutter_inappwebview）
```

## 剩余工作

| 优先级 | 内容 | 备注 |
|:---|:---|:---|
| 低 | S3-2 后台播放/锁屏/通知栏 | 需 audio_service，平台特定 |
| 中 | 歌单导入/导出 (M3U/PLS/JSON) | PRD 3.4 |
| 中 | 歌单详情页（曲目列表 + 排序 + 批量操作） | PRD 3.4 |
| 低 | 本地歌词解析（.lrc 同名文件） | LocalScanSource.getLyrics |
| 低 | 音频元数据标签读取（ID3/FLAC tag） | 替代文件名解析 |
| 低 | Web 平台 SQLite 支持 | sqflite_common_ffi_web (实验性) |
