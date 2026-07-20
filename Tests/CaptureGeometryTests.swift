import Foundation
import CoreGraphics

var failures = 0
func expect(_ cond: Bool, _ name: String) {
    if cond { print("PASS \(name)") } else { failures += 1; print("FAIL \(name)") }
}
func approx(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 0.01) -> Bool { abs(a - b) <= tol }

@main
struct TestRunner {
    static func main() {
        // maxZoom derives from format width, clamped to [1, 6]
        expect(approx(CaptureGeometry.maxZoom(formatWidth: 1920), 3.0), "maxZoom 1920 -> 3x")
        expect(approx(CaptureGeometry.maxZoom(formatWidth: 4032), 6.0), "maxZoom 4032 clamps to 6x")
        expect(approx(CaptureGeometry.maxZoom(formatWidth: 640), 1.0), "maxZoom 640 -> 1x")
        expect(approx(CaptureGeometry.maxZoom(formatWidth: 0), 1.0), "maxZoom 0 -> 1x safe")

        // cropRect: zoom only — centered 1/zoom window
        let full = CaptureGeometry.cropRect(imageSize: CGSize(width: 1920, height: 1080), zoom: 2, aspect: nil)
        expect(full == CGRect(x: 480, y: 270, width: 960, height: 540), "cropRect 2x centered")

        // cropRect: no zoom, no aspect — full frame
        let none = CaptureGeometry.cropRect(imageSize: CGSize(width: 1920, height: 1080), zoom: 1, aspect: nil)
        expect(none == CGRect(x: 0, y: 0, width: 1920, height: 1080), "cropRect identity")

        // cropRect: square aspect from 16:9
        let sq = CaptureGeometry.cropRect(imageSize: CGSize(width: 1920, height: 1080), zoom: 1, aspect: 1)
        expect(sq == CGRect(x: 420, y: 0, width: 1080, height: 1080), "cropRect 1:1")

        // cropRect: 16:9 aspect from 4:3 sensor
        let wide = CaptureGeometry.cropRect(imageSize: CGSize(width: 1600, height: 1200), zoom: 1, aspect: 16.0/9.0)
        expect(approx(wide.width, 1600) && approx(wide.height, 900) && approx(wide.origin.y, 150), "cropRect 16:9 from 4:3")

        // cropRect: zoom + aspect compose
        let combo = CaptureGeometry.cropRect(imageSize: CGSize(width: 1920, height: 1080), zoom: 2, aspect: 1)
        expect(combo == CGRect(x: 690, y: 270, width: 540, height: 540), "cropRect 2x + 1:1")

        // cropRect: degenerate input is safe
        expect(CaptureGeometry.cropRect(imageSize: .zero, zoom: 2, aspect: 1) == .zero, "cropRect zero size safe")

        // cropRect: odd dimensions stay integral and in-bounds
        let odd = CaptureGeometry.cropRect(imageSize: CGSize(width: 1279, height: 719), zoom: 1.7, aspect: 4.0/3.0)
        expect(odd.width == odd.width.rounded() && odd.height == odd.height.rounded(), "cropRect integral")
        expect(odd.maxX <= 1279 && odd.maxY <= 719 && odd.minX >= 0 && odd.minY >= 0, "cropRect in bounds")

        // centeredRect: mask geometry for the preview
        let cut = CaptureGeometry.centeredRect(ratio: 1, inside: CGRect(x: 0, y: 100, width: 800, height: 450))
        expect(cut == CGRect(x: 175, y: 100, width: 450, height: 450), "centeredRect square in 16:9")

        // AspectRatio cycle
        expect(AspectRatio.full.next == .wide && AspectRatio.square.next == .full, "aspect cycle wraps")
        expect(AspectRatio.wide.ratio.map { approx($0, 16.0/9.0) } == true && AspectRatio.full.ratio == nil, "aspect ratios")

        if failures > 0 { print("\(failures) FAILURES"); exit(1) }
        print("All tests passed")
    }
}
