import SwiftUI

struct YearProgressView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let progress = YearProgress(now: timeline.date, calendar: TrackerCalendar.calendar)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Year Elapsed")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("See how much of the current year has passed.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Desktop widget")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            DesktopWidgetVisibilityToggle(widget: .yearElapsed) { visible in
                                if visible {
                                    YearProgressDesktopPanelController.shared.present()
                                } else {
                                    YearProgressDesktopPanelController.shared.dismiss()
                                }
                            }
                        }

                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(progress.fractionElapsed, format: .percent.precision(.fractionLength(1)))
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.indigo)
                                Text("of \(String(progress.year)) elapsed")
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 8) {
                                Text("\(progress.daysElapsed) days elapsed")
                                    .font(.headline.monospacedDigit())
                                Text("\(progress.daysRemaining) days remaining")
                                    .font(.headline.monospacedDigit())
                                Text("Remaining days include today.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(20)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 12) {
                        YearProgressGrid(year: progress.year, now: timeline.date)
                            .frame(height: 280)

                        HStack(spacing: 18) {
                            Label("Past days", systemImage: "xmark")
                                .foregroundStyle(.indigo)
                            Label("Today", systemImage: "square")
                                .foregroundStyle(.indigo.opacity(0.58))
                            Label("Upcoming days", systemImage: "square")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                    .padding(20)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 20))
                }
                .padding(28)
            }
        }
        .navigationTitle("Year Elapsed")
    }
}
