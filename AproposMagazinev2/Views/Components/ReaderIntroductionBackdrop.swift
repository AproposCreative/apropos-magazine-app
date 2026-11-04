import SwiftUI

/// One decorative layer with stable identity across introduction steps. Only
/// visible, active time advances its phase; changing the foreground never does.
struct ReaderIntroductionBackdrop: View {
    let isPresented: Bool
    var isArtwork = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var clock = ReaderIntroductionBackdropClock()

    private var moves: Bool {
        isVisible && isPresented && scenePhase == .active && !reduceMotion && !reduceTransparency
    }
    private var strength: Double {
        if reduceTransparency || contrast == .increased { return 0.35 }
        if dynamicTypeSize.isAccessibilitySize { return 0.65 }
        return 1
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 390, 1.5)
            ZStack {
                Color.black
                // A paused schedule requests no continuing animation frames.
                // Uptime keeps wall-clock adjustments out of the visual phase.
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moves)) { _ in
                    let frame = ReaderIntroductionBackdropFrame.at(
                        elapsed: clock.elapsed(at: ProcessInfo.processInfo.systemUptime)
                    )
                    lights(frame: frame, size: geometry.size, scale: scale)
                }
                .opacity(strength)
                // This scrim never moves with the light. Its lower half stays
                // black, including behind long text and expanded controls.
                LinearGradient(stops: isArtwork ? [
                    .init(color: .black.opacity(0.12), location: 0),
                    .init(color: .black.opacity(0.05), location: 0.6),
                    .init(color: .black.opacity(0.4), location: 1)
                ] : [
                    .init(color: .black.opacity(0.36), location: 0),
                    .init(color: .black.opacity(0.30), location: 0.24),
                    .init(color: .black.opacity(0.55), location: 0.42),
                    .init(color: .black, location: 0.66)
                ], startPoint: .top, endPoint: .bottom)
            }
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // Lifecycle updates are the only state writes; individual frames only
        // read the clock. The clock remains owned by this persistent backdrop.
        .onAppear {
            isVisible = true
            clock.setRunning(isPresented && scenePhase == .active && !reduceMotion && !reduceTransparency,
                             at: ProcessInfo.processInfo.systemUptime)
        }
        .onChange(of: moves) { _, running in
            clock.setRunning(running, at: ProcessInfo.processInfo.systemUptime)
        }
        .onDisappear {
            clock.setRunning(false, at: ProcessInfo.processInfo.systemUptime)
            isVisible = false
        }
    }

    private func lights(frame: ReaderIntroductionBackdropFrame, size: CGSize, scale: CGFloat) -> some View {
        ZStack {
            // Existing provisional Apropos blue, spread broadly enough that
            // the independent white field can move through it without an edge.
            Ellipse()
                .fill(RadialGradient(stops: [
                    .init(color: Color(red: 0.12, green: 0.47, blue: 0.93), location: 0),
                    .init(color: Color(red: 0.07, green: 0.40, blue: 0.93), location: 0.30),
                    .init(color: Color(red: 0.02, green: 0.26, blue: 0.68).opacity(0.75), location: 0.62),
                    .init(color: .clear, location: 1)
                ], center: .center, startRadius: 0, endRadius: 290 * scale))
                .frame(width: 560 * scale, height: 360 * scale)
                .blur(radius: 38 * scale)
                .rotationEffect(.degrees(frame.blueRotation))
                .position(x: size.width * 0.45 + frame.blueOffset.width * scale,
                          y: (isArtwork ? size.height * 0.44 : min(size.height * 0.24, 210 * scale)) + frame.blueOffset.height * scale)

            Ellipse()
                .fill(RadialGradient(stops: [
                    .init(color: .white.opacity(0.68), location: 0),
                    .init(color: .white.opacity(0.42), location: 0.24),
                    .init(color: .white.opacity(0.12), location: 0.58),
                    .init(color: .clear, location: 1)
                ], center: .center, startRadius: 0, endRadius: 215 * scale))
                .frame(width: 420 * scale, height: 180 * scale)
                .blur(radius: 30 * scale)
                .rotationEffect(.degrees(frame.whiteRotation))
                .opacity(0.72)
                .position(x: size.width * 0.50 + frame.whiteOffset.width * scale,
                          y: (isArtwork ? size.height * 0.54 : min(size.height * 0.29, 250 * scale)) + frame.whiteOffset.height * scale)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// SDK-free active-time clock. Repeated foreground updates do not restart it,
/// and paused time is excluded so resuming never jumps to an unseen phase.
struct ReaderIntroductionBackdropClock {
    private var accumulated: TimeInterval = 0
    private var startedAt: TimeInterval?

    mutating func setRunning(_ running: Bool, at time: TimeInterval) {
        if running {
            if startedAt == nil { startedAt = time }
        } else if startedAt != nil {
            accumulated = elapsed(at: time)
            startedAt = nil
        }
    }

    func elapsed(at time: TimeInterval) -> TimeInterval {
        accumulated + (startedAt.map { max(0, time - $0) } ?? 0)
    }
}

/// Separate smooth paths make motion visible without pulsing brightness or
/// moving the text. Values use a 390pt canvas and scale with the actual width.
struct ReaderIntroductionBackdropFrame {
    let blueOffset: CGSize
    let whiteOffset: CGSize
    let blueRotation: Double
    let whiteRotation: Double

    static func at(elapsed: TimeInterval) -> Self {
        let blue = elapsed * 2 * .pi / 28
        let white = elapsed * 2 * .pi / 36 + 1.7
        return Self(
            blueOffset: CGSize(width: sin(blue) * 68, height: cos(blue) * 42),
            whiteOffset: CGSize(width: sin(white) * 94, height: cos(white) * 52),
            blueRotation: -27 + sin(blue) * 8,
            whiteRotation: -24 + cos(white) * 12
        )
    }
}
