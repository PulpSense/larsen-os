import AppIntents
import AppKit
import SwiftUI
import WidgetKit

struct WallEntry: TimelineEntry {
    let date: Date
    let state: WallState
}

struct WallTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WallEntry {
        WallEntry(date: Date(), state: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (WallEntry) -> Void) {
        completion(WallEntry(date: Date(), state: WallPersistence.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WallEntry>) -> Void) {
        let entry = WallEntry(date: Date(), state: WallPersistence.load())
        let refresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
            ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - Vision Board

struct VisionBoardEntry: TimelineEntry {
    let date: Date
    let images: [WidgetVisionImage]
    let openURL: URL
}

struct WidgetVisionImage: Identifiable {
    let id: String
    let url: URL

    init(_ image: VisionImage) {
        id = image.id.uuidString
        url = WallPersistence.imageURL(for: image)
    }

}

struct VisionBoardTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> VisionBoardEntry {
        entry(images: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (VisionBoardEntry) -> Void) {
        completion(entry(images: WidgetContent.visionImages(from: WallPersistence.load())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VisionBoardEntry>) -> Void) {
        let images = WidgetContent.visionImages(from: WallPersistence.load())
        let refresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
            ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry(images: images)], policy: .after(refresh)))
    }

    private func entry(images: [VisionImage]) -> VisionBoardEntry {
        VisionBoardEntry(
            date: Date(),
            images: images.map(WidgetVisionImage.init),
            openURL: URL(string: "\(AppConfiguration.urlScheme)://show-board")!
        )
    }
}

struct VisionBoardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VisionBoardEntry

    var body: some View {
        Group {
            if entry.images.isEmpty {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title)
                    .foregroundStyle(.secondary)
            } else {
                collage
            }
        }
        .widgetURL(entry.openURL)
        .containerBackground(.background, for: .widget)
    }

    private var collage: some View {
        GeometryReader { proxy in
            let layout = collageLayout
            let images = Array(entry.images.prefix(layout.limit))
            let spacing: CGFloat = 3
            let width = max(1, (proxy.size.width - CGFloat(layout.columns - 1) * spacing) / CGFloat(layout.columns))
            let rows = max(1, Int(ceil(Double(images.count) / Double(layout.columns))))
            let height = max(1, (proxy.size.height - CGFloat(rows - 1) * spacing) / CGFloat(rows))

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(width), spacing: spacing),
                    count: layout.columns
                ),
                spacing: spacing
            ) {
                ForEach(images) { image in
                    WidgetLocalImage(image: image)
                        .frame(width: width, height: height)
                        .clipped()
                }
            }
        }
    }

    private var collageLayout: (columns: Int, limit: Int) {
        switch family {
        case .systemSmall: (2, 4)
        case .systemLarge: (3, 6)
        default: (3, 6)
        }
    }
}

private struct WidgetLocalImage: View {
    let image: WidgetVisionImage

    var body: some View {
        if let nsImage = NSImage(contentsOf: image.url) {
            Image(nsImage: nsImage).resizable().scaledToFill()
        } else {
            Color.secondary.opacity(0.15)
        }
    }
}

struct DigitalWallDesktopWidget: Widget {
    let kind = AppConfiguration.visionBoardWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VisionBoardTimelineProvider()) { entry in
            VisionBoardWidgetView(entry: entry)
        }
        .configurationDisplayName("Vision Board")
        .description("Automatically shows every image imported into Digital Wall.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Year Consistency

struct ConsistencyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WallEntry

    private var year: Int { Calendar.current.component(.year, from: entry.date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text(verbatim: "\(year) · \(completedCount) \(completedCount == 1 ? "day" : "days") marked")
                } icon: {
                    Image(systemName: "square.grid.3x3.fill")
                }
                    .font(.headline)
                    .foregroundStyle(.indigo)
                Spacer()
                Button(intent: ToggleTodayV3Intent()) {
                    Image(systemName: isTodayComplete ? "checkmark" : "plus")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(isTodayComplete ? Color.green : Color.indigo, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .help(isTodayComplete ? "Unmark today" : "Complete today")
            }

            WidgetYearGrid(year: year, completedDays: entry.state.completedDays)
                .frame(maxHeight: .infinity)

            HStack {
                Label(
                    "\(currentStreak) \(currentStreak == 1 ? "day" : "days") streak",
                    systemImage: "flame.fill"
                )
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(family == .systemLarge ? 14 : 10)
        .containerBackground(.background, for: .widget)
    }

    private var completedCount: Int {
        entry.state.completedDays.filter { $0.hasPrefix("\(year)-") }.count
    }

    private var isTodayComplete: Bool {
        entry.state.completedDays.contains(DayKey.string(from: entry.date))
    }

    private var currentStreak: Int {
        var date = entry.date
        var streak = 0
        while entry.state.completedDays.contains(DayKey.string(from: date)) {
            streak += 1
            guard let prior = Calendar.current.date(byAdding: .day, value: -1, to: date) else { break }
            date = prior
        }
        return streak
    }
}

private struct WidgetYearGrid: View {
    let year: Int
    let completedDays: Set<String>

    var body: some View {
        GeometryReader { proxy in
            let weeks = WidgetCalendar.weeks(in: year)
            let spacing: CGFloat = 2
            let cellWidth = max(1, (proxy.size.width - CGFloat(weeks.count - 1) * spacing) / CGFloat(weeks.count))
            let cellHeight = max(1, (proxy.size.height - CGFloat(6) * spacing) / 7)
            let cell = min(cellWidth, cellHeight)

            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { weekday in
                            if let date = week[weekday] {
                                RoundedRectangle(cornerRadius: max(1, cell * 0.22))
                                    .fill(color(for: date))
                                    .frame(width: cell, height: cell)
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func color(for date: Date) -> Color {
        if completedDays.contains(DayKey.string(from: date)) { return .indigo }
        if date > Date() { return .secondary.opacity(0.06) }
        return .secondary.opacity(0.18)
    }
}

private enum WidgetCalendar {
    static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }()

    static func weeks(in year: Int) -> [[Date?]] {
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return [] }
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.dateComponents([.day], from: start, to: end).day ?? 365
        let slotCount = Int(ceil(Double(leading + dayCount) / 7.0)) * 7
        let slots: [Date?] = (0..<slotCount).map { index in
            let offset = index - leading
            guard offset >= 0 && offset < dayCount else { return nil }
            return calendar.date(byAdding: .day, value: offset, to: start)
        }
        return stride(from: 0, to: slots.count, by: 7).map {
            Array(slots[$0..<min($0 + 7, slots.count)])
        }
    }
}

struct DigitalWallConsistencyWidget: Widget {
    let kind = AppConfiguration.consistencyWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WallTimelineProvider()) { entry in
            ConsistencyWidgetView(entry: entry)
        }
        .configurationDisplayName("Year Consistency")
        .description("See your year and check off today without opening the app.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Phrases

struct PhraseConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Phrase"
    static let description = IntentDescription("Format with # headings, - lists, **bold**, and *italics*.")

    @Parameter(
        title: "Markdown",
        description: "Supports # headings, - lists, **bold**, *italics*, and line breaks.",
        default: "Keep going.",
        inputOptions: .init(
            capitalizationType: .sentences,
            multiline: true,
            autocorrect: true,
            smartQuotes: false,
            smartDashes: false
        )
    )
    var phrase: String

    init() { phrase = "Keep going." }
}

struct PhraseEntry: TimelineEntry {
    let date: Date
    let markdown: String
}

struct PhraseTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PhraseEntry {
        PhraseEntry(date: Date(), markdown: WallState.starterPhrases)
    }

    func snapshot(for configuration: PhraseConfigurationIntent, in context: Context) async -> PhraseEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: PhraseConfigurationIntent, in context: Context) async -> Timeline<PhraseEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    private func entry(for configuration: PhraseConfigurationIntent) -> PhraseEntry {
        let custom = configuration.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let markdown = custom.isEmpty ? WallPersistence.load().phrasesMarkdown : custom
        return PhraseEntry(date: Date(), markdown: markdown)
    }
}

struct PhrasesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PhraseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: blockSpacing) {
                ForEach(PhraseMarkdownBlock.parse(entry.markdown)) { block in
                    blockView(block)
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()

        }
        .padding(family == .systemLarge ? 22 : 16)
        .containerBackground(.background, for: .widget)
    }

    private var blockSpacing: CGFloat {
        family == .systemLarge ? 8 : 5
    }

    @ViewBuilder
    private func blockView(_ block: PhraseMarkdownBlock) -> some View {
        switch block.kind {
        case let .heading(level):
            Text(inlineMarkdown(block.text))
                .font(headingFont(level: level))
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•")
                Text(inlineMarkdown(block.text))
            }
            .font(bodyFont)
        case let .numbered(marker):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(marker)
                    .monospacedDigit()
                Text(inlineMarkdown(block.text))
            }
            .font(bodyFont)
        case .quote:
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(.secondary.opacity(0.55))
                    .frame(width: 3)
                Text(inlineMarkdown(block.text))
                    .italic()
            }
            .font(bodyFont)
        case .paragraph:
            Text(inlineMarkdown(block.text))
                .font(bodyFont)
        case .spacer:
            Color.clear.frame(height: 3)
        }
    }

    private var bodyFont: Font {
        switch family {
        case .systemSmall: .caption
        case .systemLarge: .body
        default: .callout
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            if family == .systemSmall { return .headline }
            return family == .systemLarge ? .title2.bold() : .title3.bold()
        case 2:
            return family == .systemLarge ? .title3.bold() : .headline
        default:
            return family == .systemLarge ? .headline : .subheadline.bold()
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

private struct PhraseMarkdownBlock: Identifiable {
    enum Kind {
        case heading(Int)
        case bullet
        case numbered(String)
        case quote
        case paragraph
        case spacer
    }

    let id: Int
    let kind: Kind
    let text: String

    static func parse(_ markdown: String) -> [PhraseMarkdownBlock] {
        markdown.components(separatedBy: .newlines).enumerated().map { index, rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                return PhraseMarkdownBlock(id: index, kind: .spacer, text: "")
            }

            let headingMarks = line.prefix { $0 == "#" }.count
            if (1...3).contains(headingMarks),
               line.dropFirst(headingMarks).hasPrefix(" ") {
                return PhraseMarkdownBlock(
                    id: index,
                    kind: .heading(headingMarks),
                    text: String(line.dropFirst(headingMarks + 1))
                )
            }

            if line.hasPrefix("- ") || line.hasPrefix("+ ") || line.hasPrefix("* ") {
                return PhraseMarkdownBlock(id: index, kind: .bullet, text: String(line.dropFirst(2)))
            }

            if let dot = line.firstIndex(of: ".") {
                let digits = line[..<dot]
                let remainder = line[line.index(after: dot)...]
                if !digits.isEmpty,
                   digits.allSatisfy(\.isNumber),
                   remainder.hasPrefix(" ") {
                    return PhraseMarkdownBlock(
                        id: index,
                        kind: .numbered("\(digits)."),
                        text: String(remainder.dropFirst())
                    )
                }
            }

            if line.hasPrefix("> ") {
                return PhraseMarkdownBlock(id: index, kind: .quote, text: String(line.dropFirst(2)))
            }

            return PhraseMarkdownBlock(id: index, kind: .paragraph, text: line)
        }
    }
}

struct DigitalWallPhrasesWidget: Widget {
    // New kind because this version migrates from static to configurable.
    let kind = AppConfiguration.phrasesWidgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: PhraseConfigurationIntent.self,
            provider: PhraseTimelineProvider()
        ) { entry in
            PhrasesWidgetView(entry: entry)
        }
        .configurationDisplayName("Editable Phrase")
        .description("Display a formatted, multiline reminder.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct DigitalWallWidgetBundle: WidgetBundle {
    var body: some Widget {
        DigitalWallDesktopWidget()
        DigitalWallConsistencyWidget()
    }
}
