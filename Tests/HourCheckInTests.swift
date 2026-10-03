import Foundation

final class StubWebhookProtocol: URLProtocol, @unchecked Sendable {
    static var requests: [URLRequest] = []
    static var statuses: [Int] = []
    static var error: URLError?
    static var onFirstRequest: ((StubWebhookProtocol) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        if let onFirstRequest = Self.onFirstRequest {
            Self.onFirstRequest = nil
            onFirstRequest(self)
            return
        }
        respond()
    }

    func respond() {
        if let error = Self.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let status = Self.statuses.isEmpty ? 204 : Self.statuses.removeFirst()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:]
        )!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
enum HourCheckInTests {
    @MainActor
    static func main() async throws {
        let date = ISO8601DateFormatter().date(from: "2026-10-03T15:00:00Z")!
        let id = UUID()
        let oldJSON = Data("{\"deepWorkHours\":{\"2026-10-02\":4}}".utf8)
        let oldState = try JSONDecoder().decode(WallState.self, from: oldJSON)
        precondition(oldState.hourCheckIns.isEmpty && !oldState.webhookSettings.isEnabled)
        precondition(oldState.deepWorkHours["2026-10-02"] == 4, "Migration must preserve hours.")

        var disk = WallState.empty
        var failSave = false
        let load = { disk }
        let save: (WallState) throws -> Void = { state in
            if failSave { throw CocoaError(.fileWriteNoPermission) }
            // Exercise the full persisted format, not an in-memory copy.
            disk = try JSONDecoder().decode(WallState.self, from: JSONEncoder().encode(state))
        }
        let store = WallStore(load: load, save: save, startWebhookSync: false)
        precondition(store.finishHour(id: id, summary: "  Build something  ", notes: "offline", at: date))
        precondition(store.deepWorkHours(on: date) == 1 && store.pendingCheckIns.count == 1)
        precondition(disk.hourCheckIns[0].summary == "Build something")
        precondition(disk.hourCheckIns[0].day == DayKey.string(from: date))
        precondition(disk.hourCheckIns[0].hoursAfter == 1)
        precondition(store.finishHour(id: id, summary: "Build something", notes: "offline", at: date))
        precondition(store.deepWorkHours(on: date) == 1 && store.pendingCheckIns.count == 1,
                     "Repeated submission IDs must not count twice.")

        failSave = true
        precondition(!store.finishHour(id: UUID(), summary: "Unsaved", notes: "", at: date))
        precondition(store.deepWorkHours(on: date) == 1 && disk.hourCheckIns.count == 1,
                     "A failed save must not mutate the tracker or lose the form.")
        failSave = false
        precondition(!store.finishHour(id: UUID(), summary: " \n ", notes: "", at: date))
        precondition(disk.hourCheckIns.count == 1)

        let restarted = WallStore(load: load, save: save, startWebhookSync: false)
        precondition(restarted.pendingCheckIns.first?.id == id && restarted.deepWorkHours(on: date) == 1,
                     "Offline check-ins and hours must survive restarting the app.")
        disk.webhookSettings = WebhookSettings(url: "https://automation.example/check-in", isEnabled: true)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubWebhookProtocol.self]
        let syncStore = WallStore(
            load: load, save: save, webhookClient: WebhookClient(configuration: config),
            readWebhookToken: { "test-token" }, startWebhookSync: false
        )
        StubWebhookProtocol.error = URLError(.notConnectedToInternet)
        await syncStore.syncWebhook(force: true)
        precondition(syncStore.pendingCheckIns.count == 1 && disk.hourCheckIns[0].attempts == 1)
        precondition(disk.hourCheckIns[0].nextAttemptAt != nil)
        let offlineRequestCount = StubWebhookProtocol.requests.count
        await syncStore.syncWebhook()
        precondition(StubWebhookProtocol.requests.count == offlineRequestCount,
                     "Automatic retry must respect persisted backoff.")

        StubWebhookProtocol.error = nil
        StubWebhookProtocol.statuses = [401]
        await syncStore.syncWebhook(force: true)
        precondition(syncStore.pendingCheckIns.count == 1 && disk.hourCheckIns[0].attempts == 2,
                     "HTTP errors must leave the check-in pending.")
        StubWebhookProtocol.statuses = [204]
        failSave = true
        await syncStore.syncWebhook(force: true)
        precondition(syncStore.pendingCheckIns.count == 1 && disk.hourCheckIns[0].deliveredAt == nil,
                     "Failed acknowledgment persistence must leave the same ID pending.")
        failSave = false
        await syncStore.syncWebhook(force: true)
        precondition(syncStore.pendingCheckIns.isEmpty && disk.hourCheckIns[0].deliveredAt != nil)
        precondition(syncStore.deepWorkHours(on: date) == 1, "Delivery must never increment hours.")
        let synced = WallStore(load: load, save: save, startWebhookSync: false)
        precondition(synced.pendingCheckIns.isEmpty, "Successful acknowledgments must survive restart.")
        for request in StubWebhookProtocol.requests {
            precondition(request.httpMethod == "POST")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            precondition(request.value(forHTTPHeaderField: "Idempotency-Key") == id.uuidString,
                         "Every retry must use the original submission ID.")
        }

        let request = try WebhookRequest.make(payload: disk.hourCheckIns[0].payload,
                                             url: disk.webhookSettings.url, token: "test-token")
        let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        precondition(json["submission_id"] as? String == id.uuidString)
        precondition(json["schema_version"] as? Int == 2 && json["hours"] as? Int == 1)
        precondition(json["daily_hours"] as? Int == 1 && json["event"] as? String == "hour.completed")
        precondition(json["completed_at"] as? String == "2026-10-03T15:00:00Z")
        precondition(json["token"] == nil)
        let anonymous = try WebhookRequest.make(payload: .test(), url: disk.webhookSettings.url, token: "")
        precondition(anonymous.value(forHTTPHeaderField: "Authorization") == nil)
        let beforeTestHours = syncStore.deepWorkHours(on: date)
        await syncStore.sendWebhookTest()
        precondition(syncStore.hourCheckIns.count == 1 && syncStore.deepWorkHours(on: date) == beforeTestHours,
                     "A webhook test must not create a check-in or count an hour.")

        for url in ["http://example.com", "file:///tmp/a", "https://user:password@example.com", "https://example.com/#secret"] {
            do {
                _ = try WebhookRequest.endpoint(url)
                preconditionFailure("Unsafe URL accepted: \(url)")
            } catch {}
        }
        do {
            try WebhookRequest.validateToken("secret\r\nInjected: header")
            preconditionFailure("Header injection accepted")
        } catch {}
        var failed = disk.hourCheckIns[0]
        for _ in 0..<30 { failed.recordFailure("Offline", at: date) }
        precondition(failed.nextAttemptAt == date.addingTimeInterval(300), "Retry delay must be bounded.")

        var form = HourCheckInForm()
        precondition(form.validationMessage != nil)
        form.date = date.addingTimeInterval(-86400)
        form.category = .marketing
        form.activity = "  Drafted a campaign  "
        form.distractions = "None"
        form.preparation.read10XRule = true
        form.preparation.reviewedVisionBoard = true
        precondition(form.validationMessage == nil)
        let regularID = UUID()
        let regular = HourCheckIns.recording(id: regularID, form: form, at: date, in: .empty)
        precondition(regular.deepWorkHours.isEmpty && regular.hourCheckIns.count == 1,
                     "An ordinary hour must save a check-in without incrementing the tracker.")
        precondition(regular.hourCheckIns[0].day == DayKey.string(from: form.date))
        precondition(regular.hourCheckIns[0].completedAt == date)
        form.isDeepWork = true
        let deepID = UUID()
        let deep = HourCheckIns.recording(id: deepID, form: form, at: date, in: regular)
        precondition(DeepWork.hours(on: form.date, in: deep.deepWorkHours) == 1)
        precondition(DeepWork.hours(on: date, in: deep.deepWorkHours) == 0,
                     "The hour belongs to the selected form date, not the upload or submission date.")
        let duplicated = HourCheckIns.recording(id: deepID, form: form, at: date, in: deep)
        precondition(duplicated.hourCheckIns.count == 2 && duplicated.deepWorkHours == deep.deepWorkHours)
        let restored = try JSONDecoder().decode(WallState.self, from: JSONEncoder().encode(deep))
        precondition(restored.hourCheckIns[1].form?.preparation == form.preparation)
        precondition(restored.hourCheckIns[1].form?.activity == "Drafted a campaign")
        let formRequest = try WebhookRequest.make(payload: restored.hourCheckIns[1].payload,
                                                  url: disk.webhookSettings.url, token: "")
        let formJSON = try JSONSerialization.jsonObject(with: formRequest.httpBody!) as! [String: Any]
        precondition(formJSON["category"] as? String == "Marketing" && formJSON["is_deep_work"] as? Bool == true)
        precondition(formJSON["activity"] as? String == "Drafted a campaign")
        precondition(formJSON["distractions"] as? String == "None")
        let prepJSON = formJSON["daily_preparation"] as! [String: Bool]
        precondition(prepJSON.count == 6 && prepJSON["read_10x_rule"] == true && prepJSON["reviewed_top_goals"] == false)
        let regularRequest = try WebhookRequest.make(payload: restored.hourCheckIns[0].payload,
                                                     url: disk.webhookSettings.url, token: "")
        let regularJSON = try JSONSerialization.jsonObject(with: regularRequest.httpBody!) as! [String: Any]
        precondition(regularJSON["hours"] as? Int == 0 && regularJSON["is_deep_work"] as? Bool == false)
        let formStore = WallStore(load: load, save: save, startWebhookSync: false)
        let countBefore = disk.hourCheckIns.count
        var invalidForm = form
        invalidForm.distractions = " \n "
        precondition(!formStore.finishHour(id: UUID(), form: invalidForm, at: date))
        precondition(disk.hourCheckIns.count == countBefore)
        failSave = true
        precondition(!formStore.finishHour(id: UUID(), form: form, at: date))
        precondition(disk.hourCheckIns.count == countBefore)
        failSave = false
        var queueDisk = deep
        queueDisk.webhookSettings = WebhookSettings(url: "https://original.example/check-in", isEnabled: true)
        var queueToken = "original-token"
        let queueStore = WallStore(
            load: { queueDisk }, save: { queueDisk = $0 }, webhookClient: WebhookClient(configuration: config),
            readWebhookToken: { queueToken }, writeWebhookToken: { queueToken = $0 }, startWebhookSync: false
        )
        StubWebhookProtocol.requests = []
        StubWebhookProtocol.onFirstRequest = { request in
            Task { @MainActor in
                precondition(queueStore.isSyncingWebhook)
                precondition(queueStore.configureWebhook(url: queueStore.webhookSettings.url,
                                                         token: queueToken, enabled: false),
                             "Pausing must succeed while a request is in flight.")
                precondition(queueStore.webhookStatus.contains("Sync paused"))
                request.respond()
            }
        }
        await queueStore.syncWebhook(force: true)
        precondition(StubWebhookProtocol.requests.count == 1 && queueStore.pendingCheckIns.count == 1,
                     "After acknowledging the in-flight request, pausing must stop the next request.")
        precondition(!queueStore.webhookSettings.isEnabled && !queueDisk.webhookSettings.isEnabled)

        queueDisk = deep
        queueDisk.webhookSettings = WebhookSettings(url: "https://original.example/check-in", isEnabled: true)
        let redirectedStore = WallStore(
            load: { queueDisk }, save: { queueDisk = $0 }, webhookClient: WebhookClient(configuration: config),
            readWebhookToken: { queueToken }, writeWebhookToken: { queueToken = $0 }, startWebhookSync: false
        )
        StubWebhookProtocol.requests = []
        StubWebhookProtocol.onFirstRequest = { request in
            Task { @MainActor in
                precondition(redirectedStore.configureWebhook(url: "https://corrected.example/check-in",
                                                              token: "corrected-token", enabled: true))
                request.respond()
            }
        }
        await redirectedStore.syncWebhook(force: true)
        precondition(redirectedStore.pendingCheckIns.isEmpty && StubWebhookProtocol.requests.count == 2)
        precondition(StubWebhookProtocol.requests[0].url?.host == "original.example")
        precondition(StubWebhookProtocol.requests[1].url?.host == "corrected.example")
        precondition(StubWebhookProtocol.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer corrected-token",
                     "The next request must use the corrected endpoint and token.")
        print("PASS: pause during delivery and update endpoint/token before the next queued request")
        print("PASS: migration, atomic submission, offline restart, retry, acknowledgment, idempotency, auth, payload and test isolation")
        print("PASS: reference form fields, selected date, regular versus deep work, preparation persistence and payload")
    }
}
