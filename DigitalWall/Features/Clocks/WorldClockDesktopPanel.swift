import AppKit
import SwiftUI

@MainActor
final class WorldClockDesktopPanelController {
    static let shared = WorldClockDesktopPanelController()

    private let enabledKey = "desktopWorldClockPanelEnabled"
    private let frameAutosaveName = "DigitalWallWorldClockDesktopPanelWidgetStyle"
    private let legacyFrameAutosaveName = "DigitalWallWorldClockDesktopPanel"
    private let positionMigrationKey = "worldClockPanelWidgetStylePositionMigrationV1"
    private var panel: DesktopWallPanel?

    private init() {}

    func restoreIfEnabled(store: WallStore) {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: enabledKey) == nil || defaults.bool(forKey: enabledKey)
        if enabled { present(store: store) }
    }

    func present(store: WallStore) {
        UserDefaults.standard.set(true, forKey: enabledKey)

        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let panel = DesktopPanelSupport.makePanel(
            initialSize: NSSize(width: 680, height: 170),
            minimumSize: NSSize(width: 300, height: 150),
            frameAutosaveName: frameAutosaveName,
            defaultAnchor: .bottomLeft
        ) {
            WorldClockDesktopPanelContent(
                store: store,
                setEditing: { [weak self] isEditing in
                    self?.setEditing(isEditing)
                },
                close: { [weak self] in self?.dismiss() }
            )
        }

        self.panel = panel
        migratePositionIfNeeded(panel)
        panel.orderFrontRegardless()
    }

    func dismiss() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        panel?.orderOut(nil)
        panel = nil
    }

    private func setEditing(_ isEditing: Bool) {
        panel?.setContentEditing(isEditing)
        if isEditing {
            NSApp.activate(ignoringOtherApps: true)
            panel?.makeKeyAndOrderFront(nil)
        }
    }

    private func migratePositionIfNeeded(_ panel: DesktopWallPanel) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: positionMigrationKey) else { return }
        defer { defaults.set(true, forKey: positionMigrationKey) }

        let compactSize = panel.frame.size
        guard panel.setFrameUsingName(legacyFrameAutosaveName) else { return }
        let legacyFrame = panel.frame
        let screen = NSScreen.screens.max { first, second in
            first.visibleFrame.intersection(legacyFrame).area
                < second.visibleFrame.intersection(legacyFrame).area
        } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        panel.setFrame(
            DesktopPanelSupport.migratedFrame(
                currentSize: compactSize,
                legacyFrame: legacyFrame,
                visibleFrame: visibleFrame
            ),
            display: false
        )
    }
}

private extension NSRect {
    var area: CGFloat { max(0, width) * max(0, height) }
}

private struct WorldClockDesktopPanelContent: View {
    @ObservedObject var store: WallStore
    let setEditing: (Bool) -> Void
    let close: () -> Void
    @State private var controlsVisible = false
    @State private var isEditing = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DesktopPanelBackground()

            if isEditing {
                editor
            } else {
                clocks
            }

            if !isEditing {
                DesktopPanelControlMenu(isVisible: controlsVisible) {
                    Button("Edit clocks", systemImage: "pencil") {
                        setEditing(true)
                        isEditing = true
                    }

                    Divider()

                    Button("Close", systemImage: "xmark", role: .destructive, action: close)
                }
                .padding(12)
            }
        }
        .onHover { controlsVisible = $0 }
    }

    private var clocks: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            GeometryReader { proxy in
                let spacing: CGFloat = 8
                let inset: CGFloat = 10
                let layout = bestClockLayout(
                    itemCount: store.worldClocks.count,
                    size: CGSize(
                        width: max(1, proxy.size.width - inset * 2),
                        height: max(1, proxy.size.height - inset * 2)
                    ),
                    spacing: spacing
                )

                ScrollView {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(layout.cell), spacing: spacing),
                            count: layout.columns
                        ),
                        spacing: spacing
                    ) {
                        ForEach(store.worldClocks) { clock in
                            clockTile(clock, now: timeline.date)
                                .frame(width: layout.cell, height: layout.cell)
                        }
                    }
                    .frame(
                        minWidth: max(1, proxy.size.width - inset * 2),
                        minHeight: max(1, proxy.size.height - inset * 2),
                        alignment: .center
                    )
                    .padding(inset)
                }
            }
        }
    }

    private func clockTile(_ clock: WorldClock, now: Date) -> some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: max(16, side * 0.18), style: .continuous)
                    .fill(.black.opacity(0.34))
                    .overlay {
                        RoundedRectangle(cornerRadius: max(16, side * 0.18), style: .continuous)
                            .stroke(.white.opacity(0.24), lineWidth: 1)
                    }

                ClockTileTickFrame()
                    .padding(max(7, side * 0.07))

                VStack(spacing: 0) {
                    Text(WorldClockFormatting.abbreviation(for: clock))
                        .font(.system(size: max(10, side * 0.13), weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 1)

                    Text(WorldClockFormatting.time(for: now, in: clock.timeZone))
                        .font(.system(size: max(23, side * 0.30), weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.62)
                        .lineLimit(1)

                    Spacer(minLength: 1)

                    Text(WorldClockFormatting.compactDifferenceFromLocal(for: clock.timeZone, at: now))
                        .font(.system(size: max(10, side * 0.12), weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.vertical, max(13, side * 0.13))
                .padding(.horizontal, max(10, side * 0.10))
            }
        }
    }

    private func bestClockLayout(
        itemCount: Int,
        size: CGSize,
        spacing: CGFloat
    ) -> (columns: Int, cell: CGFloat) {
        guard itemCount > 0 else { return (1, 1) }

        return (1...itemCount).reduce((columns: 1, cell: CGFloat(0))) { best, columns in
            let rows = Int(ceil(Double(itemCount) / Double(columns)))
            let cellWidth = (size.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
            let cellHeight = (size.height - CGFloat(rows - 1) * spacing) / CGFloat(rows)
            let cell = max(1, min(cellWidth, cellHeight))
            return cell > best.cell ? (columns, cell) : best
        }
    }

    private var editor: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    store.addWorldClock()
                } label: {
                    Label("Add", systemImage: "plus")
                }

                Spacer()

                Button("Done") {
                    setEditing(false)
                    isEditing = false
                }
                .buttonStyle(.borderedProminent)
            }

            ScrollView {
                WorldClockEditorRows(store: store, compact: true)
            }
        }
        .buttonStyle(.bordered)
        .padding(14)
    }
}

private struct ClockTileTickFrame: View {
    var body: some View {
        Canvas { context, size in
            let count = 9
            let longTick: CGFloat = 5
            let shortTick: CGFloat = 3

            for index in 0..<count {
                let progress = CGFloat(index) / CGFloat(count - 1)
                let x = progress * size.width
                let y = progress * size.height
                let length = index.isMultiple(of: 2) ? longTick : shortTick

                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: length))
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x, y: size.height - length))
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: length, y: y))
                path.move(to: CGPoint(x: size.width, y: y))
                path.addLine(to: CGPoint(x: size.width - length, y: y))
                context.stroke(path, with: .color(.white.opacity(0.12)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}
