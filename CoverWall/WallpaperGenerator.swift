import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum WallpaperGenerator {
    private static let context = CIContext(options: [.cacheIntermediates: true])

    static func generate(source cgImage: CGImage, for device: DeviceProfile) -> [WallpaperResult] {
        let source = CIImage(cgImage: cgImage)
        let targetSize = device.outputSize

        return WallpaperAlgorithm.allCases.compactMap { algorithm in
            let output: CIImage
            switch algorithm {
            case .smartCrop:
                output = smartCrop(source, targetSize: targetSize)
            case .mirrorBlur:
                output = mirrorBlur(source, targetSize: targetSize)
            case .frequencySeparation:
                output = frequencySeparation(source, targetSize: targetSize)
            case .blurFill:
                output = blurFill(source, targetSize: targetSize)
            }

            guard let image = render(output, size: targetSize) else { return nil }
            return WallpaperResult(algorithm: algorithm, image: image)
        }
    }

    // MARK: - Smart Crop

    private static func smartCrop(_ source: CIImage, targetSize: CGSize) -> CIImage {
        let sourceExtent = source.extent.integral
        let sourceAspect = sourceExtent.width / sourceExtent.height
        let targetAspect = targetSize.width / targetSize.height
        let focalPoint = estimateFocalPoint(in: source)

        var cropRect = sourceExtent
        if sourceAspect > targetAspect {
            let cropWidth = sourceExtent.height * targetAspect
            let centerX = sourceExtent.minX + focalPoint.x * sourceExtent.width
            let originX = clamp(
                centerX - cropWidth * 0.5,
                lower: sourceExtent.minX,
                upper: sourceExtent.maxX - cropWidth
            )
            cropRect = CGRect(x: originX, y: sourceExtent.minY, width: cropWidth, height: sourceExtent.height)
        } else if sourceAspect < targetAspect {
            let cropHeight = sourceExtent.width / targetAspect
            let centerY = sourceExtent.minY + (1 - focalPoint.y) * sourceExtent.height
            let originY = clamp(
                centerY - cropHeight * 0.5,
                lower: sourceExtent.minY,
                upper: sourceExtent.maxY - cropHeight
            )
            cropRect = CGRect(x: sourceExtent.minX, y: originY, width: sourceExtent.width, height: cropHeight)
        }

        return resizeToCanvas(source.cropped(to: cropRect), size: targetSize)
    }

    // MARK: - Mirror + Blur

    private static func mirrorBlur(_ source: CIImage, targetSize: CGSize) -> CIImage {
        let shortSide = min(targetSize.width, targetSize.height)
        let isTallPortrait = targetSize.height / max(targetSize.width, 1) > 1.6
        if isTallPortrait {
            return portraitMirrorBlur(source, targetSize: targetSize)
        }

        let base = aspectFill(source, into: targetSize)
        let mirrored = aspectFill(mirrored(source), into: targetSize)
        let canvasRect = CGRect(origin: .zero, size: targetSize)

        let blurredBase = blur(base, radius: shortSide * 0.045)
        let blurredMirror = opacity(blur(mirrored, radius: shortSide * 0.065), value: 0.28)
        let background = canvasFilled(
            blurredMirror.composited(over: blurredBase),
            size: targetSize
        )

        let inset = shortSide * 0.075
        let contentRect = aspectFitRect(
            source.extent.size,
            in: canvasRect.insetBy(dx: inset, dy: inset)
        )
        let foreground = place(source, in: contentRect)
        let mask = featheredRectangleMask(
            size: targetSize,
            rect: contentRect,
            feather: shortSide * 0.06
        )

        let composed = blend(foreground, over: background, mask: mask)
        return finish(
            composed,
            targetSize: targetSize,
            topDarkness: 0.10,
            bottomDarkness: 0.20,
            vignette: 0.22
        )
    }

    private static func portraitMirrorBlur(_ source: CIImage, targetSize: CGSize) -> CIImage {
        let shortSide = min(targetSize.width, targetSize.height)
        let canvasRect = CGRect(origin: .zero, size: targetSize)
        let extensionRect = portraitContentRect(targetSize, widthRatio: 1, verticalCenter: 0.5)
        let background = blur(
            verticallyMirroredExtension(source, contentRect: extensionRect, targetSize: targetSize),
            radius: shortSide * 0.075
        )

        let contentRect = portraitContentRect(targetSize, widthRatio: 0.88, verticalCenter: 0.52)
        let foreground = place(source, in: contentRect)
        let mask = featheredRectangleMask(
            size: targetSize,
            rect: contentRect,
            feather: shortSide * 0.085
        )

        return portraitComposite(
            background: background,
            foreground: foreground,
            mask: mask,
            targetSize: targetSize
        ).cropped(to: canvasRect)
    }

    // MARK: - Frequency Separation

    private static func frequencySeparation(_ source: CIImage, targetSize: CGSize) -> CIImage {
        let shortSide = min(targetSize.width, targetSize.height)
        let isTallPortrait = targetSize.height / max(targetSize.width, 1) > 1.6
        if isTallPortrait {
            return portraitFrequencySeparation(source, targetSize: targetSize)
        }

        let base = aspectFill(source, into: targetSize)

        let lowFrequency = base
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: shortSide * 0.065
            ])
            .cropped(to: CGRect(origin: .zero, size: targetSize))
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.78,
                kCIInputBrightnessKey: -0.025,
                kCIInputContrastKey: 1.03
            ])
        let lowFrequencyCanvas = canvasFilled(lowFrequency, size: targetSize)

        let inset = shortSide * 0.035
        let contentRect = aspectFitRect(
            source.extent.size,
            in: CGRect(origin: .zero, size: targetSize).insetBy(dx: inset, dy: inset)
        )
        let foreground = place(source, in: contentRect)
            .applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: shortSide * 0.006,
                kCIInputIntensityKey: 0.48
            ])
        let mask = featheredRectangleMask(
            size: targetSize,
            rect: contentRect,
            feather: shortSide * 0.075
        )

        let result = blend(foreground, over: lowFrequencyCanvas, mask: mask)
        return finish(
            result,
            targetSize: targetSize,
            topDarkness: 0.13,
            bottomDarkness: 0.24,
            vignette: 0.28
        )
    }

    private static func portraitFrequencySeparation(_ source: CIImage, targetSize: CGSize) -> CIImage {
        let shortSide = min(targetSize.width, targetSize.height)
        let canvasRect = CGRect(origin: .zero, size: targetSize)
        let extensionRect = portraitContentRect(targetSize, widthRatio: 1, verticalCenter: 0.5)
        let extendedSource = verticallyMirroredExtension(
            source,
            contentRect: extensionRect,
            targetSize: targetSize
        )
        let lowFrequency = blur(extendedSource, radius: shortSide * 0.15)

        let contentRect = portraitContentRect(targetSize, widthRatio: 0.94, verticalCenter: 0.52)
        let foreground = place(source, in: contentRect)
            .applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: shortSide * 0.006,
                kCIInputIntensityKey: 0.44
            ])
        let mask = featheredRectangleMask(
            size: targetSize,
            rect: contentRect,
            feather: shortSide * 0.105
        )

        return portraitComposite(
            background: lowFrequency,
            foreground: foreground,
            mask: mask,
            targetSize: targetSize
        ).cropped(to: canvasRect)
    }

    // MARK: - Blur Fill

    private static func blurFill(_ source: CIImage, targetSize: CGSize) -> CIImage {
        let canvasRect = CGRect(origin: .zero, size: targetSize)
        let contentRect = ambientContentRect(for: source.extent.size, targetSize: targetSize)
        let shortSide = min(targetSize.width, targetSize.height)
        let height = max(targetSize.height, 1)
        let width = max(targetSize.width, 1)

        let artwork = place(source, in: contentRect)
        let extended = mirrorExtended(artwork, contentRect: contentRect, targetSize: targetSize)

        let isTallPortrait = height > width * 1.15
        let bgBlurRadius = shortSide * (isTallPortrait ? 0.040 : 0.030)

        let background = canvasFilled(
            blur(extended, radius: bgBlurRadius),
            size: targetSize
        )

        let artTop = (height - contentRect.maxY) / height
        let artBot = (height - contentRect.minY) / height
        let artSpan = max(artBot - artTop, 0.001)
        let artLeft = contentRect.minX / width
        let artRight = contentRect.maxX / width

        let hazeEndFrac: CGFloat = isTallPortrait ? 0.34 : 0.22
        let focusStartFrac: CGFloat = isTallPortrait ? 0.28 : 0.14
        // Wide dissolve: portrait uses canvas remaining on each side so top and
        // bottom share the same "runway into the gutter" geometry.
        let wideTopInFrac: CGFloat = isTallPortrait ? 0.34 : 0.16
        let wideTopOutFrac: CGFloat = isTallPortrait ? 0.70 : 0.06
        let wideBotInFrac: CGFloat = isTallPortrait ? 0.28 : 0.14
        let wideBotOutFrac: CGFloat = isTallPortrait ? 0.70 : 0.18
        let focusOutInFrac: CGFloat = isTallPortrait ? 0.34 : 0.10
        // Visual distance below artBot where the sharp layer fully dies.
        let focusOutEndFrac: CGFloat = isTallPortrait ? 0.08 : 0.015
        let heavyBlurRadius = shortSide * (isTallPortrait ? 0.024 : 0.016)
        let mediumBlurRadius = shortSide * (isTallPortrait ? 0.010 : 0.006)
        let softBlurRadius = shortSide * (isTallPortrait ? 0.0035 : 0.002)
        // Strong horizontal edges near a border need extra haze so the seam
        // cannot punch through a thin veil.
        let topEdgeBoost = isTallPortrait ? estimateEdgeBoost(in: source, atTop: true) : 1.0
        let bottomEdgeBoost = isTallPortrait ? estimateEdgeBoost(in: source, atTop: false) : 1.0

        let hazeEnd = artTop + artSpan * hazeEndFrac
        let focusStart = artTop + artSpan * focusStartFrac

        let contentXMask: CIImage
        if artLeft > 0.015 || artRight < 0.985 {
            contentXMask = multiplyMasks(
                ciHorizontalRamp(
                    size: targetSize,
                    xFromLeft0: artLeft, alpha0: 0,
                    xFromLeft1: min(1, artLeft + 0.04), alpha1: 1
                ),
                ciHorizontalRamp(
                    size: targetSize,
                    xFromLeft0: max(0, artRight - 0.04), alpha0: 1,
                    xFromLeft1: artRight, alpha1: 0
                )
            )
        } else {
            contentXMask = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
                .cropped(to: canvasRect)
        }

        let heavy = blur(extended, radius: heavyBlurRadius)
        let medium = blur(extended, radius: mediumBlurRadius)
        let soft = blur(extended, radius: softBlurRadius)

        let sharpMask = multiplyMasks(
            ciVerticalRamp(
                size: targetSize,
                yFromTop0: artTop + artSpan * (focusStartFrac - 0.10), alpha0: 0,
                yFromTop1: hazeEnd + artSpan * 0.05, alpha1: 1
            ),
            contentXMask
        )
        // Base stack: heavy atmosphere, then progressive top/bottom border
        // dissolve, then the sharp subject only in the focus band.
        var hazyArtwork = heavy
        hazyArtwork = blend(medium, over: hazyArtwork, mask: multiplyMasks(
            borderTierMask(
                size: targetSize,
                borderFrac: artTop,
                artSpan: artSpan,
                gutterSpan: artTop,
                isTop: true,
                insideInFrac: 0.18,
                insideOutFrac: 0.08,
                outsideOutFrac: 0.12,
                peakAlpha: 1
            ),
            contentXMask
        ))
        hazyArtwork = blend(soft, over: hazyArtwork, mask: multiplyMasks(
            borderTierMask(
                size: targetSize,
                borderFrac: artTop,
                artSpan: artSpan,
                gutterSpan: artTop,
                isTop: true,
                insideInFrac: 0.20,
                insideOutFrac: 0.16,
                outsideOutFrac: 0.20,
                peakAlpha: 1
            ),
            contentXMask
        ))
        hazyArtwork = blend(artwork, over: hazyArtwork, mask: sharpMask)

        if isTallPortrait {
            // Same three-tier border dissolve on both ends: high-frequency
            // structure must die before it meets the blurred mirror extension.
            hazyArtwork = applyBorderHaze(
                hazyArtwork,
                extended: extended,
                shortSide: shortSide,
                targetSize: targetSize,
                artSpan: artSpan,
                borderFrac: artTop,
                gutterSpan: artTop,
                isTop: true,
                boost: topEdgeBoost,
                contentXMask: contentXMask
            )
            hazyArtwork = applyBorderHaze(
                hazyArtwork,
                extended: extended,
                shortSide: shortSide,
                targetSize: targetSize,
                artSpan: artSpan,
                borderFrac: artBot,
                gutterSpan: 1 - artBot,
                isTop: false,
                boost: bottomEdgeBoost,
                contentXMask: contentXMask
            )
        }

        // Portrait wide ramps use gutter remaining so top/bottom match.
        let wideTopOuter: CGFloat = isTallPortrait
            ? max(0, artTop - artTop * wideTopOutFrac)
            : artTop - artSpan * wideTopOutFrac
        let wideBotOuter: CGFloat = isTallPortrait
            ? min(1, artBot + (1 - artBot) * wideBotOutFrac)
            : artBot + (1 - artBot) * wideBotOutFrac

        let wideTop = ciVerticalRamp(
            size: targetSize,
            yFromTop0: wideTopOuter, alpha0: 0,
            yFromTop1: artTop + artSpan * wideTopInFrac, alpha1: 1
        )
        let wideBot = ciVerticalRamp(
            size: targetSize,
            yFromTop0: artBot - artSpan * wideBotInFrac, alpha0: 1,
            yFromTop1: wideBotOuter, alpha1: 0
        )
        let wideMask = multiplyMasks(
            multiplyMasks(wideTop, wideBot),
            contentXMask
        )
        let base = canvasFilled(
            blend(hazyArtwork, over: background, mask: wideMask),
            size: targetSize
        )

        let focusIn = ciVerticalRamp(
            size: targetSize,
            yFromTop0: focusStart - artSpan * 0.06, alpha0: 0,
            yFromTop1: focusStart + artSpan * 0.12, alpha1: 1
        )
        let focusOut = ciVerticalRamp(
            size: targetSize,
            yFromTop0: artBot - artSpan * focusOutInFrac, alpha0: 1,
            yFromTop1: artBot - artSpan * focusOutEndFrac, alpha1: 0
        )
        let focusMask = multiplyMasks(
            multiplyMasks(focusIn, focusOut),
            contentXMask
        )
        var composed = blend(artwork, over: base, mask: focusMask)
            .cropped(to: canvasRect)

        if isTallPortrait {
            composed = applyBorderSeal(
                composed,
                shortSide: shortSide,
                targetSize: targetSize,
                artSpan: artSpan,
                borderFrac: artTop,
                gutterSpan: artTop,
                isTop: true,
                boost: topEdgeBoost
            )
            composed = applyBorderSeal(
                composed,
                shortSide: shortSide,
                targetSize: targetSize,
                artSpan: artSpan,
                borderFrac: artBot,
                gutterSpan: 1 - artBot,
                isTop: false,
                boost: bottomEdgeBoost
            )
        }

        let ambient = sampleAmbientColor(from: source)
        return blurFillGrade(
            composed,
            targetSize: targetSize,
            contentRect: contentRect,
            ambient: ambient
        )
    }

    private static func mirrorExtended(
        _ artwork: CIImage,
        contentRect: CGRect,
        targetSize: CGSize
    ) -> CIImage {
        let artExtent = artwork.extent
        var extended = artwork

        let aboveHeight = targetSize.height - contentRect.maxY
        if aboveHeight > 1 {
            let s = max(1, aboveHeight / artExtent.height)
            extended = artwork
                .transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -s, tx: 0, ty: contentRect.maxY + s * artExtent.maxY))
                .composited(over: extended)
        }
        let belowHeight = contentRect.minY
        if belowHeight > 1 {
            let s = max(1, belowHeight / artExtent.height)
            extended = artwork
                .transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -s, tx: 0, ty: contentRect.minY + s * artExtent.minY))
                .composited(over: extended)
        }
        let leftWidth = contentRect.minX
        if leftWidth > 1 {
            let sx = max(1, leftWidth / artExtent.width)
            let sy = max(1, targetSize.height / artExtent.height)
            let ty = targetSize.height * 0.5 - sy * artExtent.midY
            extended = artwork
                .transformed(by: CGAffineTransform(a: -sx, b: 0, c: 0, d: sy, tx: contentRect.minX + sx * artExtent.minX, ty: ty))
                .composited(over: extended)
        }
        let rightWidth = targetSize.width - contentRect.maxX
        if rightWidth > 1 {
            let sx = max(1, rightWidth / artExtent.width)
            let sy = max(1, targetSize.height / artExtent.height)
            let ty = targetSize.height * 0.5 - sy * artExtent.midY
            extended = artwork
                .transformed(by: CGAffineTransform(a: -sx, b: 0, c: 0, d: sy, tx: contentRect.maxX + sx * artExtent.maxX, ty: ty))
                .composited(over: extended)
        }
        return extended
    }

    private static func blurFillGrade(
        _ image: CIImage,
        targetSize: CGSize,
        contentRect: CGRect,
        ambient: CIColor
    ) -> CIImage {
        let canvasRect = CGRect(origin: .zero, size: targetSize)
        let height = max(targetSize.height, 1)
        let width = max(targetSize.width, 1)
        let artTop = (height - contentRect.maxY) / height
        let artBot = (height - contentRect.minY) / height
        let artLeft = contentRect.minX / width
        let artRight = contentRect.maxX / width

        let topVeil = ciVerticalRamp(
            size: targetSize,
            yFromTop0: 0, alpha0: 0.06,
            yFromTop1: 0.16, alpha1: 0
        )
        var result = canvasFilled(navyOverlay(image, mask: topVeil), size: targetSize)

        let depthRise = ciVerticalRamp(
            size: targetSize,
            yFromTop0: artBot - 0.02, alpha0: 0,
            yFromTop1: artBot + (1 - artBot) * 0.30, alpha1: 0.12
        )
        let depthFall = ciVerticalRamp(
            size: targetSize,
            yFromTop0: artBot + (1 - artBot) * 0.30, alpha0: 1,
            yFromTop1: 0.98, alpha1: 0
        )
        result = canvasFilled(
            navyOverlay(result, mask: multiplyMasks(depthRise, depthFall)),
            size: targetSize
        )

        // Bind ambient lift to the dissolve zone so it does not re-impose a
        // color step after border haze has already blended the edge.
        let topAmbientEnd = min(max(artTop + 0.16, 0.08), 0.28)
        let topAmbient = ciVerticalRamp(
            size: targetSize,
            yFromTop0: 0, alpha0: 0.32,
            yFromTop1: topAmbientEnd, alpha1: 0
        )
        result = canvasFilled(colorOverlay(result, color: ambient, mask: topAmbient), size: targetSize)

        // Bind ambient lift to the dissolve zone so it does not re-impose a
        // color step after the bottom haze has already blended the border.
        let bottomAmbientStart = min(max(artBot - 0.20, 0.55), 0.82)
        let bottomAmbient = ciVerticalRamp(
            size: targetSize,
            yFromTop0: bottomAmbientStart, alpha0: 0,
            yFromTop1: min(0.95, bottomAmbientStart + 0.18), alpha1: 0.90
        )
        result = canvasFilled(colorOverlay(result, color: ambient, mask: bottomAmbient), size: targetSize)

        if artLeft > 0.02 {
            let leftAmbient = ciHorizontalRamp(
                size: targetSize,
                xFromLeft0: 0, alpha0: 0.70,
                xFromLeft1: artLeft + 0.02, alpha1: 0
            )
            result = canvasFilled(colorOverlay(result, color: ambient, mask: leftAmbient), size: targetSize)
        }
        if artRight < 0.98 {
            let rightAmbient = ciHorizontalRamp(
                size: targetSize,
                xFromLeft0: artRight - 0.02, alpha0: 0,
                xFromLeft1: 1, alpha1: 0.70
            )
            result = canvasFilled(colorOverlay(result, color: ambient, mask: rightAmbient), size: targetSize)
        }

        return result.cropped(to: canvasRect)
    }

    // MARK: - Shared Helpers

    private static func ambientContentRect(for imageSize: CGSize, targetSize: CGSize) -> CGRect {
        let canvasRect = CGRect(origin: .zero, size: targetSize)
        if targetSize.height > targetSize.width {
            let height = imageSize.height * targetSize.width / imageSize.width
            if height <= targetSize.height {
                return CGRect(
                    x: 0,
                    y: targetSize.height * 0.50 - height * 0.5,
                    width: targetSize.width,
                    height: height
                )
            }
        } else {
            let width = imageSize.width * targetSize.height / imageSize.height
            if width <= targetSize.width {
                return CGRect(
                    x: (targetSize.width - width) * 0.5,
                    y: 0,
                    width: width,
                    height: targetSize.height
                )
            }
        }
        return aspectFitRect(imageSize, in: canvasRect)
    }

    private static func ciVerticalRamp(
        size: CGSize,
        yFromTop0: CGFloat,
        alpha0: CGFloat,
        yFromTop1: CGFloat,
        alpha1: CGFloat
    ) -> CIImage {
        let canvasRect = CGRect(origin: .zero, size: size)
        let y0 = size.height * (1 - yFromTop0)
        let y1 = size.height * (1 - yFromTop1)
        let filter = CIFilter.linearGradient()
        filter.point0 = CGPoint(x: size.width * 0.5, y: y0)
        filter.point1 = CGPoint(x: size.width * 0.5, y: y1)
        let a0 = clamp(alpha0, lower: 0, upper: 1)
        let a1 = clamp(alpha1, lower: 0, upper: 1)
        filter.color0 = CIColor(red: a0, green: a0, blue: a0, alpha: 1)
        filter.color1 = CIColor(red: a1, green: a1, blue: a1, alpha: 1)
        return (filter.outputImage ?? CIImage(color: .black)).cropped(to: canvasRect)
    }

    private static func ciHorizontalRamp(
        size: CGSize,
        xFromLeft0: CGFloat,
        alpha0: CGFloat,
        xFromLeft1: CGFloat,
        alpha1: CGFloat
    ) -> CIImage {
        let canvasRect = CGRect(origin: .zero, size: size)
        let x0 = size.width * xFromLeft0
        let x1 = size.width * xFromLeft1
        let filter = CIFilter.linearGradient()
        filter.point0 = CGPoint(x: x0, y: size.height * 0.5)
        filter.point1 = CGPoint(x: x1, y: size.height * 0.5)
        let a0 = clamp(alpha0, lower: 0, upper: 1)
        let a1 = clamp(alpha1, lower: 0, upper: 1)
        filter.color0 = CIColor(red: a0, green: a0, blue: a0, alpha: 1)
        filter.color1 = CIColor(red: a1, green: a1, blue: a1, alpha: 1)
        return (filter.outputImage ?? CIImage(color: .black)).cropped(to: canvasRect)
    }

    private static func multiplyMasks(_ a: CIImage, _ b: CIImage) -> CIImage {
        a.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: b
        ])
    }

    private static func navyOverlay(_ image: CIImage, mask: CIImage) -> CIImage {
        let navy = CIImage(color: CIColor(red: 0.004, green: 0.012, blue: 0.022))
            .cropped(to: mask.extent)
        return blend(navy, over: image, mask: mask)
    }

    private static func colorOverlay(_ image: CIImage, color: CIColor, mask: CIImage) -> CIImage {
        let fill = CIImage(color: color).cropped(to: mask.extent)
        return blend(fill, over: image, mask: mask)
    }

    private static func sampleAmbientColor(from source: CIImage) -> CIColor {
        let sampleSize = 32
        let extent = source.extent
        guard extent.width > 1, extent.height > 1 else {
            return CIColor(red: 0.11, green: 0.16, blue: 0.20)
        }
        let band = CGRect(
            x: extent.minX,
            y: extent.minY + extent.height * 0.38,
            width: extent.width,
            height: extent.height * 0.18
        )
        let croppedBand = source.cropped(to: band)
        let scaled = croppedBand.transformed(by: CGAffineTransform(
            scaleX: CGFloat(sampleSize) / max(band.width, 1),
            y: CGFloat(sampleSize) / max(band.height, 1)
        ))
        let placed = scaled
            .transformed(by: CGAffineTransform(
                translationX: -scaled.extent.minX,
                y: -scaled.extent.minY
            ))
            .cropped(to: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        var pixels = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            context.render(
                placed,
                toBitmap: baseAddress,
                rowBytes: sampleSize * 4,
                bounds: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        var count: CGFloat = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            r += CGFloat(pixels[i])
            g += CGFloat(pixels[i + 1])
            b += CGFloat(pixels[i + 2])
            count += 1
        }
        guard count > 0 else {
            return CIColor(red: 0.11, green: 0.16, blue: 0.20)
        }
        r /= count * 255
        g /= count * 255
        b /= count * 255
        let lum = r * 0.2126 + g * 0.7152 + b * 0.0722
        let desat: CGFloat = 0.50
        let lift: CGFloat = 0.045
        return CIColor(
            red: clamp(r * (1 - desat) + lum * desat + lift * 0.85, lower: 0, upper: 1),
            green: clamp(g * (1 - desat) + lum * desat + lift * 1.05, lower: 0, upper: 1),
            blue: clamp(b * (1 - desat) + lum * desat + lift * 1.35, lower: 0, upper: 1)
        )
    }

    /// Scale factor in ~[1.0, 1.35] based on edge energy near a square border.
    /// Busy bands (car bodies, letterbox bars, type) get extra dissolve haze.
    private static func estimateEdgeBoost(in source: CIImage, atTop: Bool) -> CGFloat {
        let sampleSize = 64
        let extent = source.extent
        guard extent.width > 1, extent.height > 1 else { return 1 }

        // CI y grows upward from origin: top visual band is high y.
        let bandHeight = extent.height * 0.28
        let band = CGRect(
            x: extent.minX,
            y: atTop ? extent.maxY - bandHeight : extent.minY,
            width: extent.width,
            height: bandHeight
        )
        let croppedBand = source.cropped(to: band)
        let scaled = croppedBand.transformed(by: CGAffineTransform(
            scaleX: CGFloat(sampleSize) / max(band.width, 1),
            y: CGFloat(sampleSize) / max(band.height, 1)
        ))
        let placed = scaled
            .transformed(by: CGAffineTransform(
                translationX: -scaled.extent.minX,
                y: -scaled.extent.minY
            ))
            .cropped(to: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        var pixels = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            context.render(
                placed,
                toBitmap: baseAddress,
                rowBytes: sampleSize * 4,
                bounds: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }

        var totalEdge: CGFloat = 0
        var totalHorizontal: CGFloat = 0
        var count: CGFloat = 0
        for y in 1..<(sampleSize - 1) {
            for x in 1..<(sampleSize - 1) {
                let index = (y * sampleSize + x) * 4
                let luminance = pixelLuminance(pixels, at: index)
                let left = pixelLuminance(pixels, at: index - 4)
                let right = pixelLuminance(pixels, at: index + 4)
                let above = pixelLuminance(pixels, at: index - sampleSize * 4)
                let below = pixelLuminance(pixels, at: index + sampleSize * 4)
                let gx = abs(luminance - left) + abs(luminance - right)
                let gy = abs(luminance - above) + abs(luminance - below)
                totalEdge += gx + gy
                // Horizontal structure (|grad y|) is what reads as a hard cut.
                totalHorizontal += gy
                count += 1
            }
        }

        guard count > 0 else { return 1 }
        let meanEdge = totalEdge / count
        let meanHorizontal = totalHorizontal / count
        // Typical quiet band sits well under 0.08; busy type/metal edges sit higher.
        let edgeScore = meanEdge * 0.55 + meanHorizontal * 0.45
        let t = clamp((edgeScore - 0.06) / 0.12, lower: 0, upper: 1)
        return 1 + t * 0.35
    }

    /// Progressive border dissolve mask. Peak sits on the square's border and
    /// fades into the artwork (inside) and into the canvas gutter (outside).
    private static func borderTierMask(
        size: CGSize,
        borderFrac: CGFloat,
        artSpan: CGFloat,
        gutterSpan: CGFloat,
        isTop: Bool,
        insideInFrac: CGFloat,
        insideOutFrac: CGFloat,
        outsideOutFrac: CGFloat,
        peakAlpha: CGFloat
    ) -> CIImage {
        // Visual coordinates: yFromTop 0 = canvas top, 1 = bottom.
        // "inside" moves into the square; "outside" moves into the gutter.
        let insideFar = isTop
            ? borderFrac + artSpan * insideInFrac
            : borderFrac - artSpan * insideInFrac
        let insideNear = isTop
            ? borderFrac + artSpan * insideOutFrac
            : borderFrac - artSpan * insideOutFrac
        let outsideFar = isTop
            ? max(0, borderFrac - gutterSpan * outsideOutFrac)
            : min(1, borderFrac + gutterSpan * outsideOutFrac)

        let insideRamp = ciVerticalRamp(
            size: size,
            yFromTop0: insideFar, alpha0: 0,
            yFromTop1: insideNear, alpha1: peakAlpha
        )
        let outsideRamp = ciVerticalRamp(
            size: size,
            yFromTop0: insideNear, alpha0: peakAlpha,
            yFromTop1: outsideFar, alpha1: 0
        )
        return multiplyMasks(insideRamp, outsideRamp)
    }

    /// Three-tier soft/medium/heavy haze anchored to a square border.
    private static func applyBorderHaze(
        _ image: CIImage,
        extended: CIImage,
        shortSide: CGFloat,
        targetSize: CGSize,
        artSpan: CGFloat,
        borderFrac: CGFloat,
        gutterSpan: CGFloat,
        isTop: Bool,
        boost: CGFloat,
        contentXMask: CIImage
    ) -> CIImage {
        let b = clamp(boost, lower: 1, upper: 1.4)
        let softLayer = blur(extended, radius: shortSide * 0.010 * b)
        let mediumLayer = blur(extended, radius: shortSide * 0.014 * b)
        let heavyLayer = blur(extended, radius: shortSide * 0.024 * b)

        var result = image
        result = blend(
            softLayer,
            over: result,
            mask: multiplyMasks(
                borderTierMask(
                    size: targetSize,
                    borderFrac: borderFrac,
                    artSpan: artSpan,
                    gutterSpan: gutterSpan,
                    isTop: isTop,
                    insideInFrac: 0.24,
                    insideOutFrac: 0.02,
                    outsideOutFrac: 0.18,
                    peakAlpha: 0.95
                ),
                contentXMask
            )
        )
        result = blend(
            mediumLayer,
            over: result,
            mask: multiplyMasks(
                borderTierMask(
                    size: targetSize,
                    borderFrac: borderFrac,
                    artSpan: artSpan,
                    gutterSpan: gutterSpan,
                    isTop: isTop,
                    insideInFrac: 0.28,
                    insideOutFrac: 0.00,
                    outsideOutFrac: 0.34,
                    peakAlpha: min(0.92, 0.90 * b)
                ),
                contentXMask
            )
        )
        result = blend(
            heavyLayer,
            over: result,
            mask: multiplyMasks(
                borderTierMask(
                    size: targetSize,
                    borderFrac: borderFrac,
                    artSpan: artSpan,
                    gutterSpan: gutterSpan,
                    isTop: isTop,
                    insideInFrac: 0.18,
                    insideOutFrac: 0.00,
                    outsideOutFrac: 0.16,
                    peakAlpha: min(1, 0.95 * b)
                ),
                contentXMask
            )
        )
        return result
    }

    /// Dual seal (outer border + inner handoff) so the last high-frequency edge
    /// cannot punch through the haze, regardless of cover content.
    private static func applyBorderSeal(
        _ image: CIImage,
        shortSide: CGFloat,
        targetSize: CGSize,
        artSpan: CGFloat,
        borderFrac: CGFloat,
        gutterSpan: CGFloat,
        isTop: Bool,
        boost: CGFloat
    ) -> CIImage {
        let b = clamp(boost, lower: 1, upper: 1.4)
        var composed = image

        let outerRadius = shortSide * 0.012 * b
        let outerMask = borderTierMask(
            size: targetSize,
            borderFrac: borderFrac,
            artSpan: artSpan,
            gutterSpan: gutterSpan,
            isTop: isTop,
            insideInFrac: 0.22,
            insideOutFrac: 0.04,
            outsideOutFrac: 0.30,
            peakAlpha: 0.88
        )
        composed = blend(
            blur(composed, radius: outerRadius),
            over: composed,
            mask: outerMask
        ).cropped(to: CGRect(origin: .zero, size: targetSize))

        let innerRadius = shortSide * 0.005
        let innerMask = borderTierMask(
            size: targetSize,
            borderFrac: borderFrac,
            artSpan: artSpan,
            gutterSpan: gutterSpan,
            isTop: isTop,
            insideInFrac: 0.36,
            insideOutFrac: 0.02,
            outsideOutFrac: 0.12,
            peakAlpha: 0.55
        )
        composed = blend(
            blur(composed, radius: innerRadius),
            over: composed,
            mask: innerMask
        ).cropped(to: CGRect(origin: .zero, size: targetSize))

        return composed
    }

    private static func estimateFocalPoint(in source: CIImage) -> CGPoint {
        let sampleSize = 48
        let sourceExtent = source.extent
        let scale = min(CGFloat(sampleSize) / sourceExtent.width, CGFloat(sampleSize) / sourceExtent.height)
        let sample = source
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .cropped(to: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        var pixels = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            context.render(
                sample,
                toBitmap: baseAddress,
                rowBytes: sampleSize * 4,
                bounds: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }

        var weightedX: CGFloat = 0
        var weightedY: CGFloat = 0
        var totalWeight: CGFloat = 0

        for y in 1..<(sampleSize - 1) {
            for x in 1..<(sampleSize - 1) {
                let index = (y * sampleSize + x) * 4
                let luminance = pixelLuminance(pixels, at: index)
                let left = pixelLuminance(pixels, at: index - 4)
                let right = pixelLuminance(pixels, at: index + 4)
                let above = pixelLuminance(pixels, at: index - sampleSize * 4)
                let below = pixelLuminance(pixels, at: index + sampleSize * 4)
                let edgeEnergy = abs(luminance - left) + abs(luminance - right) + abs(luminance - above) + abs(luminance - below)
                let red = CGFloat(pixels[index]) / 255
                let green = CGFloat(pixels[index + 1]) / 255
                let blue = CGFloat(pixels[index + 2]) / 255
                let saturation = max(red, green, blue) - min(red, green, blue)
                let centerBias = 0.55 + 0.45 * (1 - distanceFromCenter(x: x, y: y, size: sampleSize))
                let weight = max(0.001, (edgeEnergy * 0.72 + saturation * 0.28) * centerBias)

                weightedX += CGFloat(x) * weight
                weightedY += CGFloat(y) * weight
                totalWeight += weight
            }
        }

        guard totalWeight > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(
            x: clamp(weightedX / totalWeight / CGFloat(sampleSize), lower: 0.22, upper: 0.78),
            y: clamp(weightedY / totalWeight / CGFloat(sampleSize), lower: 0.18, upper: 0.82)
        )
    }

    private static func finish(
        _ image: CIImage,
        targetSize: CGSize,
        topDarkness: CGFloat,
        bottomDarkness: CGFloat,
        vignette: CGFloat,
        portraitDamping: Bool = true,
        gradientMidAlpha: CGFloat = 0.02
    ) -> CIImage {
        let aspectRatio = targetSize.height / max(targetSize.width, 1)
        let portraitProtection = portraitDamping ? clamp((aspectRatio - 1.1) / 1.0, lower: 0, upper: 1) : 0
        let adjustedTopDarkness = topDarkness * (1 - portraitProtection * 0.72)
        let adjustedBottomDarkness = bottomDarkness * (1 - portraitProtection * 0.72)
        let adjustedVignette = vignette * (1 - portraitProtection)
        let canvasRect = CGRect(origin: .zero, size: targetSize)
        let gradient = makeTopBottomGradient(
            size: targetSize,
            topDarkness: adjustedTopDarkness,
            bottomDarkness: adjustedBottomDarkness,
            midAlpha: gradientMidAlpha
        )
        let withGradient = canvasFilled(
            gradient.composited(over: image),
            size: targetSize
        )

        guard adjustedVignette > 0.001 else { return withGradient }
        return withGradient.applyingFilter("CIVignette", parameters: [
            kCIInputRadiusKey: min(targetSize.width, targetSize.height) * 0.78,
            kCIInputIntensityKey: adjustedVignette
        ]).cropped(to: canvasRect)
    }

    private static func aspectFill(_ image: CIImage, into size: CGSize) -> CIImage {
        let extent = image.extent
        let scale = max(size.width / extent.width, size.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rect = CGRect(
            x: scaled.extent.midX - size.width * 0.5,
            y: scaled.extent.midY - size.height * 0.5,
            width: size.width,
            height: size.height
        )
        return scaled.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
    }

    private static func aspectFitRect(_ imageSize: CGSize, in container: CGRect) -> CGRect {
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: container.midX - size.width * 0.5,
            y: container.midY - size.height * 0.5,
            width: size.width,
            height: size.height
        )
    }

    private static func portraitContentRect(
        _ targetSize: CGSize,
        widthRatio: CGFloat,
        verticalCenter: CGFloat
    ) -> CGRect {
        let width = targetSize.width * widthRatio
        let height = width
        return CGRect(
            x: (targetSize.width - width) * 0.5,
            y: targetSize.height * verticalCenter - height * 0.5,
            width: width,
            height: height
        )
    }

    private static func verticallyMirroredExtension(
        _ source: CIImage,
        contentRect: CGRect,
        targetSize: CGSize
    ) -> CIImage {
        let center = place(source, in: contentRect)
        let below = center.transformed(by: CGAffineTransform(
            a: 1, b: 0, c: 0, d: -1,
            tx: 0,
            ty: contentRect.minY * 2
        ))
        let above = center.transformed(by: CGAffineTransform(
            a: 1, b: 0, c: 0, d: -1,
            tx: 0,
            ty: contentRect.maxY * 2
        ))

        return canvasFilled(
            center.composited(over: above.composited(over: below)),
            size: targetSize
        )
    }

    private static func place(_ image: CIImage, in rect: CGRect) -> CIImage {
        let extent = image.extent
        let scale = min(rect.width / extent.width, rect.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let x = rect.midX - scaled.extent.width * 0.5 - scaled.extent.minX
        let y = rect.midY - scaled.extent.height * 0.5 - scaled.extent.minY
        return scaled.transformed(by: CGAffineTransform(translationX: x, y: y))
    }

    private static func resizeToCanvas(_ image: CIImage, size: CGSize) -> CIImage {
        let extent = image.extent
        let scaled = image.transformed(by: CGAffineTransform(
            scaleX: size.width / extent.width,
            y: size.height / extent.height
        ))
        return scaled.transformed(by: CGAffineTransform(
            translationX: -scaled.extent.minX,
            y: -scaled.extent.minY
        )).cropped(to: CGRect(origin: .zero, size: size))
    }

    private static func mirrored(_ image: CIImage) -> CIImage {
        let extent = image.extent
        return image.transformed(by: CGAffineTransform(translationX: extent.maxX, y: 0).scaledBy(x: -1, y: 1))
    }

    private static func blur(_ image: CIImage, radius: CGFloat) -> CIImage {
        image
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: image.extent)
    }

    private static func solidBackground(size: CGSize) -> CIImage {
        CIImage(color: CIColor(red: 0.004, green: 0.018, blue: 0.032, alpha: 1))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    private static func canvasFilled(_ image: CIImage, size: CGSize) -> CIImage {
        let canvasRect = CGRect(origin: .zero, size: size)
        return image
            .cropped(to: canvasRect)
            .composited(over: solidBackground(size: size))
            .cropped(to: canvasRect)
    }

    private static func portraitComposite(
        background: CIImage,
        foreground: CIImage,
        mask: CIImage,
        targetSize: CGSize
    ) -> CIImage {
        let canvasRect = CGRect(origin: .zero, size: targetSize)
        guard let backgroundCGImage = context.createCGImage(background.cropped(to: canvasRect), from: canvasRect),
              let foregroundCGImage = context.createCGImage(foreground.cropped(to: canvasRect), from: canvasRect),
              let maskCGImage = context.createCGImage(mask.cropped(to: canvasRect), from: canvasRect) else {
            return background.cropped(to: canvasRect)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let graphicsContext = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return background.cropped(to: canvasRect)
        }

        graphicsContext.interpolationQuality = .high
        graphicsContext.draw(backgroundCGImage, in: canvasRect)

        graphicsContext.saveGState()
        graphicsContext.clip(to: canvasRect, mask: maskCGImage)
        graphicsContext.draw(foregroundCGImage, in: canvasRect)
        graphicsContext.restoreGState()

        guard let outputCGImage = graphicsContext.makeImage() else {
            return background.cropped(to: canvasRect)
        }
        return CIImage(cgImage: outputCGImage)
    }

    private static func opacity(_ image: CIImage, value: CGFloat) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: value)
        ])
    }

    private static func blend(_ foreground: CIImage, over background: CIImage, mask: CIImage) -> CIImage {
        let filter = CIFilter.blendWithMask()
        filter.inputImage = foreground
        filter.backgroundImage = background
        filter.maskImage = mask
        return filter.outputImage ?? background
    }

    private static func featheredRectangleMask(size: CGSize, rect: CGRect, feather: CGFloat) -> CIImage {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(rect)

        guard let maskImage = context.makeImage() else {
            return CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        }

        return CIImage(cgImage: maskImage)
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: feather])
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    private static func makeTopBottomGradient(
        size: CGSize,
        topDarkness: CGFloat,
        bottomDarkness: CGFloat,
        midAlpha: CGFloat = 0.02
    ) -> CIImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        let colors = [
            CGColor(red: 0.005, green: 0.015, blue: 0.025, alpha: topDarkness),
            CGColor(red: 0.002, green: 0.008, blue: 0.018, alpha: midAlpha),
            CGColor(red: 0.002, green: 0.008, blue: 0.018, alpha: bottomDarkness)
        ] as CFArray
        let locations: [CGFloat] = [0, 0.46, 1]
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations)!
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: size.height),
            end: CGPoint(x: 0, y: 0),
            options: []
        )
        return CIImage(cgImage: context.makeImage()!)
    }

    private static func render(_ image: CIImage, size: CGSize) -> CGImage? {
        let rect = CGRect(origin: .zero, size: size)
        return context.createCGImage(image.cropped(to: rect), from: rect)
    }

    private static func pixelLuminance(_ pixels: [UInt8], at index: Int) -> CGFloat {
        let red = CGFloat(pixels[index]) / 255
        let green = CGFloat(pixels[index + 1]) / 255
        let blue = CGFloat(pixels[index + 2]) / 255
        return red * 0.2126 + green * 0.7152 + blue * 0.0722
    }

    private static func distanceFromCenter(x: Int, y: Int, size: Int) -> CGFloat {
        let center = CGFloat(size - 1) * 0.5
        let dx = (CGFloat(x) - center) / center
        let dy = (CGFloat(y) - center) / center
        return min(1, sqrt(dx * dx + dy * dy) / 1.4142)
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
