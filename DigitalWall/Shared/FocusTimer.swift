import Foundation

/// A deadline keeps elapsed time correct across sleep and relaunch. Pausing freezes the remainder.
struct FocusTimer: Codable {
    enum Phase: String, Codable { case idle, running, paused, completed }
    enum Kind: String, Codable, CaseIterable { case timer, `break` }

    // Optional storage preserves sessions saved before timer kinds existed.
    private var storedKind: Kind?
    var kind: Kind { storedKind ?? .timer }

    private(set) var phase: Phase = .idle
    private(set) var duration: TimeInterval = 3_600
    private(set) var deadline: Date?
    private(set) var completedAt: Date?
    private(set) var pausedRemaining: TimeInterval = 0

    func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case .idle: return duration
        case .running: return max(0, deadline?.timeIntervalSince(now) ?? 0)
        case .paused: return pausedRemaining
        case .completed: return 0
        }
    }

    func progress(at now: Date) -> Double {
        guard phase != .idle else { return 0 }
        return min(1, max(0, 1 - remaining(at: now) / duration))
    }

    mutating func start(minutes: Int, kind: Kind = .timer, at now: Date) {
        storedKind = kind
        duration = TimeInterval(min(180, max(1, minutes)) * 60)
        deadline = now.addingTimeInterval(duration)
        completedAt = nil
        pausedRemaining = 0
        phase = .running
    }

    /// Returns true exactly once per completed session.
    @discardableResult
    mutating func update(at now: Date) -> Bool {
        guard phase == .running, remaining(at: now) <= 0 else { return false }
        return complete(at: now)
    }

    /// Manual completion follows the same lifecycle as expiration, including paused timers.
    @discardableResult
    mutating func complete(at now: Date) -> Bool {
        guard phase == .running || phase == .paused else { return false }
        phase = .completed
        completedAt = now
        deadline = nil
        pausedRemaining = 0
        return true
    }

    mutating func pause(at now: Date) {
        guard phase == .running, !update(at: now) else { return }
        pausedRemaining = remaining(at: now)
        deadline = nil
        phase = .paused
    }

    mutating func resume(at now: Date) {
        guard phase == .paused else { return }
        deadline = now.addingTimeInterval(pausedRemaining)
        phase = .running
    }

    func isIndicatorVisible(at now: Date) -> Bool {
        switch phase {
        case .idle: return false
        case .running, .paused: return true
        case .completed:
            if kind == .break { return true }
            guard let completedAt else { return false }
            return now < completedAt.addingTimeInterval(30)
        }
    }

    mutating func reset() { self = FocusTimer() }
}

/// Small, local duration grammar: no network requests or interpretation of unrelated text.
enum TimerDuration {
    static func kind(from input: String) -> FocusTimer.Kind {
        input.range(of: #"\bbreak\b"#, options: [.regularExpression, .caseInsensitive]) == nil ? .timer : .break
    }

    static func minutes(from input: String) -> Int? {
        var text = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return 60 }
        guard text.count <= 200 else { return nil }
        guard text.range(of: #"(^|\s)-"#, options: .regularExpression) == nil else { return nil }
        for phrase in ["half an hour", "half hour"] {
            text = text.replacingOccurrences(of: phrase, with: "30 minutes")
        }
        text = text.replacingOccurrences(of: "quarter of an hour", with: "15 minutes")
            .replacingOccurrences(of: "-", with: " ")
        let pattern = try! NSRegularExpression(pattern: #"\d+(?:\.\d+)?|[a-z]+"#)
        let range = NSRange(text.startIndex..., in: text)
        let matches = pattern.matches(in: text, range: range)
        let remainder = pattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        guard remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let fillers: Set<String> = ["start", "set", "timer", "focus", "session", "break", "take", "for", "please", "and", "of"]
        let tokens = matches.map { (text as NSString).substring(with: $0.range) }.filter { !fillers.contains($0) }
        let numbers: [String: Int] = [
            "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
            "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
            "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
            "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
        ]
        let units: [String: Double] = ["m": 1, "min": 1, "mins": 1, "minute": 1, "minutes": 1,
                                       "h": 60, "hr": 60, "hrs": 60, "hour": 60, "hours": 60]
        var index = 0
        var total: Double = 0
        var hasAmount = false
        while index < tokens.count {
            let amount: Double
            if tokens[index] == "a" || tokens[index] == "an" {
                index += 1
                if index < tokens.count, units[tokens[index]] != nil { amount = 1 }
                else { continue }
            } else if let numeric = Double(tokens[index]) {
                amount = numeric
                index += 1
            } else {
                var value = 0
                let start = index
                while index < tokens.count {
                    if let number = numbers[tokens[index]] { value += number }
                    else if tokens[index] == "hundred", value > 0 { value *= 100 }
                    else { break }
                    guard value <= 180 else { return nil }
                    index += 1
                }
                guard index > start else { return nil }
                amount = Double(value)
            }
            guard amount > 0 else { return nil }
            if index < tokens.count {
                guard let multiplier = units[tokens[index]] else { return nil }
                total += amount * multiplier
                index += 1
            } else { total += amount }
            hasAmount = true
        }
        guard hasAmount, total.isFinite, total >= 1, total <= 180, total.rounded() == total else { return nil }
        return Int(total)
    }
}
