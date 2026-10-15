# SPEC: 下载专辑封面原图

- 状态：已实现
- 日期：2026-09-20
- 关联文件（拟改）：
  - `CoverWall/WallpaperStudioViewModel.swift`
  - `CoverWall/PhotoExportService.swift`
  - `CoverWall/StudioDetail.swift`
  - `CoverWall/ITunesModels.swift`（仅命名/注释微调，可选）
  - `CoverWall/en.lproj/Localizable.strings`
  - `CoverWall/zh-Hans.lproj/Localizable.strings`
- 明确不改：`WallpaperGenerator.swift`、设备预设尺寸、算法阈值

## 背景与目标

CoverWall 的主路径是「选封面 → 下载高清源图 → 生成四方案壁纸 → 导出壁纸」。用户已经能看到源封面分辨率（Studio 头部 `sourceArtwork` 的 `宽 × 高 · 源封面`），但**没有办法把这张源封面本身保存/分享出去**。

现状里还有一个隐性浪费：`prepare(result:)` 已经通过 `ITunesSearchService.downloadArtwork` 拉到了原始 `Data`，随后只转成 `CGImage` 做生成，**原始字节被丢弃**。若再对 `CGImage` 做 JPEG 重编码导出，会白白损失质量。

目标：

1. 在壁纸工作室提供「下载/保存原图」入口，用户可把当前专辑封面存到相册（iOS）或存成文件（macOS），并可走系统分享。
2. 导出尽量使用 **CDN 返回的原始字节**，避免二次 JPEG 压缩。
3. 不改变壁纸生成与四方案导出主链路。

## 产品定义

### 什么算「原图」

| 术语 | 含义 |
|------|------|
| CDN 源文件 | 请求 `highResArtworkURL(size: 3000)` 后 Apple CDN 返回的字节流；CDN 不会放大超过原稿分辨率（代码注释已说明） |
| App 内「原图」 | 上述字节流本身；展示尺寸以解码后的 `CGImage` 宽高为准 |
| 非目标 | 不是「无限分辨率」；不是原始出版物的 master 文件；不保证 PNG/无损 |

请求尺寸沿用现有默认 **3000**，与壁纸生成共用同一次下载，不额外打网络。

### 用户故事

- 作为用户，我在工作室选中一张专辑后，想把封面原图存到相册/磁盘，而不必先看壁纸方案。
- 作为用户，我想分享高清封面给朋友，用系统分享即可。
- 作为用户，我能在界面上看到源封面分辨率，确认这就是将要导出的那张。

### 交互与信息架构

**唯一主入口：Studio 头部元信息区**（与 `sourceArtwork` 尺寸标签同一视觉簇）。

```
┌──────────────────────────────────────────────────────────┐
│  [封面 84×84]  专辑名                                      │
│                 艺人名                                    │
│                 2400 × 2400 · 源封面                      │
│                 [↓ 保存原图] [分享]   ← 新增              │
├──────────────────────────────────────────────────────────┤
│  目标设备 · iPhone / iPad / Mac                           │
├──────────────────────────────────────────────────────────┤
│  四方案网格（现有）                                       │
└──────────────────────────────────────────────────────────┘
```

平台差异：

| 平台 | 主按钮 | 次按钮 |
|------|--------|--------|
| iOS / iPadOS | 保存到相册（`square.and.arrow.down`） | 分享（`ShareLink`） |
| macOS | 存储文件…（`folder` / NSSavePanel） | 分享（`ShareLink`） |

规则：

1. **按钮仅在源图数据就绪时可用**（`isDownloading == false && sourceArtworkData != nil`）。下载中显示禁用态，不与全局 `loadingBlock` 抢注意力。
2. 成功/失败文案复用 `exportMessage` / `errorMessage`，与壁纸导出共用提示条，避免状态机分叉。
3. **不**在 `FullscreenPreview` 加「下载原图」——那里语义是壁纸预览；混入源图会破坏「预览 = 壁纸结果」的心智。
4. **不**在搜索结果列表/发现墙做快捷下载：列表只有 100px 缩略 URL，走完整原图链路会拖慢滚动，且与「先选中再工作」的产品节奏一致。
5. 可选增强（本期可不做）：Studio 头部封面图的 contextMenu / 长按菜单里镜像同一组动作，方便触控设备。

### 文案（本地化 key）

| key | en | zh-Hans |
|-----|----|---------|
| `save_artwork` | Save Original Artwork | 保存封面原图 |
| `export_saved_artwork_photos` | Artwork saved to Photos | 封面已保存到相册 |
| `export_saved_artwork_file` | Artwork file saved | 封面文件已保存 |
| `error_artwork_unavailable` | Original artwork is not ready yet. | 封面原图尚未就绪。 |

复用现有：`share_action`、`error_photo_permission`、`error_save_failed`、`error_encode_failed`。

建议文件名（与壁纸区分）：

```
{suggestedFileName 去掉 .jpg} · Cover.jpg
→ "Radiohead - OK Computer · Cover.jpg"
```

或更稳妥、避免中点依赖：

```
{suggestedFileName 去掉 .jpg} Cover.jpg
→ "Radiohead - OK Computer Cover.jpg"
```

推荐后者（系统文件名更友好）。壁纸仍用现有 `suggestedFileName`。

## 技术方案

### 数据流（目标）

```
prepare(result)
    │
    ├─ downloadArtwork(highResURL)  ──► Data  ──► 缓存 sourceArtworkData（新增）
    │                                        └─► ArtworkLoader.cgImage ──► sourceArtwork（现有）
    │
    └─ generate() 使用 sourceArtwork（不变）

用户点「保存/分享」
    │
    ├─ 优先：sourceArtworkData 原始字节
    └─ 回退：PhotoExportService.jpegData(from: sourceArtwork)  （仅当 data 缺失，理论上不应发生）
```

### 1. ViewModel：缓存原始字节

`WallpaperStudioViewModel`：

```swift
var sourceArtworkData: Data?   // 新增
// prepare 中：
let data = try await service.downloadArtwork(from: url)
guard let image = ArtworkLoader.cgImage(from: data) else { throw ArtworkError.invalidImage }
sourceArtworkData = data
sourceArtwork = image
```

- `prepare` 开头清空 `sourceArtworkData`（与 `sourceArtwork` 一致）。
- 新增建议文件名：

```swift
var suggestedArtworkFileName: String {
    let base = suggestedFileName.hasSuffix(".jpg")
        ? String(suggestedFileName.dropLast(4))
        : suggestedFileName
    return base + " Cover.jpg"
}
```

- 新增导出编排（与 `saveToPhotos(_ result:)` 对称）：

```swift
func saveArtwork() async
func artworkSharePayload() -> PlatformShareImage?  // data + name + cgImage
#if os(macOS)
func saveArtworkViaPanel()
#endif
```

实现要点：`saveArtwork` / `saveArtworkViaPanel` 优先写 `sourceArtworkData`；没有 data 时回退对 `sourceArtwork` 编码。`isExporting` 可与壁纸导出共用，避免同时双写相册时的并发 UI；本期允许共用。

### 2. PhotoExportService：支持「已是文件」的导出路径

现有 API 全部接收 `CGImage` 并强制 `jpegData`。新增重载，**数据已就绪时不再编码**：

```swift
// iOS
static func saveToPhotoLibrary(_ data: Data) async throws

// macOS
static func savePanelWrite(_ data: Data, suggestedName: String) throws
```

实现可抽私有：

```swift
private static func saveToPhotoLibrary(resourceData: Data) async throws {
    // 与现有 addOnly 权限逻辑相同；PHAssetCreationRequest.addResource(with: .photo, data:)
}
```

注意：

- 仍按 photo 资源写入相册；若未来发现 CDN 偶发非 JPEG/PNG，可读 `CGImageSource` 的 UTI 决定 `.photo` vs `.photo` + options，**本期默认字节即 JPEG**（搜索链路规范化 `.../100x100bb.jpg`，charts 也已规范到 `.jpg`）。
- macOS `allowedContentTypes` 保持 `[.jpeg]`，与文件名后缀一致。
- 不新增 PNG 导出选项。

分享：复用 `PlatformShareImage`，`data` 填原始字节即可（`transferRepresentation` 已是 `DataRepresentation` + JPEG content type）。

### 3. StudioDetail：头部操作条

在 `header` 的 `VStack` 中，分辨率标签下方增加：

```swift
if studio.sourceArtwork != nil || studio.isDownloading {
    HStack(spacing: 8) {
        Button { Task { await studio.saveArtwork() } } label: {
            Label(...)  // iOS: save_artwork / macOS: save_file 或 save_artwork
        }
        .buttonStyle(.bordered)
        .disabled(studio.sourceArtworkData == nil || studio.isExporting)

        if let payload = studio.artworkSharePayload() {
            ShareLink(item: payload, preview: ...) { ... }
                .buttonStyle(.borderless)
                .disabled(studio.sourceArtworkData == nil)
        }
    }
    .font(.subheadline)
}
```

样式约束：

- 不用 `.borderedProminent`——那是全屏预览的主 CTA；工作室头部保持次要操作权重。
- 与尺寸标签同一左对齐流，不引入新卡片，避免头部过重。
- macOS 最小窗口下不换行挤压标题：按钮放第二行或尾随 `Spacer()` 右对齐均可；推荐 **尾随右对齐**（`HStack { metaVStack; Spacer(); actions }`），与现有 `header` 的 `Spacer()` 结构一致。

### 4. 架构边界（遵守 AGENTS.md）

| 约束 | 本方案如何满足 |
|------|----------------|
| `WallpaperGenerator` 仅 CGImage / 跨平台 | 零改动 |
| 后台下载，主 Actor 更新 UI | `prepare` 已在 MainActor；不引入大图重编码主路径 |
| 文案走 Localizable.strings | 新增 4 个 key，en + zh-Hans |
| 不打包真实专辑封面 | 仍走运行时 CDN |
| 身份信息不进仓库 | 无签名/Team 变更 |
| 平台分支限制在 View / PhotoExportService | 新 API 与 `#if os(macOS)` 仅落在这两处 |

### 5. 性能与内存

- 原图 Data 已在生成前下载；缓存仅多持有一份约 0.5–3MB 的 JPEG，可接受。
- 导出相册路径：原始字节直写，**不再** `CGImage → JPEG 0.95`，CPU 与质量双赢。
- 分享 payload 随 `ShareLink` 创建；头部按钮创建成本可忽略。
- 不做磁盘缓存层；切换专辑时旧 Data 随 `prepare` 释放。

## 错误与边界

| 场景 | 行为 |
|------|------|
| 下载失败 / 无法解码 | 保持现有 `errorMessage`；不出现保存按钮（data 为 nil） |
| 相册权限拒绝 | 复用 `error_photo_permission` |
| 用户在保存面板取消 | 静默返回（与现有壁纸 `savePanelWrite` 一致，不报错） |
| CDN 实际分辨率 < 3000 | 正常导出真实尺寸；尺寸标签已展示实际宽高，不另做「分辨率告警」 |
| charts 发现墙点击进入 | 同走 `prepare`，与搜索结果无差别 |
| 单曲结果（有 trackName） | 同样可保存封面；文件名用 `title`（已有回退） |
| 与壁纸导出同时点击 | 共用 `isExporting`，后者排队或按钮禁用 |

## 被否决的方案

| 方案 | 原因 |
|------|------|
| 在 `FullscreenPreview` 增加「保存源封面」 | 预览语义是壁纸；会混淆「正在存什么」 |
| 搜索列表每行快捷下载 | 未选中时无高清缓存；列表滚动成本高；与工作流不一致 |
| 导出前用 `sourceArtwork` 重新 JPEG 编码 | 丢弃 CDN 原始压缩质量，违背「原图」 |
| 用 Apple Music API 拿更高质量资产 | 需 JWT/开发者密钥，不适合客户端（与发现专辑 SPEC 结论一致） |
| 提供分辨率选项（600/1200/3000） | 已有 3000 一次到位；选项增加 UI 与 CDN 负担，本期不做 |
| 新建独立 `ArtworkExportService` | 职责仍是「把图像数据写到相册/磁盘」，扩展 `PhotoExportService` 更贴现有边界 |

## 实现清单（建议顺序）

1. `PhotoExportService`：`saveToPhotoLibrary(Data)` / macOS `savePanelWrite(Data, suggestedName:)`，抽取权限与写文件共用逻辑。
2. `WallpaperStudioViewModel`：缓存 `sourceArtworkData`；`suggestedArtworkFileName`；`saveArtwork()` / `saveArtworkViaPanel()` / `artworkSharePayload()`。
3. `StudioDetail.header`：操作条 + 禁用态；macOS 右对齐。
4. `Localizable.strings`：en + zh-Hans 四条文案；错误文案若需区分「原图未就绪」则加 `error_artwork_unavailable`。
5. 回归：iOS Simulator + macOS `BUILD SUCCEEDED`；手测保存/分享/权限拒绝/切换专辑后按钮状态。

## 验收标准

- [ ] 选中专辑并完成下载后，Studio 头部出现保存原图与分享入口。
- [ ] iOS：保存成功后相册出现封面图；分辨率与头部标签一致。
- [ ] macOS：存储面板默认文件名含艺人、专辑与 `Cover`。
- [ ] 导出字节与 CDN 响应在无回退路径下一致（可用导出前后 `Data.count` / hash 抽查）。
- [ ] 壁纸四方案预览、保存、分享行为无回归。
- [ ] 未选中/下载中/失败态不出现可点的保存原图按钮。
- [ ] 中英文案完整；`xcodebuild` 双平台通过。

## 后续可选（明确不在本期）

- 封面原图全屏预览（缩放）——若做，应是独立轻量 sheet，不塞进壁纸 `FullscreenPreview`。
- 批量保存多张发现墙封面。
- 按 content-type 动态选择 JPEG/PNG 资源类型。
- 将原图尺寸展示改为「实际 / 请求」双值。

## 决策记录

| 议题 | 结论 |
|------|------|
| 入口位置 | Studio 头部，与源封面尺寸同簇 |
| 字节策略 | 优先缓存 `prepare` 原始 Data，禁止默认重编码 |
| 请求尺寸 | 沿用 3000，与生成共用一次下载 |
| 平台动作 | iOS 相册+分享；macOS 存文件+分享 |
| 与壁纸导出关系 | 扩展同一 Service + 同一提示条，不新建子系统 |
| Preview / 列表入口 | 本期不做 |
