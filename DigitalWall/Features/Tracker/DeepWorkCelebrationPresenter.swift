import AppKit
import SwiftUI

@MainActor
final class DeepWorkCelebrationPresenter {
    static let shared = DeepWorkCelebrationPresenter()
    private let overlay = FullScreenOverlayController()
    private init() {}

    func present(
        hours: Int, streak: Int, hideApplicationOnDismiss: Bool,
        reduceMotion: Bool? = nil, onDismiss: (() -> Void)? = nil
    ) {
        guard let milestone = DeepWorkCelebrationMilestone.forHours(hours) else { onDismiss?(); return }
        overlay.present(
            hideApplicationOnDismiss: hideApplicationOnDismiss,
            autoDismissAfter: .seconds(milestone == .dayWon ? 6.8 : 6.0),
            onDismiss: onDismiss,
            dismissOnKeyDown: { $0.keyCode == 53 || $0.charactersIgnoringModifiers == " " }
        ) { dismiss in
            MilestoneCelebrationView(hours: hours, streak: streak, milestone: milestone,
                                     reduceMotionOverride: reduceMotion, dismiss: dismiss)
        }
    }

    func dismiss() { overlay.dismiss() }
}

/// A growing planetary system rewards each earned hour with more motion and spectacle.
private struct MilestoneCelebrationView: View {
    let hours: Int
    let streak: Int
    let milestone: DeepWorkCelebrationMilestone
    let reduceMotionOverride: Bool?
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    @State private var revealed = false
    @State private var emblemVisible = false
    @State private var copyVisible = false
    @State private var detailVisible = false
    @State private var footerVisible = false

    private let ink = Color(red: 0.025, green: 0.032, blue: 0.044)
    private let paper = Color(red: 0.96, green: 0.945, blue: 0.90)
    private var configuration: DeepWorkCelebrationConfiguration { milestone.configuration(hours: hours) }
    private var intensity: PlanetaryCelebrationIntensity { .init(hours: hours) }
    private var accent: Color {
        Color(hue: max(0.07, 0.56 - Double(max(0, hours - 4)) * 0.047), saturation: 0.65, brightness: 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(1.28, min(proxy.size.width / 900, proxy.size.height / 820))
            ZStack {
                // An opaque base keeps contrast stable over every wallpaper and app.
                ink
                CosmicStarfield(intensity: intensity, accent: accent, reduceMotion: reduceMotion)
                LinearGradient(stops: [.init(color: .clear, location: 0.25),
                                       .init(color: ink.opacity(0.88), location: 0.62),
                                       .init(color: ink.opacity(0.45), location: 1)],
                               startPoint: .top, endPoint: .bottom)

                VStack(spacing: 0) {
                    PlanetarySystem(intensity: intensity, accent: accent, reduceMotion: reduceMotion)
                        .frame(width: 620, height: 300)
                        .opacity(emblemVisible ? 1 : 0)
                        .scaleEffect(reduceMotion || emblemVisible ? 1 : 0.65)
                        .padding(.bottom, 10)

                    HStack(spacing: 14) {
                        Rectangle().fill(accent.opacity(0.4)).frame(width: 30, height: 1)
                        Text(intensity.chapter)
                            .font(.system(size: 12, weight: .medium))
                            .tracking(1.2)
                        Rectangle().fill(accent.opacity(0.4)).frame(width: 30, height: 1)
                    }
                    .foregroundStyle(accent)
                    .padding(.bottom, 10)

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(hours)")
                            .font(.system(size: 90, weight: .medium, design: .rounded))
                            .tracking(-4)
                            .monospacedDigit()
                        Text("hours")
                            .font(.system(size: 22, weight: .regular, design: .serif))
                            .foregroundStyle(paper.opacity(0.55))
                            .padding(.leading, 4)
                    }
                    .padding(.bottom, 8)

                    Text(configuration.title)
                        .font(.system(size: 40, weight: .medium, design: .serif))
                        .tracking(-0.8)
                        .padding(.bottom, 16)

                    Text(configuration.detail)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(paper.opacity(0.7))
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 420)
                        .opacity(detailVisible ? 1 : 0)
                        .offset(y: reduceMotion || detailVisible ? 0 : 8)

                    footer
                        .padding(.top, 32)
                        .opacity(footerVisible ? 1 : 0)
                        .offset(y: reduceMotion || footerVisible ? 0 : 8)
                }
                .foregroundStyle(paper)
                .multilineTextAlignment(.center)
                .frame(width: 620)
                .opacity(copyVisible ? 1 : 0)
                .offset(y: reduceMotion || copyVisible ? 0 : 14)
                .scaleEffect(scale)

                VStack {
                    Spacer()
                    Text("Click anywhere or press Esc to return")
                        .font(.system(size: 11))
                        .foregroundStyle(paper.opacity(0.32))
                        .padding(.bottom, 28)
                }
                .opacity(footerVisible ? 1 : 0)
            }
            .opacity(revealed ? 1 : 0)
            .contentShape(Rectangle())
            .onTapGesture(perform: dismiss)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .task {
            do { try await runSequence() } catch { /* Dismissal cancels the remaining stages. */ }
        }
    }

    @ViewBuilder private var footer: some View {
        if milestone == .dayWon {
            HStack(spacing: 9) {
                Image(systemName: "flame")
                    .font(.system(size: 14, weight: .regular))
                Text("\(streak) \(streak == 1 ? "day" : "days") in a row")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(accent.opacity(0.055), in: Capsule())
            .overlay { Capsule().strokeBorder(accent.opacity(0.18), lineWidth: 1) }
        } else if milestone == .keepBuilding {
            let extra = max(1, hours - 8)
            VStack(spacing: 12) {
                HStack(spacing: 7) {
                    ForEach(0..<7, id: \.self) { index in
                        Capsule()
                            .fill(index <= (extra - 1) % 7 ? accent : paper.opacity(0.12))
                            .frame(width: 20, height: 2)
                    }
                }
                Text("Level \((extra - 1) / 7 + 1) · A little further, every hour")
                    .font(.system(size: 11))
                    .foregroundStyle(paper.opacity(0.5))
            }
        } else {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, accent.opacity(0.5), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 80, height: 1)
                .padding(.vertical, 16)
        }
    }

    @MainActor private func runSequence() async throws {
        if reduceMotion {
            revealed = true
            emblemVisible = true
            copyVisible = true
            detailVisible = true
            footerVisible = true
        } else {
            withAnimation(.easeOut(duration: 0.4)) { revealed = true }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.9)) { emblemVisible = true }
            try await Task.sleep(for: .milliseconds(160))
            withAnimation(.easeOut(duration: 0.8)) { copyVisible = true }
            try await Task.sleep(for: .milliseconds(260))
            withAnimation(.easeOut(duration: 0.65)) { detailVisible = true }
            try await Task.sleep(for: .milliseconds(320))
            withAnimation(.easeOut(duration: 0.65)) { footerVisible = true }
        }
        let hold = milestone == .dayWon ? 5_200 : 4_400
        try await Task.sleep(for: .milliseconds(hold))
        withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.6)) { revealed = false }
    }
}

/// All motion is elapsed-time based; Reduce Motion renders a stationary planetary scene.
private struct PlanetarySystem: View {
    let intensity: PlanetaryCelebrationIntensity
    let accent: Color
    let reduceMotion: Bool
    @State private var epoch = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 1.4 : timeline.date.timeIntervalSince(epoch)
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height * 0.5)
                let radius: CGFloat = intensity.hours >= 8 ? 86 : 80
                let glow = CGRect(x: center.x - 190, y: center.y - 190, width: 380, height: 380)
                context.fill(Path(ellipseIn: glow), with: .radialGradient(
                    Gradient(colors: [accent.opacity(0.38), accent.opacity(0.08), .clear]),
                    center: center, startRadius: radius * 0.6, endRadius: 185))

                // Back halves of the rings disappear naturally behind the solid planet.
                for ring in 0..<intensity.rings {
                    drawRing(context: &context, center: center, ring: ring, time: time, front: false)
                }
                drawMoons(context: &context, center: center, time: time, front: false)
                drawPlanet(context: &context, center: center, radius: radius, time: time)
                for ring in 0..<intensity.rings {
                    drawRing(context: &context, center: center, ring: ring, time: time, front: true)
                }
                drawMoons(context: &context, center: center, time: time, front: true)

                if intensity.hours >= 8 {
                    // A second world turns the double-goal milestone into a binary system.
                    let companion = CGPoint(x: center.x + 142, y: center.y - 74)
                    drawPlanet(context: &context, center: companion, radius: 25, time: time * 0.7)
                }
                if !reduceMotion {
                    for pulse in 0..<min(3, intensity.hours - 3) {
                        let progress = min(1, max(0, (time - Double(pulse) * 0.32) / 2.0))
                        let diameter = 170 + progress * 360
                        let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter * 0.3,
                                          width: diameter, height: diameter * 0.6)
                        context.stroke(Path(ellipseIn: rect), with: .color(accent.opacity((1 - progress) * 0.22)), lineWidth: 1)
                    }
                }
            }
        }
        .accessibilityLabel("\(intensity.chapter), \(intensity.moons) orbiting moons")
    }

    private func drawPlanet(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, time: Double) {
        let sphere = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        let light = CGPoint(x: center.x - radius * 0.48, y: center.y - radius * 0.52)
        context.fill(sphere, with: .radialGradient(
            Gradient(colors: [.white.opacity(0.95), accent, accent.opacity(0.85), Color(red: 0.015, green: 0.025, blue: 0.10), .black]),
            center: light, startRadius: 0, endRadius: radius * 1.9))
        var surface = context
        surface.clip(to: sphere)
        // Curved, drifting cloud bands give the sphere a surface and a visible terminator.
        for band in 0..<18 {
            let latitude = CGFloat(band) / 17 * radius * 2 - radius
            var path = Path()
            for sample in 0...50 {
                let x = CGFloat(sample) / 50 * radius * 2 - radius
                let wave = sin(Double(x / radius) * 4 + Double(band) * 1.7 + time * 0.18) * radius * 0.045
                let point = CGPoint(x: center.x + x, y: center.y + latitude + wave + (x * x / radius) * 0.12)
                if sample == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            surface.stroke(path, with: .color(band.isMultiple(of: 3) ? .white.opacity(0.18) : .black.opacity(0.13)),
                           lineWidth: CGFloat(2 + band % 4))
        }
        // Shadow the surface texture as well as the base shading.
        surface.fill(sphere, with: .linearGradient(
            Gradient(stops: [.init(color: .clear, location: 0.3), .init(color: .black.opacity(0.83), location: 1)]),
            startPoint: CGPoint(x: center.x - radius, y: center.y - radius),
            endPoint: CGPoint(x: center.x + radius, y: center.y + radius * 0.4)))
        context.stroke(sphere, with: .linearGradient(Gradient(colors: [.white.opacity(0.85), accent.opacity(0.7), .clear]),
                       startPoint: light, endPoint: CGPoint(x: center.x + radius, y: center.y + radius)), lineWidth: 1.5)
    }

    private func orbitalPoint(center: CGPoint, radius: CGFloat, angle: Double, tilt: Double) -> CGPoint {
        let x = cos(angle) * radius
        let y = sin(angle) * radius * 0.29
        return CGPoint(x: center.x + x * cos(tilt) - y * sin(tilt),
                       y: center.y + x * sin(tilt) + y * cos(tilt))
    }

    private func drawRing(context: inout GraphicsContext, center: CGPoint, ring: Int, time: Double, front: Bool) {
        let radius = CGFloat(143 + ring * 21)
        let tilt = -0.28 + Double(ring) * 0.16
        var path = Path()
        for step in 0...100 {
            let angle = (front ? 0 : Double.pi) + Double(step) / 100 * .pi
            let point = orbitalPoint(center: center, radius: radius, angle: angle, tilt: tilt)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        context.stroke(path, with: .color(accent.opacity(front ? 0.7 : 0.24)), lineWidth: ring == 0 ? 5 : 1.5)
        // Bright ring dust moves around the orbit, with density increasing at every hour.
        for index in 0..<(24 + min(24, intensity.hours) * 3) {
            let angle = Double(index) * 2.39996 + time * intensity.orbitSpeed * 0.18
            guard (sin(angle) >= 0) == front else { continue }
            let point = orbitalPoint(center: center, radius: radius + CGFloat(index % 3) * 3,
                                     angle: angle, tilt: tilt)
            context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: 1.6, height: 1.6)),
                         with: .color(.white.opacity(front ? 0.75 : 0.3)))
        }
    }

    private func drawMoons(context: inout GraphicsContext, center: CGPoint, time: Double, front: Bool) {
        for moon in 0..<intensity.moons {
            let radius = CGFloat(min(235, 124 + moon * 19))
            let angle = time * intensity.orbitSpeed * (1 + Double(moon) * 0.13) + Double(moon) * 2.4
            guard (sin(angle) >= 0) == front else { continue }
            let point = orbitalPoint(center: center, radius: radius, angle: angle, tilt: -0.3 + Double(moon) * 0.12)
            var trail = Path()
            for step in 0...24 {
                let p = orbitalPoint(center: center, radius: radius, angle: angle - Double(step) * 0.018,
                                     tilt: -0.3 + Double(moon) * 0.12)
                if step == 0 { trail.move(to: p) } else { trail.addLine(to: p) }
            }
            context.stroke(trail, with: .color(accent.opacity(0.36)), lineWidth: 1.5)
            let r = CGFloat(5 + moon % 3 * 2)
            context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [.white, accent, .black]),
                                               center: CGPoint(x: point.x - r * 0.4, y: point.y - r * 0.4),
                                               startRadius: 0, endRadius: r * 2))
        }
    }
}

private struct CosmicStarfield: View {
    let intensity: PlanetaryCelebrationIntensity
    let accent: Color
    let reduceMotion: Bool
    @State private var epoch = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSince(epoch)
            Canvas { context, size in
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.32)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                    Gradient(colors: [accent.opacity(0.22), .purple.opacity(0.08), .clear]),
                    center: origin, startRadius: 0, endRadius: size.width * 0.48))
                for index in 0..<intensity.stars {
                    let x = Double((index * 7919 + 101) % 1009) / 1009
                    let y = Double((index * 3571 + 53) % 997) / 997
                    let drift = time * 0.003 * intensity.orbitSpeed
                    let point = CGPoint(x: (x + drift).truncatingRemainder(dividingBy: 1) * size.width,
                                        y: y * size.height)
                    let radius = CGFloat(index.isMultiple(of: 13) ? 1.6 : 0.7)
                    let brightness = 0.22 + Double(index % 7) * 0.08
                    context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: radius * 2, height: radius * 2)),
                                 with: .color(.white.opacity(brightness)))
                    if intensity.warp > 0, !reduceMotion {
                        let phase = (time * 0.24 + x).truncatingRemainder(dividingBy: 1)
                        let length = phase * intensity.warp * 0.1
                        var streak = Path()
                        streak.move(to: point)
                        streak.addLine(to: CGPoint(x: point.x + (point.x - origin.x) * length,
                                                  y: point.y + (point.y - origin.y) * length))
                        context.stroke(streak, with: .color(accent.opacity(phase * 0.45)), lineWidth: 1)
                    }
                }
                if !reduceMotion {
                    for meteor in 0..<intensity.meteors {
                        let phase = (time * (0.22 + Double(meteor) * 0.03) + Double(meteor) * 0.27)
                            .truncatingRemainder(dividingBy: 1)
                        let x = (Double(meteor + 1) / Double(intensity.meteors + 1) + phase * 0.3)
                            .truncatingRemainder(dividingBy: 1) * size.width
                        let y = phase * size.height * 0.8
                        var streak = Path()
                        streak.move(to: CGPoint(x: x - 70, y: y - 22))
                        streak.addLine(to: CGPoint(x: x, y: y))
                        context.stroke(streak, with: .linearGradient(Gradient(colors: [.clear, accent, .white]),
                                       startPoint: CGPoint(x: x - 70, y: y - 22), endPoint: CGPoint(x: x, y: y)),
                                       lineWidth: 1.3)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
