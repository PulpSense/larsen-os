import AppKit
import SwiftUI

@MainActor
final class DeepWorkCelebrationPresenter {
    static let shared = DeepWorkCelebrationPresenter()

    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var dismissalTask: Task<Void, Never>?
    private var hideApplicationOnDismiss = false

    private init() {}

    func present(streak: Int, hideApplicationOnDismiss: Bool) {
        dismiss(hideApplication: false)

        let screen = screenUnderPointer() ?? NSScreen.main
        guard let screen else { return }

        let panel = CelebrationPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: DeepWorkCelebrationView(streak: streak) {
            DeepWorkCelebrationPresenter.shared.dismiss()
        })
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.setFrame(screen.frame, display: true)
        self.panel = panel
        self.hideApplicationOnDismiss = hideApplicationOnDismiss
        panel.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 || event.charactersIgnoringModifiers == " " {
                self?.dismiss()
                return nil
            }
            return event
        }

        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5.8))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismiss(hideApplication: hideApplicationOnDismiss)
    }

    private func dismiss(hideApplication: Bool) {
        dismissalTask?.cancel()
        dismissalTask = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
        hideApplicationOnDismiss = false

        if hideApplication {
            DispatchQueue.main.async {
                NSApp.hide(nil)
            }
        }
    }

    private func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
    }
}

private final class CelebrationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct DeepWorkCelebrationView: View {
    let streak: Int
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var impactVisible = false
    @State private var burst = false
    @State private var copyVisible = false
    @State private var streakVisible = false
    @State private var sparksReady = false
    @State private var flashVisible = false
    @State private var impactRingVisible = false
    @State private var fading = false

    private let pieces = ConfettiPiece.makePieces(count: 220)
    private let sparks = CelebrationSpark.makePieces(count: 54)

    var body: some View {
        GeometryReader { proxy in
            let contentScale = min(
                1.75,
                max(1, min(proxy.size.width / 1_600, proxy.size.height / 900))
            )

            ZStack {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.76),
                        Color.indigo.opacity(0.76),
                        Color.black.opacity(0.82)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        (streakVisible ? Color.digitalWallFlame : .white).opacity(0.34),
                        (streakVisible ? Color.digitalWallFlame : .indigo).opacity(0.10),
                        .clear
                    ],
                    center: .center,
                    startRadius: 20,
                    endRadius: min(proxy.size.width, proxy.size.height) * 0.58
                )
                .scaleEffect(streakVisible ? 1.35 : (copyVisible ? 1.05 : 0.35))
                .opacity(copyVisible ? 1 : 0)

                Color.white
                    .opacity(flashVisible ? 0.72 : 0)

                Circle()
                    .stroke(Color.white.opacity(0.82), lineWidth: 7)
                    .frame(width: 150, height: 150)
                    .scaleEffect(impactRingVisible ? 4.8 : 0.45)
                    .opacity(impactVisible ? (impactRingVisible ? 0 : 0.9) : 0)

                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(piece.color)
                        .frame(width: piece.width, height: piece.height)
                        .rotationEffect(.degrees(burst ? piece.rotation : 0))
                        .position(
                            x: proxy.size.width * (burst ? piece.endX : piece.startX),
                            y: proxy.size.height * (burst ? piece.endY : 0.84)
                        )
                        .opacity(impactVisible && !burst ? 1 : 0)
                        .animation(
                            .easeOut(duration: piece.duration).delay(piece.delay),
                            value: burst
                        )
                }

                ForEach(sparks) { spark in
                    Circle()
                        .fill(spark.color)
                        .frame(width: spark.size, height: spark.size)
                        .shadow(color: spark.color.opacity(0.8), radius: 6)
                        .position(
                            x: proxy.size.width * (streakVisible ? spark.endX : 0.5),
                            y: proxy.size.height * (streakVisible ? spark.endY : 0.64)
                        )
                        .scaleEffect(streakVisible ? 0.15 : 1)
                        .opacity(sparksReady && !streakVisible ? 0.95 : 0)
                        .animation(
                            .easeOut(duration: spark.duration).delay(spark.delay),
                            value: streakVisible
                        )
                }

                VStack(spacing: 16) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 78, weight: .black, design: .rounded))
                        .foregroundStyle(.indigo)
                        .frame(width: 158, height: 158)
                        .background(.white, in: Circle())
                        .shadow(color: .black.opacity(0.34), radius: 34, y: 16)
                        .rotationEffect(.degrees(impactVisible ? 0 : -14))
                        .scaleEffect(impactVisible ? 1 : 2.4)
                        .offset(y: impactVisible ? 0 : -340)
                        .opacity(impactVisible ? 1 : 0)

                    Text("DAY WON")
                        .font(.system(size: 78, weight: .black, design: .rounded))
                        .tracking(3)
                        .shadow(color: .indigo.opacity(0.7), radius: 28)
                        .scaleEffect(copyVisible ? 1 : 0.78)
                        .opacity(copyVisible ? 1 : 0)

                    Text("4 hours of deep work")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .offset(y: copyVisible ? 0 : 18)
                        .opacity(copyVisible ? 1 : 0)

                    HStack(spacing: 14) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 52, weight: .black))
                            .symbolEffect(.bounce, value: streakVisible)

                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(streak)")
                                .font(.system(size: 48, weight: .black, design: .rounded))
                                .monospacedDigit()
                            Text("\(streak == 1 ? "DAY" : "DAYS") STREAK")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .tracking(1.4)
                        }
                    }
                    .foregroundStyle(Color.digitalWallFlame)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 13)
                    .background(.black.opacity(0.32), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.digitalWallFlame.opacity(0.52), lineWidth: 1.5)
                    }
                    .shadow(color: Color.digitalWallFlame.opacity(0.52), radius: 28)
                    .scaleEffect(streakVisible ? 1 : 0.2)
                    .opacity(streakVisible ? 1 : 0)
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .scaleEffect(contentScale)
                .offset(y: streakVisible ? -6 : 0)
                .opacity(impactVisible && !fading ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: dismiss)
        }
        .ignoresSafeArea()
        .task {
            await runSequence()
        }
    }

    @MainActor
    private func runSequence() async {
        let impactAnimation = reduceMotion
            ? Animation.easeOut(duration: 0.01)
            : .spring(response: 0.48, dampingFraction: 0.58)

        withAnimation(impactAnimation) {
            impactVisible = true
            flashVisible = true
        }

        try? await Task.sleep(for: .milliseconds(reduceMotion ? 1 : 15))
        withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.65)) {
            impactRingVisible = true
        }

        try? await Task.sleep(for: .milliseconds(reduceMotion ? 10 : 55))
        burst = true
        withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.38)) {
            flashVisible = false
        }

        try? await Task.sleep(for: .milliseconds(reduceMotion ? 10 : 520))
        withAnimation(reduceMotion ? .easeOut(duration: 0.01) : .spring(response: 0.58, dampingFraction: 0.72)) {
            copyVisible = true
        }

        try? await Task.sleep(for: .milliseconds(reduceMotion ? 10 : 1_050))
        sparksReady = true
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 1 : 20))
        withAnimation(reduceMotion ? .easeOut(duration: 0.01) : .spring(response: 0.62, dampingFraction: 0.58)) {
            streakVisible = true
        }

        try? await Task.sleep(for: .milliseconds(reduceMotion ? 10 : 2_650))
        withAnimation(.easeInOut(duration: reduceMotion ? 0.01 : 0.58)) {
            fading = true
        }
    }
}

private struct CelebrationSpark: Identifiable {
    let id: Int
    let endX: CGFloat
    let endY: CGFloat
    let size: CGFloat
    let delay: Double
    let duration: Double
    let color: Color

    static func makePieces(count: Int) -> [CelebrationSpark] {
        let colors: [Color] = [Color.digitalWallFlame, .orange, .yellow, .white]
        return (0..<count).map { index in
            let angle = Double(index) / Double(max(1, count)) * Double.pi * 2
            let distance = 0.12 + Double(fraction(index * 31)) * 0.26
            return CelebrationSpark(
                id: index,
                endX: 0.5 + CGFloat(cos(angle) * distance),
                endY: 0.64 + CGFloat(sin(angle) * distance * 0.62),
                size: 3 + fraction(index * 19) * 7,
                delay: Double(fraction(index * 17) * 0.22),
                duration: Double(0.85 + fraction(index * 43) * 0.65),
                color: colors[index % colors.count]
            )
        }
    }

    private static func fraction(_ seed: Int) -> CGFloat {
        CGFloat((seed * 37 + 17) % 101) / 100
    }
}

private struct ConfettiPiece: Identifiable {
    let id: Int
    let startX: CGFloat
    let endX: CGFloat
    let endY: CGFloat
    let width: CGFloat
    let height: CGFloat
    let rotation: Double
    let delay: Double
    let duration: Double
    let color: Color

    static func makePieces(count: Int) -> [ConfettiPiece] {
        let colors: [Color] = [.yellow, .pink, .cyan, .mint, .orange, .white, .purple]
        return (0..<count).map { index in
            let side: CGFloat = index.isMultiple(of: 2) ? 0.08 : 0.92
            let horizontal = fraction(index * 47 + 11)
            let vertical = fraction(index * 71 + 7)
            return ConfettiPiece(
                id: index,
                startX: side,
                endX: 0.05 + horizontal * 0.9,
                endY: -0.12 + vertical * 1.05,
                width: 5 + fraction(index * 19) * 8,
                height: 10 + fraction(index * 31) * 13,
                rotation: Double(240 + fraction(index * 59) * 1_080),
                delay: Double(fraction(index * 23) * 0.32),
                duration: Double(1.65 + fraction(index * 43) * 0.9),
                color: colors[index % colors.count]
            )
        }
    }

    private static func fraction(_ seed: Int) -> CGFloat {
        CGFloat((seed * 37 + 17) % 101) / 100
    }
}
