import SwiftUI
import AVFoundation

/// Live camera preview backed by `AVCaptureVideoPreviewLayer`.
///
/// Digital zoom is a GPU-composited `CATransform3D` scale on the preview
/// layer (macOS has no device zoom API); the matching crop is applied to
/// saved photos so preview and output agree.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    var mirrored: Bool = false
    var zoom: CGFloat = 1
    var aspectFill: Bool = true
    var onZoomDelta: ((CGFloat) -> Void)? = nil

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        if nsView.previewLayer.session !== session {
            nsView.previewLayer.session = session
        }
        apply(to: nsView)
    }

    private func apply(to view: PreviewView) {
        view.previewLayer.videoGravity = aspectFill ? .resizeAspectFill : .resizeAspect
        view.zoom = zoom
        view.onZoomDelta = onZoomDelta
        guard let conn = view.previewLayer.connection, conn.isVideoMirroringSupported else { return }
        conn.automaticallyAdjustsVideoMirroring = false
        conn.isVideoMirrored = mirrored
    }

    /// Layer-backed NSView that hosts the capture preview layer as a *sublayer*
    /// (more reliable than making it the backing layer) and keeps it sized to
    /// the view's bounds. Zoom scales the layer around its center.
    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()
        var onZoomDelta: ((CGFloat) -> Void)?

        var zoom: CGFloat = 1 {
            didSet {
                guard zoom != oldValue else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                previewLayer.transform = CATransform3DMakeScale(zoom, zoom, 1)
                CATransaction.commit()
            }
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            layer?.masksToBounds = true
            layer?.addSublayer(previewLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            // Set bounds+position (not frame) so the zoom transform composes
            // cleanly; disable implicit animations so resizing tracks crisply.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.bounds = bounds
            previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            CATransaction.commit()
        }

        override func scrollWheel(with event: NSEvent) {
            onZoomDelta?(event.scrollingDeltaY)
        }
    }
}
