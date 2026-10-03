import SwiftUI

struct HourCheckInsView: View {
    @ObservedObject var store: WallStore
    @State private var form = HourCheckInForm()
    @State private var submissionID = UUID()
    @State private var savedMessage: String?
    @Environment(\.openSettings) private var openSettings
    @AppStorage("settingsTab") private var settingsTab = "general"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Finish hour")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("A quick record of what moved forward.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 24) {
                        DatePicker("Date", selection: $form.date, displayedComponents: .date)
                        Picker("Category", selection: $form.category) {
                            Text("Select a category").tag(Optional<HourCategory>.none)
                            ForEach(HourCategory.allCases) { category in
                                Text(category.rawValue).tag(Optional(category))
                            }
                        }
                    }
                    Toggle("This was a deep work hour.", isOn: $form.isDeepWork)
                        .toggleStyle(.checkbox)
                    answerField("What did you do during this hour?", text: $form.activity)
                    answerField("How many times was I distracted, and if I was, how?", text: $form.distractions)
                    Divider()
                    Text("Daily preparation").font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("I read the 10X Rule.", isOn: $form.preparation.read10XRule)
                        Toggle("I reviewed my Top Goals.", isOn: $form.preparation.reviewedTopGoals)
                        Toggle("I reviewed the 3.0 Version of Myself.", isOn: $form.preparation.reviewedVersionOfMyself)
                        Toggle("I read my Motivation List out loud.", isOn: $form.preparation.readMotivationListOutLoud)
                        Toggle("I read my Thought Habits.", isOn: $form.preparation.readThoughtHabits)
                        Toggle("I reviewed my vision board.", isOn: $form.preparation.reviewedVisionBoard)
                    }
                    .toggleStyle(.checkbox)
                    HStack {
                        Text("Saved on this Mac, even when offline.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(form.isDeepWork ? "Submit & log 1 hour" : "Submit check-in", systemImage: "checkmark") { submit() }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(form.validationMessage != nil)
                    }
                    if let savedMessage {
                        Label(savedMessage, systemImage: "checkmark.circle.fill")
                            .font(.callout).foregroundStyle(.green)
                    }
                }
                .padding(20)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: store.isOnline ? "arrow.triangle.2.circlepath" : "wifi.slash")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.webhookStatus).font(.callout)
                        Text("\(store.pendingCheckIns.count) pending · \(store.hourCheckIns.count) check-ins saved")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.webhookSettings.isEnabled && !store.pendingCheckIns.isEmpty {
                        Button("Retry now") { Task { await store.syncWebhook(force: true) } }
                            .disabled(store.isSyncingWebhook || store.isTestingWebhook)
                    }
                    Button("Webhook settings") {
                        settingsTab = "webhook"
                        openSettings()
                    }
                }

                if !store.hourCheckIns.isEmpty {
                    Text("Recent check-ins").font(.headline)
                    ForEach(store.hourCheckIns.reversed().prefix(50)) { checkIn in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                if !checkIn.notes.isEmpty { Text(checkIn.notes).textSelection(.enabled) }
                                if let form = checkIn.form {
                                    Text("Distractions: \(form.distractions)").textSelection(.enabled)
                                    PreparationSummary(preparation: form.preparation)
                                }
                                Text("Submission ID: \(checkIn.id.uuidString)")
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                if let error = checkIn.lastDeliveryError {
                                    Text(error).font(.caption).foregroundStyle(.orange)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(checkIn.summary).font(.body.weight(.medium))
                                    Text(checkIn.completedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let form = checkIn.form {
                                        Text("\(checkIn.day) · \(form.category?.rawValue ?? "Other") · \(form.isDeepWork ? "Deep work" : "Regular hour")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Label(checkIn.deliveredAt == nil ? "Pending" : "Sent",
                                      systemImage: checkIn.deliveredAt == nil ? "clock" : "checkmark.circle")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("Hour Check-ins")
    }

    private func answerField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            TextEditor(text: text)
                .font(.body)
                .padding(6)
                .frame(height: 68)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                .accessibilityLabel(title)
        }
    }

    private func submit() {
        let date = Date()
        let submittedForm = form
        guard store.finishHour(id: submissionID, form: submittedForm, at: date) else { return }
        form = HourCheckInForm()
        submissionID = UUID()
        savedMessage = submittedForm.isDeepWork ? "Check-in saved · 1 deep work hour logged" : "Check-in saved"
        let hours = store.deepWorkHours(on: submittedForm.date)
        if submittedForm.isDeepWork && Calendar.current.isDateInToday(submittedForm.date) && hours >= DeepWork.dailyGoalHours {
            DeepWorkCelebrationPresenter.shared.present(
                hours: hours,
                streak: ConsistencyStreak.current(
                    completedDays: store.completedDays, through: date, calendar: TrackerCalendar.calendar
                ),
                hideApplicationOnDismiss: false
            )
        }
    }
}

private struct PreparationSummary: View {
    let preparation: DailyPreparation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Daily preparation").font(.caption.weight(.semibold))
            item("10X Rule", preparation.read10XRule)
            item("Top Goals", preparation.reviewedTopGoals)
            item("3.0 Version of Myself", preparation.reviewedVersionOfMyself)
            item("Motivation List out loud", preparation.readMotivationListOutLoud)
            item("Thought Habits", preparation.readThoughtHabits)
            item("Vision board", preparation.reviewedVisionBoard)
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func item(_ title: String, _ checked: Bool) -> some View {
        Label(title, systemImage: checked ? "checkmark.square" : "square")
    }
}

struct WebhookSettingsView: View {
    @ObservedObject var store: WallStore
    @State private var url = ""
    @State private var token = ""
    @State private var enabled = false
    @State private var saved = false
    @State private var tokenLoaded = false
    @State private var savedToken = ""
    @State private var settingsError: String?

    private var isBusy: Bool { store.isSyncingWebhook || store.isTestingWebhook }
    private var hasChanges: Bool {
        url != store.webhookSettings.url || enabled != store.webhookSettings.isEnabled || token != savedToken
    }

    var body: some View {
        Form {
            Section {
                Toggle("Sync check-ins to a webhook", isOn: $enabled)
                TextField("Webhook URL", text: $url, prompt: Text("https://…"))
                SecureField("Bearer token (optional)", text: $token)
                Text("The token is stored in Keychain and sent in the Authorization header.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(store.pendingCheckIns.count) pending check-ins will be sent to the configured URL when sync is enabled.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Save") {
                        saved = store.configureWebhook(url: url, token: token, enabled: enabled)
                        if saved {
                            url = store.webhookSettings.url
                            savedToken = token
                            settingsError = nil
                        } else { settingsError = store.lastError }
                    }
                    .disabled(store.isTestingWebhook || !tokenLoaded)
                    if saved { Label("Saved", systemImage: "checkmark").foregroundStyle(.green) }
                    Spacer()
                    Button(store.isTestingWebhook ? "Sending test…" : "Send test") {
                        Task { await store.sendWebhookTest() }
                    }
                    .disabled(isBusy || hasChanges || store.webhookSettings.url.isEmpty)
                }
            } header: { Text("Webhook") }

            Section {
                Text(store.webhookStatus)
                Text("\(store.pendingCheckIns.count) pending submissions")
                    .foregroundStyle(.secondary)
                Button("Retry pending now") { Task { await store.syncWebhook(force: true) } }
                    .disabled(isBusy || !store.webhookSettings.isEnabled || store.pendingCheckIns.isEmpty)
                if let result = store.webhookTestResult {
                    Text(result).font(.callout).textSelection(.enabled)
                }
                if let settingsError { Text(settingsError).foregroundStyle(.red) }
            } header: { Text("Delivery") }

            Section {
                Text("Connect your automation to this URL and map the JSON fields into your sheet or other destination. A test sends webhook.test with zero hours.")
                Text("Use submission_id to prevent duplicate rows. Digital Wall retries until the webhook returns HTTP 2xx, including after restarting the app.")
            } header: { Text("Automation setup") }
        }
        .formStyle(.grouped)
        .onAppear {
            url = store.webhookSettings.url
            enabled = store.webhookSettings.isEnabled
            do {
                token = try WebhookSecret.read()
                savedToken = token
                tokenLoaded = true
                saved = true
            } catch {
                settingsError = error.localizedDescription
                tokenLoaded = false
            }
        }
        .onChange(of: url) { _, _ in saved = false }
        .onChange(of: token) { _, _ in saved = false }
        .onChange(of: enabled) { _, _ in saved = false }
    }
}
