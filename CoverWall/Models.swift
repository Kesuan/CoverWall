import CoreGraphics
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum DeviceProfile: String, CaseIterable, Identifiable, Hashable {
    case iPhone
    case iPad
    case mac

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .iPhone: return "device_iphone"
        case .iPad: return "device_ipad"
        case .mac: return "device_mac"
        }
    }

    var title: LocalizedStringKey {
        LocalizedStringKey(titleKey)
    }

    var localizedTitle: String {
        String(localized: String.LocalizationValue(titleKey))
    }

    var subtitle: String {
        let size = outputSize
        return "\(Int(size.width)) × \(Int(size.height))"
    }

    var outputSize: CGSize {
        switch self {
        case .iPhone: return CGSize(width: 1179, height: 2556)
        case .iPad: return CGSize(width: 1668, height: 2388)
        case .mac: return CGSize(width: 2880, height: 1800)
        }
    }

    var symbolName: String {
        switch self {
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .mac: return "laptopcomputer"
        }
    }

    static var current: DeviceProfile {
        #if os(macOS)
        return .mac
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #else
        return .iPhone
        #endif
    }
}

enum WallpaperAlgorithm: String, CaseIterable, Identifiable, Hashable {
    case smartCrop
    case mirrorBlur
    case frequencySeparation
    case blurFill

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .smartCrop: return "algo_smart_crop"
        case .mirrorBlur: return "algo_mirror_blur"
        case .frequencySeparation: return "algo_frequency_separation"
        case .blurFill: return "algo_blur_fill"
        }
    }

    var shortDescription: LocalizedStringKey {
        switch self {
        case .smartCrop: return "algo_smart_crop_desc"
        case .mirrorBlur: return "algo_mirror_blur_desc"
        case .frequencySeparation: return "algo_frequency_separation_desc"
        case .blurFill: return "algo_blur_fill_desc"
        }
    }

    var accentColor: Color {
        switch self {
        case .smartCrop: return Color(red: 0.28, green: 0.70, blue: 0.82)
        case .mirrorBlur: return Color(red: 0.48, green: 0.60, blue: 0.88)
        case .frequencySeparation: return Color(red: 0.62, green: 0.78, blue: 0.67)
        case .blurFill: return Color(red: 0.94, green: 0.64, blue: 0.38)
        }
    }
}

struct WallpaperResult: Identifiable, Hashable {
    let id = UUID()
    let algorithm: WallpaperAlgorithm
    let image: CGImage

    static func == (lhs: WallpaperResult, rhs: WallpaperResult) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
