import SwiftUI

struct WorldClocksView: View {
    @ObservedObject var store: WallStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("World Clocks")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("A compact set of time zones that stays on your desktop.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    WorldClockDesktopPanelController.shared.present(store: store)
                } label: {
                    Label("Show on Desktop", systemImage: "rectangle.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
            }

            ScrollView {
                WorldClockEditorRows(store: store)
            }

            Button {
                store.addWorldClock()
            } label: {
                Label("Add clock", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .padding(28)
        .navigationTitle("World Clocks")
    }
}

struct WorldClockEditorRows: View {
    @ObservedObject var store: WallStore
    var compact = false

    var body: some View {
        LazyVStack(spacing: compact ? 8 : 12) {
            ForEach(store.worldClocks) { clock in
                WorldClockEditorRow(store: store, clock: clock, compact: compact)
            }
        }
    }
}

private struct WorldClockEditorRow: View {
    @ObservedObject var store: WallStore
    let clock: WorldClock
    let compact: Bool
    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 28)
                .contentShape(Rectangle())
                .draggable(clock.id.uuidString)
                .help("Drag to reorder")

            TextField("Label", text: nameBinding)
                .textFieldStyle(.roundedBorder)
                .frame(width: compact ? 105 : 180)

            Picker("Time zone", selection: timeZoneBinding) {
                ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { identifier in
                    Text(WorldClockFormatting.menuLabel(for: identifier))
                        .tag(identifier)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button(role: .destructive) {
                store.removeWorldClock(clock.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .help("Remove clock")
        }
        .padding(compact ? 8 : 12)
        .background(
            isDropTarget ? Color.indigo.opacity(0.18) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.indigo.opacity(0.8), lineWidth: 1.5)
            }
        }
        .dropDestination(for: String.self) { items, location in
            guard let value = items.first,
                  let sourceID = UUID(uuidString: value) else { return false }
            store.moveWorldClock(
                sourceID,
                relativeTo: clock.id,
                placeAfterDestination: location.y > (compact ? 24 : 30)
            )
            return true
        } isTargeted: {
            isDropTarget = $0
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { store.worldClocks.first(where: { $0.id == clock.id })?.name ?? clock.name },
            set: { store.updateWorldClock(clock.id, name: $0) }
        )
    }

    private var timeZoneBinding: Binding<String> {
        Binding(
            get: {
                store.worldClocks.first(where: { $0.id == clock.id })?.timeZoneIdentifier
                    ?? clock.timeZoneIdentifier
            },
            set: { store.updateWorldClock(clock.id, timeZoneIdentifier: $0) }
        )
    }
}

enum WorldClockFormatting {
    static func abbreviation(for clock: WorldClock) -> String {
        let name = clock.name.isEmpty ? cityName(for: clock.timeZoneIdentifier) : clock.name
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count > 1 {
            return words.prefix(3).compactMap(\.first).map(String.init).joined().uppercased()
        }
        return String(name.prefix(3)).uppercased()
    }

    static func cityName(for identifier: String) -> String {
        identifier
            .split(separator: "/")
            .last
            .map(String.init)?
            .replacingOccurrences(of: "_", with: " ")
            ?? identifier
    }

    static func menuLabel(for identifier: String) -> String {
        guard let zone = TimeZone(identifier: identifier) else { return identifier }
        return "\(cityName(for: identifier)) · \(gmtLabel(for: zone, at: Date()))"
    }

    static func time(for date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: date)
    }

    static func day(for date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    static func differenceFromLocal(for zone: TimeZone, at date: Date) -> String {
        let difference = zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        guard difference != 0 else { return "local" }
        let sign = difference > 0 ? "+" : "−"
        let totalMinutes = abs(difference) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 { return "\(sign)\(hours)h" }
        return "\(sign)\(hours)h \(minutes)m"
    }

    static func compactDifferenceFromLocal(for zone: TimeZone, at date: Date) -> String {
        let difference = zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        guard difference != 0 else { return "0" }
        let sign = difference > 0 ? "+" : "−"
        let totalMinutes = abs(difference) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0
            ? "\(sign)\(hours)"
            : String(format: "%@%d:%02d", sign, hours, minutes)
    }

    private static func gmtLabel(for zone: TimeZone, at date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        let sign = seconds >= 0 ? "+" : "−"
        let totalMinutes = abs(seconds) / 60
        return String(format: "GMT%@%d:%02d", sign, totalMinutes / 60, totalMinutes % 60)
    }
}
