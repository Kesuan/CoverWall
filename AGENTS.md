# AGENTS.md

CoverWall 是一个把 iTunes 专辑封面生成设备壁纸的多平台 SwiftUI 应用（iOS 17+ / iPadOS 17+ / macOS 14+）。本文档给在本仓库工作的 coding agent / 贡献者使用。

## 工程与构建

工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成。**不要手工改 `CoverWall.xcodeproj/project.pbxproj`**，改源文件后需要时重新生成：

```bash
cd "$(git rev-parse --show-toplevel)"
xcodegen generate
```

Shared scheme 为 `CoverWall`（由 XcodeGen 写入 `xcshareddata/xcschemes/`）。

编译验证（CLI，跳过签名）：

```bash
export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"   # 或本机 Xcode 路径

# macOS
xcodebuild -project CoverWall.xcodeproj -scheme CoverWall \
  -destination 'generic/platform=macOS' -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build

# iOS Simulator
xcodebuild -project CoverWall.xcodeproj -scheme CoverWall \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

改完源码后，**至少让 macOS 与 iOS Simulator 两边都 BUILD SUCCEEDED 再收工**。

### 签名与隐私（必读）

- **`DEVELOPMENT_TEAM` 与个人 `PRODUCT_BUNDLE_IDENTIFIER` 不得写入 `project.yml` / `project.pbxproj` / 任何将提交的文件。**
- 本地真机/商店构建使用 `Config/Signing.local.xcconfig`（已 gitignore）；模板见 `Config/Signing.local.xcconfig.example`。
- `Config/Signing.xcconfig` 只 `#include?` 本地文件，本身不含身份信息。
- 仓库内中性 bundle id 为 `com.example.coverwall`。
- macOS 本地 Debug 为 ad-hoc 签名（`CODE_SIGN_IDENTITY[sdk=macosx*] = "-"`）；iOS Automatic。
- 不要提交 `.p12` / `.mobileprovision` / `.cer` / `*.certSigningRequest`。

## 架构速览

```
搜索 UI ──► SearchViewModel ──► ITunesSearchService ──► iTunes Search API
                                      │
                                      ▼
选中专辑 ──► WallpaperStudioViewModel ──► ArtworkLoader (Data→CGImage)
                                      │
                                      ▼
                              WallpaperGenerator.generate(...)
                                      │  四算法，输出 CGImage
                                      ▼
                    StudioDetail 四方案网格 ──► FullscreenPreview
                                      │
                                      ▼
                         PhotoExportService（相册 / 分享 / macOS 存文件）
```

| 文件 | 职责 |
|------|------|
| `CoverWallApp.swift` | `@main` 入口；macOS 默认窗口尺寸 |
| `ContentView.swift` | 根导航：macOS `NavigationSplitView` / iOS `NavigationStack` |
| `SearchViewModel.swift` | 搜索词、结果列表、搜索状态 |
| `ITunesModels.swift` | 搜索结果模型 |
| `ITunesSearchService.swift` | 专辑+歌曲并行搜索、封面下载 |
| `WallpaperStudioViewModel.swift` | 选中项、目标设备、后台生成与导出编排 |
| `ArtworkLoader.swift` | `Data`/`URL` → `CGImage` |
| `WallpaperGenerator.swift` | 四算法 Core Image 管线（**仅依赖 CGImage/CoreGraphics/CoreImage**） |
| `Models.swift` | `DeviceProfile` / `WallpaperAlgorithm` / `WallpaperResult` |
| `StudioDetail.swift` | 设备切换 + 四方案对比网格 |
| `FullscreenPreview.swift` | 全屏预览与导出 |
| `PhotoExportService.swift` | JPEG 编码、`PHPhotoLibrary` 写入、macOS `NSSavePanel` |
| `PlatformImage.swift` | `CGImage` → UIKit/AppKit 的唯一桥接点 |

## 硬约束

1. **`WallpaperGenerator` 保持跨平台**  
   禁止 `import AppKit` / `UIKit` / `NSImage` / `UIImage`。输入输出一律 `CGImage`。平台差异只允许出现在 `PlatformImage`、`PhotoExportService` 的 `#if os(...)` 分支，以及 View 层。

2. **设备预设不要随意改尺寸**  
   `1179×2556` / `1668×2388` / `2880×1800` 与算法里的 portrait/landscape 分支阈值（如 `height > width * 1.15`、`> 1.6`）是配套调过的。若新增分辨率，需要同时回归四算法在竖屏与横屏下的观感。

3. **不要打包受版权保护的封面图**  
   仓库与 App 资源中不得加入示例专辑封面。调试请用真实搜索结果。

4. **文案走本地化**  
   用户可见字符串使用 `Localizable.strings`（`en` + `zh-Hans`）的 key；SwiftUI 用 `Text("key")` 或 `LocalizedStringKey`。需要拼接进 `String` 时用 `String(localized: String.LocalizationValue(key))`，不要把 `LocalizedStringKey` 直接塞进 `String(localized:)`。

5. **生成在后台，回主 Actor 更新 UI**  
   `WallpaperStudioViewModel.generate` 使用 `Task.detached`；改生成流程时保持 UI 不被大图渲染卡住。

6. **身份信息不进仓库**  
   Team ID、个人 Apple 开发者账号相关值、本机绝对路径、证书与描述文件一律留在 gitignored 的本地配置里。

## 算法备忘（改动 `WallpaperGenerator` 前必读）

| 算法 | 要点 |
|------|------|
| Smart Crop | 焦点由局部边缘能量 + 饱和度 + 中心偏置估计；裁切后 `resizeToCanvas` |
| Mirror + Blur | 竖屏走 `portraitMirrorBlur`（垂直镜像扩展）；横屏 aspect-fill + 侧向镜像 |
| Frequency Separation | 低频（大半径高斯 + 降饱和）垫底，前景 unsharp + 羽化遮罩 |
| Blur Fill | 短边满幅 + 镜像延展背景；四层雾化（heavy/medium/soft/sharp）+ 底部雾化（竖屏）+ ambient 调色 |

`finish()` 里的 portrait damping（按宽高比压暗渐晕/上下暗角）是为了竖屏不“糊成一片”，不要为了对称去去掉。

## README 示例资源

- 示例封面与四算法全尺寸壁纸在 `Docs/Examples/`（`readme/` 为嵌入用缩略图）。
- 改算法后可用 `Tools/GenerateReadmeExamples/main.swift` 链上 `Models` + `WallpaperGenerator` 重新导出，命令见 README Examples 小节。
- 示例封面是文档用原创插画，**不是**真实专辑封面。

## 提交约定

- 信息用英文祈使句，说明 *why* 而不是罗列文件。
- 不要提交 `xcuserdata/`、`.DS_Store`、DerivedData（已在 `.gitignore`）。
- 生成 `project.yml` 变更时，一并提交重新生成后的 `project.pbxproj` 与 shared scheme。
- 提交前搜索本地开发者账号标识（Team ID、个人 bundle 前缀、本机用户名路径），避免身份信息回流。

## License

仓库采用 **PolyForm Noncommercial 1.0.0**（禁止他人商用；作者保留商业发行权）。改代码前先读根目录 `LICENSE`。

## 尚未实现 / 勿假装已完成

- 无单元测试 target
- App Icon：浅色已进 `AppIcon.appiconset`；深色 SVG/PNG 在 `Design/AppIcon/`，**未**接入多平台 catalog 的 macOS dark appearance（原因见 `Design/AppIcon/README.md`）
- 不读 Apple Music 资料库、不支持本地图片导入
- iOS 无法程序化设壁纸，只导出到相册/分享
- Mac App Store 沙盒 entitlements 未配置（当前空字典，仅适合本地/开源构建）
