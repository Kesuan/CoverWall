# SPEC: 发现专辑封面墙（随机混池）

- 状态：已实现
- 日期：2026-09-11（随机混池修订）
- 关联文件：`CoverWall/ITunesChartsService.swift`（新增）、`CoverWall/SearchViewModel.swift`、`CoverWall/ContentView.swift`、`CoverWall/en.lproj/Localizable.strings`、`CoverWall/zh-Hans.lproj/Localizable.strings`

## 背景与目标

当前 App 启动后搜索页只有空状态，用户必须先输入关键词才能看到封面。目标是：**打开 App 即展示一批专辑封面，点任意一张立刻进入四方案壁纸生成**，把"第一次预览"的路径缩短到一次点击。

初版仅拉当日榜单，刷新后批次几乎不变。修订目标：**每次刷新重新混一批随机专辑封面**。

决策记录（与用户确认）：

| 议题 | 结论 |
|------|------|
| 内容类型 | 仅专辑（方形封面、无单曲杂讯） |
| 国家/地区 | 固定 `US`，与现有搜索服务硬编码保持一致 |
| macOS 位置 | 左侧边栏（iOS 为搜索页 idle 态） |
| 样式与数量 | 自适应封面网格，25 张 |
| 刷新策略 | 当日榜单 100 + 随机流派榜单 100 混池洗牌，每次刷新换流派 |
| 网格标题 | "发现专辑"（en `Discover` / zh `发现专辑`） |

## 数据源

采用两个官方源混池（免鉴权）：

**1. Marketing Tools RSS（当日热门榜）**

```
https://rss.marketingtools.apple.com/api/v2/{country}/music/most-played/{limit}/albums.json
```

- 返回 `{"feed": {"results": [...]}}`，字段含 `artistName` / `id` / `name` / `releaseDate` / `artworkUrl100`
- `artworkUrl100` 形如 `.../100x100bb.jpg`，与 `ITunesResult.artworkURL(size:)` / `highResArtworkURL()` 兼容
- limit 支持 1–100（`200` 返回 500）
- 响应头 `cache-control: max-age=0, private, must-revalidate` + ETag，复用 URLSession 默认缓存，不做自定义缓存层

**2. 旧版 iTunes RSS（流派热门榜，用于扩充随机池）**

```
https://itunes.apple.com/us/rss/topalbums/limit=100/genre={genreId}/json
```

- 旧 `im:` JSON 格式：`feed.entry`（单条时是对象、多条时是数组，需两种都解码）
- 每流派实测 15–100 条，内容混合当季新专辑与经典老专辑
- 图片 URL 形如 `.../170x170bb.png`；规范化成 `.../100x100bb.jpg` 后，`.jpg` 尺寸替换（600≈106KB、3000≈2.4MB）全部可用
- 流派池取实测非空且面向大众的 17 个：`2, 5, 6, 7, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 21, 24, 1289`（Blues / Classical / Country / Electronic / Singer-Songwriter / Jazz / Latin / New Age / Pop / R&B-Soul / Soundtrack / Dance / Hip-Hop-Rap / Alternative / Rock / Reggae / Folk）
- 个别流派偶发空结果，单源失败可容忍（见下）

**混池算法**：两源并行请求 → 合并 → 按 `collectionId` 去重 → `shuffled()` → 取 25。单源失败用另一源，双失败才走失败态。每次刷新随机换流派（排除上一次），配合洗牌使批次明显不同。

被否决的方案：

- iTunes Search API 随机关键词：结果质量参差（冷门单曲、字面命中），且官方限速约 20 次/分钟
- Apple Music API `/v1/catalog/{storefront}/charts`：需要开发者 JWT 私钥，不适合放进客户端
- 国家轮换：`gb` / `ca` / `au` 的 Marketing Tools feed 不稳定，实测不可用

## 架构

```
FeaturedAlbumsGrid ──► SearchViewModel ──► ITunesChartsService ──┬─► Marketing Tools RSS（当日榜）
        │  (点击)                                                └─► 旧版 iTunes RSS（随机流派榜）
        ▼
   selection: ITunesResult ──► StudioDetail.prepare(...)   ← 现有链路零改动
```

### 1. `ITunesChartsService.swift`

```swift
struct ITunesChartsService: Sendable {
    static let discoverGenreIDs: [Int]  // 17 个已验证流派

    func topAlbums(country: String = "US", limit: Int = 25) async throws -> [ITunesResult]
    func genreTopAlbums(genreId: Int, limit: Int = 100) async throws -> [ITunesResult]
    func randomFeaturedAlbums(genreId: Int, limit: Int = 25) async throws -> [ITunesResult]
}
```

- 通过 `URLComponents` 拼 URL；HTTP 状态检查风格与 `ITunesSearchService` 一致
- 旧版 feed 解码：`feed.entry` 单对象/数组自适应；映射 `im:name` / `im:artist` / `id.attributes.im:id` / `im:image` 最大尺寸 / `im:releaseDate`
- 映射为现有 `ITunesResult`：`collectionId = Int(id)`、`collectionName = name`、`trackName = nil`
- 映射后 `isAlbum == true`、`artworkURL(size:)`、`ResultRow`、`StudioDetail` 全部可直接复用

### 2. `SearchViewModel.swift`

- 状态：`featuredAlbums: [ITunesResult]`、`isLoadingFeatured: Bool`、`featuredFailed: Bool`、`lastFeaturedGenreId: Int?`
- `loadFeaturedAlbums()`：幂等（`featuredAlbums` 为空且不在加载中才执行），视图 `.task` 调用
- `refreshFeaturedAlbums()`：强制重载并换流派，供下拉刷新 / 刷新按钮
- 失败时保留旧批次；若从未加载成功则置 `featuredFailed`，不弹出全局错误、不影响搜索状态机

### 3. `ContentView.swift`

新增共享视图 `FeaturedAlbumsGrid`：

- `LazyVGrid` 按水平尺寸类自适应：iOS regular（iPad）`adaptive(minimum: 150, maximum: 220)`，compact（iPhone）`96–160`；macOS 保持 `96–160`
- iPad（regular）封面标题/歌手字体同步放大为 `subheadline` / `footnote`
- 单元格：方形 `AsyncImage`（`.scaledToFill` + 圆角）+ 专辑名 + 歌手，`caption` 字号、单行截断，占位为 `.quaternary`
- 缩略图分辨率：统一走 `artworkURL(size:)` 替换 CDN 尺寸，避免 Retina 下 100px 源被放大发糊——网格 600、搜索结果行 200、studio 头部 300；生成壁纸仍用 `highResArtworkURL()`（3000）
- `onSelect: (ITunesResult) -> Void` 回调
- 加载中：居中 `ProgressView` + `featured_loading` 文案
- 加载失败：回退现有 idle 空状态（`search_idle_title` / `search_idle_hint`），并保留重试入口

接入点：

- iOS `SearchList`：`searchTerm` 为空且无搜索结果时显示网格（替换原 `ContentUnavailableView`）；`.task` 加载；`.refreshable` 触发刷新；点击 `selection = album` 触发 push + 生成
- macOS `SearchResultsList`：idle 分支同样显示网格（侧栏宽 300–400pt，约 3 列）；点击 `selection = album` 由 `NavigationSplitView` 详情区接管
- 有搜索词/搜索结果时行为保持现状，不变

### 4. 本地化

| key | en | zh-Hans |
|-----|----|---------|
| `featured_title` | Discover | 发现专辑 |
| `featured_loading` | Loading albums… | 正在加载专辑… |
| `featured_failed` | Could not load albums. | 无法加载专辑。 |
| `featured_refresh` | Refresh | 刷新 |

## 验收标准

1. 冷启动后，iOS 搜索页 / macOS 侧栏在无搜索状态下显示 25 张专辑封面网格
2. 点击任意封面 → 立即进入 studio，下载高清封面并生成四种壁纸方案（复用现有流程）
3. 点击刷新 / 下拉刷新 → 批次明显变化（换流派 + 重新洗牌），且 25 张内无重复
4. 断网启动：网格区域回退为空状态或失败提示，搜索功能不受影响
5. macOS 与 iOS Simulator 均 BUILD SUCCEEDED

## 非目标

- 不做榜单缓存层、不做离线持久化
- 不引入 Apple Music API / MusicKit
- 不做 explicit 内容过滤（与现有搜索行为一致）
- 不改动 `WallpaperGenerator` 与导出流程

## 风险与注意

- 榜单为 Apple 官方推广素材渠道，条款要求素材仅用于推广商店内容；App 现有"运行时下载封面生成壁纸"的用法不变，本次仅新增入口，不扩大素材使用范围
- 旧版流派 RSS 属未文档化接口：流派偶发空结果，单源失败必须静默降级为榜单池；若未来整体失效，混池自动退回仅榜单
- Marketing Tools feed 每日更新一次，无文档化 SLA；失败路径必须静默回退
