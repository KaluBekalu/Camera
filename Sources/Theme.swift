import SwiftUI

/// Shared visual language for the app: colors, materials, and reusable
/// control styles that give the UI its modern, glassy iOS-camera feel.
enum Theme {
    static let accent = Color.yellow
    static let recording = Color(red: 1.0, green: 0.23, blue: 0.19)
    static let controlSize: CGFloat = 40
}

/// A circular translucent "glass" button used for the floating camera controls.
struct GlassCircleButton: View {
    let systemImage: String
    var active: Bool = false
    var tint: Color = .white
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? Theme.accent : tint)
                .frame(width: Theme.controlSize, height: Theme.controlSize)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(active ? 0.0 : 0.12)))
                .overlay(
                    Circle().strokeBorder(Theme.accent.opacity(active ? 0.9 : 0.0), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.25), radius: hovering ? 8 : 4, y: 2)
                .scaleEffect(hovering ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .animation(.easeInOut(duration: 0.15), value: active)
    }
}

/// A pill-shaped label used for badges (recording time, AE/AF lock, etc.).
struct GlassBadge: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = .white

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }
}

/// Rule-of-thirds grid drawn over the preview.
struct GridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                let w = geo.size.width, h = geo.size.height
                for i in 1...2 {
                    let x = w * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h))
                    let y = h * CGFloat(i) / 3
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
                }
            }
            .stroke(.white.opacity(0.35), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}
