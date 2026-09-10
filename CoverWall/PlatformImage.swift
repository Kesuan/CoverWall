import CoreGraphics
import SwiftUI

#if canImport(UIKit)
import UIKit

struct PlatformImage: View {
    let cgImage: CGImage

    var body: some View {
        Image(uiImage: UIImage(cgImage: cgImage))
            .resizable()
    }
}
#elseif canImport(AppKit)
import AppKit

struct PlatformImage: View {
    let cgImage: CGImage

    var body: some View {
        Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
            .resizable()
    }
}
#endif
