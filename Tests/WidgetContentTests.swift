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

        let expandedImages = (1...9).map { VisionImage(fileName: "\($0).png") }
        precondition(
            VisionBoardPresentation.imagesForExpandedView(expandedImages).map(\.id)
                == expandedImages.map(\.id),
            "The expanded vision board must show every image visible in the compact panel."
        )

        let today = Date(timeIntervalSince1970: 1_788_048_000)
        let oneHour = WidgetContent.addingDeepWorkHour(today, in: state)
        precondition(
            DeepWork.hours(on: today, in: oneHour.deepWorkHours) == 1
                && !oneHour.completedDays.contains(DayKey.string(from: today)),
            "The first logged hour must remain visible without winning the day."
        )

        let fourHours = (0..<3).reduce(oneHour) { current, _ in
            WidgetContent.addingDeepWorkHour(today, in: current)
        }
        precondition(
            DeepWork.hours(on: today, in: fourHours.deepWorkHours) == 4
                && fourHours.completedDays.contains(DayKey.string(from: today)),
            "The fourth logged hour must win the day."
        )

        let fifthHour = WidgetContent.addingDeepWorkHour(today, in: fourHours)
        precondition(
            DeepWork.hours(on: today, in: fifthHour.deepWorkHours) == 5
                && fifthHour.completedDays.contains(DayKey.string(from: today)),
            "Hours beyond the daily goal must be preserved without changing won-day status."
        )

        let restoredHours = try! JSONDecoder().decode(
            WallState.self,
            from: JSONEncoder().encode(fifthHour)
        )
        precondition(
            DeepWork.hours(on: today, in: restoredHours.deepWorkHours) == 5,
            "Deep-work hours must survive a persistence round trip."
        )

        let legacyData = Data(#"{"completedDays":["2026-08-31"],"phrasesMarkdown":"Keep going."}"#.utf8)
        let migratedLegacyState = try! JSONDecoder().decode(WallState.self, from: legacyData)
        precondition(
            migratedLegacyState.deepWorkHours["2026-08-31"] == DeepWork.dailyGoalHours,
            "Existing completed days must migrate to four deep-work hours."
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

        print("PASS: wall content, deep-work, and world-clock contracts")
    }
}
