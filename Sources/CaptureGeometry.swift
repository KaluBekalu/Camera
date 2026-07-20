import Foundation
import CoreGraphics

/// Selectable output aspect ratios. `full` means the sensor's native frame.
enum AspectRatio: String, CaseIterable, Identifiable {
    case full = "full"
    case wide = "16:9"
    case classic = "4:3"
    case square = "1:1"

    var id: String { rawValue }

    /// width / height; nil means keep the native frame.
    var ratio: CGFloat? {
        switch self {
        case .full: return nil
        case .wide: return 16.0 / 9.0
        case .classic: return 4.0 / 3.0
        case .square: return 1
        }
    }

    var label: String { self == .full ? "Full" : rawValue }

    var next: AspectRatio {
        let all = AspectRatio.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// Pure geometry for digital zoom and aspect-ratio cropping. macOS exposes no
/// device zoom API (`videoZoomFactor` is unavailable), so zoom is a centered
/// crop computed here and applied to the preview transform and saved photos.
enum CaptureGeometry {

    /// Max digital zoom for a capture format, derived from its pixel width so
    /// the cropped output never drops below `minOutputWidth`. Clamped to [1, 6].
    static func maxZoom(formatWidth: CGFloat, minOutputWidth: CGFloat = 640) -> CGFloat {
        guard formatWidth > 0 else { return 1 }
        return min(6, max(1, formatWidth / minOutputWidth))
    }

    /// Centered crop rect in image pixel space for a zoom factor and optional
    /// target aspect (width/height). Integral and guaranteed within bounds.
    static func cropRect(imageSize: CGSize, zoom: CGFloat, aspect: CGFloat?) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let z = max(1, zoom)
        var w = imageSize.width / z
        var h = imageSize.height / z
        if let a = aspect, a > 0 {
            if w / h > a { w = h * a } else { h = w / a }
        }
        w.round(.down)
        h.round(.down)
        let x = ((imageSize.width - w) / 2).rounded(.down)
        let y = ((imageSize.height - h) / 2).rounded(.down)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Largest rect of the given aspect (width/height) centered inside `rect`.
    /// Used to position the preview's dimmed letterbox masks.
    static func centeredRect(ratio: CGFloat, inside rect: CGRect) -> CGRect {
        guard ratio > 0, rect.width > 0, rect.height > 0 else { return rect }
        var w = rect.width
        var h = rect.height
        if w / h > ratio { w = h * ratio } else { h = w / ratio }
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}
