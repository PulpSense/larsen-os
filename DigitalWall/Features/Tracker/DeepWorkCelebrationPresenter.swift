import AppKit
import SwiftUI

@MainActor
final class DeepWorkCelebrationPresenter {
    static let shared = DeepWorkCelebrationPresenter()

    private let overlay = FullScreenOverlayController()

    private init() {}

    func present(hours: Int, streak: Int, hideApplicationOnDismiss: Bool) {
        guard let milestone = DeepWorkCelebrationMilestone.forHours(hours) else { return }

        overlay.present(
            hideApplicationOnDismiss: hideApplicationOnDismiss,
            autoDismissAfter: .seconds(milestone == .dayWon ? 5.8 : 3.0),
            dismissOnKeyDown: { event in
                event.keyCode == 53 || event.charactersIgnoringModifiers == " "
            }
        ) { dismiss in
            if milestone == .dayWon {
                DayWonCelebrationView(streak: streak, dismiss: dismiss)
            } else {
                BonusHourCelebrationView(
                    hours: hours,
                    milestone: milestone,
                    dismiss: dismiss
                )
            }
        }
    }

    func dismiss() {
        overlay.dismiss()
    }
}

private struct DayWonCelebrationView: View {
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
                    .opacity(reduceMotion ? 0 : (impactVisible ? (impactRingVisible ? 0 : 0.9) : 0))

                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(piece.color)
                        .frame(width: piece.width, height: piece.height)
                        .rotationEffect(.degrees(burst ? piece.rotation : 0))
                        .position(
                            x: proxy.size.width * (burst ? piece.endX : piece.startX),
                            y: proxy.size.height * (burst ? piece.endY : 0.84)
                        )
                        .opacity(reduceMotion ? 0 : (impactVisible && !burst ? 1 : 0))
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
                        .opacity(reduceMotion ? 0 : (sparksReady && !streakVisible ? 0.95 : 0))
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
        if reduceMotion {
            impactVisible = true
            copyVisible = true
            streakVisible = true
            try? await Task.sleep(for: .milliseconds(5_100))
            fading = true
            return
        }

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

private struct BonusHourCelebrationView: View {
    let hours: Int
    let milestone: DeepWorkCelebrationMilestone
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false
    @State private var effectActive = false
    @State private var fading = false

    private var accent: Color { DeepWorkVisuals.earnedColor(for: hours) }
    private var configuration: DeepWorkCelebrationConfiguration {
        milestone.configuration(hours: hours)
    }

    var body: some View {
        GeometryReader { proxy in
            let shortestSide = min(proxy.size.width, proxy.size.height)
            let effectSize = min(660, shortestSide * 0.72)
            let contentScale = min(
                1.7,
                max(1, min(proxy.size.width / 1_600, proxy.size.height / 900))
            )

            ZStack {
                LinearGradient(
                    colors: [
                        .black.opacity(0.90),
                        accent.opacity(0.27),
                        Color.digitalWallFlame.opacity(milestone == .keepBuilding ? 0.22 : 0.08),
                        .black.opacity(0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [accent.opacity(effectActive ? 0.44 : 0.10), .clear],
                    center: .center,
                    startRadius: 10,
                    endRadius: shortestSide * 0.58
                )
                .scaleEffect(effectActive ? 1.18 : 0.48)

                milestoneEffect(size: effectSize)

                ForEach(0..<(reduceMotion ? 0 : configuration.particleCount), id: \.self) { index in
                    let angle = Double(index) / Double(max(1, configuration.particleCount)) * Double.pi * 2
                    let distance = effectSize * (0.28 + CGFloat((index * 37) % 31) / 100)
                    Circle()
                        .fill(index.isMultiple(of: 4) ? Color.digitalWallFlame : accent)
                        .frame(width: CGFloat(4 + (index * 7) % 8), height: CGFloat(4 + (index * 7) % 8))
                        .shadow(color: accent.opacity(0.85), radius: 7)
                        .offset(
                            x: effectActive ? CGFloat(cos(angle)) * distance : 0,
                            y: effectActive ? CGFloat(sin(angle)) * distance * 0.68 : 0
                        )
                        .opacity(effectActive ? 0 : 0.95)
                        .animation(
                            .easeOut(duration: reduceMotion ? 0.01 : 0.85 + Double(index % 5) * 0.08)
                                .delay(reduceMotion ? 0 : Double(index % 7) * 0.025),
                            value: effectActive
                        )
                }

                VStack(spacing: 12) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 76, weight: .black))
                        .foregroundStyle(Color.digitalWallFlame)
                        .frame(width: 154, height: 154)
                        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 38, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 38, style: .continuous)
                                .stroke(accent.opacity(0.65), lineWidth: 2)
                        }
                        .shadow(color: accent.opacity(0.72), radius: 34)
                        .symbolEffect(.bounce, value: entered)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(hours)")
                            .font(.system(size: 106, weight: .black, design: .rounded))
                            .monospacedDigit()
                        Text("H")
                            .font(.system(size: 50, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Text(configuration.title)
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .tracking(2.2)
                        .foregroundStyle(accent)
                        .shadow(color: accent.opacity(0.65), radius: 20)

                    Text(configuration.detail)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))

                    if milestone == .keepBuilding {
                        progressPips
                            .padding(.top, 8)
                    }
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .scaleEffect(contentScale * (entered ? 1 : 0.62))
                .opacity(entered && !fading ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: dismiss)
        }
        .ignoresSafeArea()
        .task { await runSequence() }
    }

    @ViewBuilder
    private func milestoneEffect(size: CGFloat) -> some View {
        switch milestone {
        case .bonusHour:
            orbitTrails(count: 1, size: size)
        case .momentum:
            orbitTrails(count: 2, size: size)
        case .unstoppable:
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    Circle()
                        .stroke(accent.opacity(0.72 - Double(ring) * 0.16), lineWidth: CGFloat(5 - ring))
                        .frame(width: size * (0.42 + CGFloat(ring) * 0.18))
                        .scaleEffect(reduceMotion ? 1 : (effectActive ? 1.35 : 0.38))
                        .opacity(reduceMotion ? 0.72 : (effectActive ? 0 : 0.9))
                        .animation(
                            .easeOut(duration: reduceMotion ? 0.01 : 1.0)
                                .delay(reduceMotion ? 0 : Double(ring) * 0.10),
                            value: effectActive
                        )
                }
            }
        case .doubleGoal:
            ZStack {
                ForEach(0..<20, id: \.self) { ray in
                    Capsule()
                        .fill(ray.isMultiple(of: 3) ? Color.digitalWallFlame : accent)
                        .frame(width: reduceMotion ? size * 0.12 : (effectActive ? size * 0.18 : size * 0.04), height: 7)
                        .offset(x: reduceMotion ? size * 0.34 : (effectActive ? size * 0.42 : size * 0.18))
                        .rotationEffect(.degrees(Double(ray) * 18))
                        .opacity(reduceMotion ? 0.72 : (effectActive ? 0 : 0.92))
                        .animation(
                            .easeOut(duration: reduceMotion ? 0.01 : 0.82)
                                .delay(reduceMotion ? 0 : Double(ray % 4) * 0.025),
                            value: effectActive
                        )
                }
            }
        case .keepBuilding:
            orbitTrails(count: 3, size: size)
        case .dayWon:
            EmptyView()
        }
    }

    private func orbitTrails(count: Int, size: CGFloat) -> some View {
        ZStack {
            ForEach(0..<count, id: \.self) { orbit in
                Circle()
                    .trim(from: 0.04, to: 0.36)
                    .stroke(
                        AngularGradient(
                            colors: [.clear, accent.opacity(0.45), .white, accent],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(
                        width: size * (0.62 + CGFloat(orbit) * 0.13),
                        height: size * (0.62 + CGFloat(orbit) * 0.13)
                    )
                    .rotationEffect(.degrees(
                        effectActive
                            ? 300 + Double(orbit) * 150
                            : -80 + Double(orbit) * 150
                    ))
                    .shadow(color: accent.opacity(0.88), radius: 12)
                    .animation(
                        .easeOut(duration: reduceMotion ? 0.01 : 1.25 - Double(orbit) * 0.12),
                        value: effectActive
                    )
            }
        }
    }

    private var progressPips: some View {
        let extraHours = max(1, hours - 8)
        let level = (extraHours - 1) / 7 + 1
        let filledPips = (extraHours - 1) % 7 + 1

        return VStack(spacing: 9) {
            HStack(spacing: 12) {
                ForEach(0..<7, id: \.self) { index in
                    Circle()
                        .fill(index < filledPips ? accent : .clear)
                        .frame(width: 11, height: 11)
                        .overlay {
                            Circle().stroke(accent.opacity(0.7), lineWidth: 1.5)
                        }
                        .shadow(color: accent.opacity(0.75), radius: 6)
                }
            }

            Text("LEVEL \(level)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(accent.opacity(0.82))
        }
    }

    @MainActor
    private func runSequence() async {
        if reduceMotion {
            entered = true
            try? await Task.sleep(for: .milliseconds(2_400))
            fading = true
            return
        }

        withAnimation(
            .spring(response: 0.48, dampingFraction: 0.62)
        ) {
            entered = true
        }

        try? await Task.sleep(for: .milliseconds(90))
        effectActive = true

        try? await Task.sleep(for: .milliseconds(2_050))
        withAnimation(.easeInOut(duration: 0.42)) {
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
            let distance = 0.12 + Double(particleFraction(index * 31)) * 0.26
            return CelebrationSpark(
                id: index,
                endX: 0.5 + CGFloat(cos(angle) * distance),
                endY: 0.64 + CGFloat(sin(angle) * distance * 0.62),
                size: 3 + particleFraction(index * 19) * 7,
                delay: Double(particleFraction(index * 17) * 0.22),
                duration: Double(0.85 + particleFraction(index * 43) * 0.65),
                color: colors[index % colors.count]
            )
        }
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
            let horizontal = particleFraction(index * 47 + 11)
            let vertical = particleFraction(index * 71 + 7)
            return ConfettiPiece(
                id: index,
                startX: side,
                endX: 0.05 + horizontal * 0.9,
                endY: -0.12 + vertical * 1.05,
                width: 5 + particleFraction(index * 19) * 8,
                height: 10 + particleFraction(index * 31) * 13,
                rotation: Double(240 + particleFraction(index * 59) * 1_080),
                delay: Double(particleFraction(index * 23) * 0.32),
                duration: Double(1.65 + particleFraction(index * 43) * 0.9),
                color: colors[index % colors.count]
            )
        }
    }
}

private func particleFraction(_ seed: Int) -> CGFloat {
    CGFloat((seed * 37 + 17) % 101) / 100
}
