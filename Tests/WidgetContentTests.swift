import Foundation

@main
enum WidgetContentTests {
    static func main() {
        let images = [
            VisionImage(fileName: "one.png"),
            VisionImage(fileName: "two.jpg"),
            VisionImage(fileName: "three.heic")
        ]
        let state = WallState(
            images: images,
            completedDays: [],
            phrasesMarkdown: "Keep going."
        )

        precondition(
            state.visionBoards.count == 1
                && state.visionBoards[0].id == VisionBoard.primaryID
                && state.visionBoards[0].imageIDs == images.map(\.id),
            "Existing imported images must migrate into the primary vision board."
        )
        precondition(
            !state.visionBoardPrivacyEnabled
                && state.visionBoardPrivacyMessage == "Private vision board",
            "Vision-board desktop privacy must begin disabled with a safe default message."
        )

        let secondBoard = VisionBoard(
            name: "Private goals",
            imageIDs: [images[1].id, images[2].id],
            hiddenDesktopImageIDs: [images[1].id]
        )
        let multipleBoardState = WallState(
            images: images,
            visionBoards: [state.visionBoards[0], secondBoard],
            visionBoardPrivacyEnabled: true,
            visionBoardPrivacyMessage: "Goals in progress",
            completedDays: [],
            phrasesMarkdown: "Keep going."
        )
        let boardData = try! JSONEncoder().encode(multipleBoardState)
        let restoredBoards = try! JSONDecoder().decode(WallState.self, from: boardData)
        precondition(
            restoredBoards.visionBoards == multipleBoardState.visionBoards
                && restoredBoards.visionBoardPrivacyEnabled
                && restoredBoards.visionBoardPrivacyMessage == "Goals in progress",
            "Multiple boards and desktop-only privacy choices must persist independently."
        )

        precondition(
            state.desktopPhrases.count == 1
                && state.desktopPhrases[0].id == DesktopPhrase.primaryID
                && state.desktopPhrases[0].markdown == "Keep going.",
            "Existing phrase Markdown must migrate into the primary desktop window."
        )

        let secondPhrase = DesktopPhrase(markdown: "## Second", isVisible: false)
        let multiplePhraseState = WallState(
            images: [],
            completedDays: [],
            phrasesMarkdown: "## First",
            desktopPhrases: [
                DesktopPhrase(id: DesktopPhrase.primaryID, markdown: "## First"),
                secondPhrase
            ]
        )
        let phraseData = try! JSONEncoder().encode(multiplePhraseState)
        let restoredPhrases = try! JSONDecoder().decode(WallState.self, from: phraseData)
        precondition(
            restoredPhrases.desktopPhrases == multiplePhraseState.desktopPhrases,
            "Every phrase window and its visibility must persist independently."
        )

        precondition(
            WidgetContent.visionImages(from: state).map(\.id) == images.map(\.id),
            "The vision widget must show every image imported by the app."
        )

        let today = Date(timeIntervalSince1970: 1_788_048_000)
        let completed = WidgetContent.toggling(today, in: state)
        precondition(
            completed.completedDays.contains(DayKey.string(from: today)),
            "The first consistency toggle must mark today complete."
        )

        let uncompleted = WidgetContent.toggling(today, in: completed)
        precondition(
            !uncompleted.completedDays.contains(DayKey.string(from: today)),
            "The second consistency toggle must unmark today."
        )

        var streakCalendar = Calendar(identifier: .gregorian)
        streakCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let septemberFirst = streakCalendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 1,
            hour: 12
        ))!
        precondition(
            ConsistencyStreak.current(
                completedDays: ["2026-08-30", "2026-08-31"],
                through: septemberFirst,
                calendar: streakCalendar
            ) == 2,
            "A current streak must include yesterday when today is not marked yet."
        )
        precondition(
            ConsistencyStreak.current(
                completedDays: ["2026-08-30", "2026-08-31", "2026-09-01"],
                through: septemberFirst,
                calendar: streakCalendar
            ) == 3,
            "Marking today must extend the current streak."
        )
        precondition(
            ConsistencyStreak.current(
                completedDays: ["2026-08-30"],
                through: septemberFirst,
                calendar: streakCalendar
            ) == 0,
            "A missed yesterday must end the current streak."
        )

        precondition(
            state.worldClocks.count == 6,
            "A migrated wall must start with six editable world clocks."
        )
        precondition(
            state.worldClocks.allSatisfy { TimeZone(identifier: $0.timeZoneIdentifier) != nil },
            "Every starter clock must use a valid system time zone."
        )

        let reordered = WorldClockOrdering.moving(
            state.worldClocks[5].id,
            before: state.worldClocks[1].id,
            in: state.worldClocks
        )
        precondition(
            reordered.map(\.id) == [
                state.worldClocks[0].id,
                state.worldClocks[5].id,
                state.worldClocks[1].id,
                state.worldClocks[2].id,
                state.worldClocks[3].id,
                state.worldClocks[4].id
            ],
            "Dragging a clock must persist the requested display order."
        )

        let movedToEnd = WorldClockOrdering.moving(
            state.worldClocks[0].id,
            before: state.worldClocks[5].id,
            placeAfterDestination: true,
            in: state.worldClocks
        )
        precondition(
            movedToEnd.last?.id == state.worldClocks[0].id,
            "A clock must be draggable to the final position."
        )

        print("PASS: wall content, consistency, and world-clock contracts")
    }
}
