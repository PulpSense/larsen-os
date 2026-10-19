import Foundation

@main
enum FocusTimerTests {
    static func main() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var timer = FocusTimer()
        precondition(timer.duration == 3_600 && timer.phase == .idle)
        timer.start(minutes: 60, at: start)
        precondition(timer.remaining(at: start) == 3_600)
        precondition(timer.progress(at: start.addingTimeInterval(900)) == 0.25)
        timer.pause(at: start.addingTimeInterval(900))
        precondition(timer.phase == .paused)
        precondition(timer.remaining(at: start.addingTimeInterval(50_000)) == 2_700)
        precondition(!timer.update(at: start.addingTimeInterval(50_000)))
        timer.resume(at: start.addingTimeInterval(50_000))
        precondition(timer.remaining(at: start.addingTimeInterval(50_001)) == 2_699)
        // Round-trip a running session, then simulate waking after the deadline.
        var restored = try JSONDecoder().decode(FocusTimer.self, from: JSONEncoder().encode(timer))
        precondition(restored.update(at: start.addingTimeInterval(60_000)))
        precondition(restored.phase == .completed && restored.progress(at: start) == 1)
        precondition(!restored.update(at: start.addingTimeInterval(60_001)))
        let completed = try JSONDecoder().decode(FocusTimer.self, from: JSONEncoder().encode(restored))
        precondition(completed.phase == .completed)
        restored.reset()
        precondition(restored.phase == .idle && restored.duration == 3_600)
        restored.start(minutes: 1, at: start)
        restored.pause(at: start.addingTimeInterval(60))
        precondition(restored.phase == .completed, "Pausing at expiration must not strand the timer.")
        restored.start(minutes: 25, at: start)
        precondition(restored.phase == .running && restored.duration == 1_500)
        restored.reset()
        precondition(!restored.update(at: start.addingTimeInterval(100_000)))
        var completion = FocusTimer()
        completion.start(minutes: 1, at: start)
        let finish = start.addingTimeInterval(60)
        precondition(completion.update(at: finish))
        precondition(completion.isIndicatorVisible(at: finish.addingTimeInterval(29.999)))
        precondition(!completion.isIndicatorVisible(at: finish.addingTimeInterval(30)))
        let savedCompletion = try JSONDecoder().decode(FocusTimer.self, from: JSONEncoder().encode(completion))
        precondition(savedCompletion.completedAt == finish)
        precondition(!savedCompletion.isIndicatorVisible(at: finish.addingTimeInterval(100)))
        let legacy = try JSONDecoder().decode(FocusTimer.self, from: Data(#"{"phase":"completed","duration":3600,"pausedRemaining":0}"#.utf8))
        precondition(!legacy.isIndicatorVisible(at: finish), "Legacy completions must not leave a permanent icon.")
        precondition(!FocusTimer().isIndicatorVisible(at: start))
        var breakTimer = FocusTimer()
        breakTimer.start(minutes: 10, kind: .break, at: start)
        precondition(breakTimer.update(at: start.addingTimeInterval(600)))
        precondition(breakTimer.isIndicatorVisible(at: start.addingTimeInterval(86_400)))
        let savedBreak = try JSONDecoder().decode(FocusTimer.self, from: JSONEncoder().encode(breakTimer))
        precondition(savedBreak.kind == .break && savedBreak.phase == .completed)
        precondition(savedBreak.isIndicatorVisible(at: start.addingTimeInterval(86_400)))
        breakTimer.reset()
        precondition(breakTimer.kind == .timer && !breakTimer.isIndicatorVisible(at: start))
        precondition(legacy.kind == .timer)
        precondition(TimerDuration.kind(from: "take a fifteen minute break") == .break)
        precondition(TimerDuration.kind(from: "10 minutes") == .timer)
        precondition(TimerDuration.kind(from: "breakfast") == .timer)
        var early = FocusTimer()
        precondition(!early.complete(at: start))
        early.start(minutes: 60, at: start)
        precondition(early.complete(at: start.addingTimeInterval(5)))
        precondition(early.remaining(at: start) == 0 && early.progress(at: start) == 1)
        precondition(early.completedAt == start.addingTimeInterval(5) && early.deadline == nil)
        precondition(!early.complete(at: start.addingTimeInterval(6)))
        precondition(!early.isIndicatorVisible(at: start.addingTimeInterval(35)))
        early.start(minutes: 10, kind: .break, at: start)
        early.pause(at: start.addingTimeInterval(5))
        precondition(early.complete(at: start.addingTimeInterval(10)))
        precondition(early.kind == .break && early.pausedRemaining == 0)
        precondition(early.isIndicatorVisible(at: start.addingTimeInterval(100)))
        for action in TimerCompletionAction.allCases {
            var flow = FocusTimer()
            flow.start(minutes: 10, completionAction: action, at: start)
            precondition(flow.completionAction == action)
            precondition(flow.takePendingCheckIn() == nil, "Running timers must not open a form")
            flow.pause(at: start.addingTimeInterval(2))
            flow = try JSONDecoder().decode(FocusTimer.self, from: JSONEncoder().encode(flow))
            precondition(flow.completionAction == action, "Per-session choice must survive relaunch")
            precondition(flow.complete(at: start.addingTimeInterval(5)))
            let expected: TimerCompletionAction? = action == .alert ? nil : action
            if action != .alert {
                precondition(flow.isIndicatorVisible(at: start.addingTimeInterval(86_400)),
                             "Pending check-ins must stay visible until the user clicks")
            }
            precondition(flow.takePendingCheckIn() == expected)
            precondition(flow.takePendingCheckIn() == nil, "A completed timer must open the form once")
            flow = try JSONDecoder().decode(FocusTimer.self, from: JSONEncoder().encode(flow))
            precondition(flow.takePendingCheckIn() == nil, "Handled forms must not reopen after relaunch")
            flow.start(minutes: 1, kind: .break, completionAction: action, at: start)
            flow.update(at: finish)
            precondition(flow.completionAction == .alert && flow.takePendingCheckIn() == nil,
                         "Breaks must never open a form")
            flow.start(minutes: 1, completionAction: action, at: start)
            flow = try JSONDecoder().decode(FocusTimer.self, from: JSONEncoder().encode(flow))
            flow.update(at: finish)
            precondition(flow.takePendingCheckIn() == expected, "Expired timers restored after sleep must keep their choice")
            flow.reset()
            precondition(flow.takePendingCheckIn() == nil)
        }
        precondition(legacy.completionAction == .alert && !legacy.hasPendingCheckIn,
                     "Existing timers retain their original alert-only behavior")
        print("PASS: completion choices, per-session persistence, single form transition, sleep, cancellation, break and legacy behavior")
        let examples: [(String, Int)] = [
            ("", 60), ("60 minute", 60), ("10 minutes", 10), ("fifteen minutes", 15),
            ("15m", 15), ("1h 30m", 90), ("1 hour and thirty minutes", 90),
            ("take a ten minute break", 10), ("a break for fifteen minutes", 15),
            ("an hour", 60), ("half an hour", 30), ("quarter of an hour", 15),
            ("twenty-five minutes", 25), ("one hundred and twenty minutes", 120),
            ("1.5 hours", 90), ("180", 180), ("Start a timer for 45 minutes please", 45)
        ]
        for (input, expected) in examples {
            precondition(TimerDuration.minutes(from: input) == expected, "Failed duration: \(input)")
        }
        for input in ["banana", "10 cats", "0", "-10 minutes", "-ten minutes", "181 minutes", "4 hours", "10:30", "1.5 minutes", "timer", "break", "tomorrow", "10 minutes nonsense"] {
            precondition(TimerDuration.minutes(from: input) == nil, "Invalid duration accepted: \(input)")
        }
        print("Focus timer tests passed: lifecycle, 30-second completion, relaunch migration and natural-language durations")
    }
}
