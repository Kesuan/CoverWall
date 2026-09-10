# CoverWall App Icon

瑞士几何：半切圆盘 + 斜带 + 朱红竖屏。源 SVG 分浅色 / 深色两套。

## 源文件

| 文件 | 用途 |
|------|------|
| `icon-light.svg` | 浅色主图 |
| `icon-dark.svg` | 深色主图（macOS dark appearance） |
| `render_swiss_icons.swift` | Core Graphics 光栅化，输出不透明方形 PNG |

## 重新导出

```bash
cd "$(git rev-parse --show-toplevel)"
swift Design/AppIcon/render_swiss_icons.swift Design/AppIcon/png \
  16 32 64 128 256 512 1024
rm -f CoverWall/Assets.xcassets/AppIcon.appiconset/AppIcon-*.png
cp Design/AppIcon/png/AppIcon-Light-*.png Design/AppIcon/png/AppIcon-Dark-*.png \
  CoverWall/Assets.xcassets/AppIcon.appiconset/
```

## Xcode

- iOS：`AppIcon-Light-1024`（universal）
- macOS：全尺寸 light 槽位
- **不把 dark appearance 写进共享的多平台 `AppIcon`**：actool 会把 mac 的 `luminosity=dark` 子项标成 unassigned 并丢掉（警告 `has N unassigned children`），`Assets.car` 里也不会出现 dark 渲染。深色 SVG 仍保留在本目录，若将来拆成 macOS-only target 再接入。
- postbuild `Install Complete macOS App Icon` 用 light 图补全 icns 并 ad-hoc 重签

## macOS 图标不显示

1. Product → Clean Build Folder
2. `killall Dock Finder`
3. 或把 `.app` 拷出 DerivedData
