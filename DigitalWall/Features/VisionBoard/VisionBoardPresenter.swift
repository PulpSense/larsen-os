import AppKit
import SwiftUI

@MainActor
final class VisionBoardPresenter {
    static let shared = VisionBoardPresenter()

    private let overlay = FullScreenOverlayController()

    private init() {}

    func present(images: [VisionImage], hideApplicationOnDismiss: Bool = false) {
        present(
            items: images.map {
                PresentedVisionImage(
                    id: $0.id.uuidString,
                    url: WallPersistence.imageURL(for: $0),
                    phrase: $0.phrase,
                    displayMode: $0.displayMode,
                    focalPoint: $0.focalPoint
                )
            },
            hideApplicationOnDismiss: hideApplicationOnDismiss
        )
    }

    func present(imageURLs: [URL], hideApplicationOnDismiss: Bool = false) {
        present(
            items: imageURLs.map { PresentedVisionImage(id: $0.path, url: $0, phrase: "") },
            hideApplicationOnDismiss: hideApplicationOnDismiss
        )
    }

    private func present(items: [PresentedVisionImage], hideApplicationOnDismiss: Bool) {
        guard !items.isEmpty else { return }
        overlay.present(
            hideApplicationOnDismiss: hideApplicationOnDismiss,
            dismissOnKeyDown: { _ in true }
        ) { dismiss in
            ImmersiveVisionBoard(images: items, dismiss: dismiss)
        }
    }

    /// Keeps milestone feedback and focus restoration in the same submission sequence.
    func presentAfterCheckIn(
        store: WallStore,
        date: Date,
        isDeepWork: Bool,
        showVisionBoard: Bool? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        let shouldShowVisionBoard = showVisionBoard ?? CheckInFlowPreferences.manualVisionBoard
        let showCarousel = { [self] in
            guard shouldShowVisionBoard else { onDismiss?(); return }
            let boardID = DashboardNavigation.shared.boardID(in: store)
            let images = !store.visionBoardPrivacyEnabled
                ? boardID.map { store.images(for: $0) } ?? []
                : []
            presentCarousel(images: images.shuffled(), onDismiss: onDismiss)
        }
        let hours = store.deepWorkHours(on: date)
        if isDeepWork, Calendar.current.isDateInToday(date),
           DeepWorkCelebrationMilestone.forHours(hours) != nil {
            DeepWorkCelebrationPresenter.shared.present(
                hours: hours,
                streak: ConsistencyStreak.current(
                    completedDays: store.completedDays, through: Date(), calendar: TrackerCalendar.calendar
                ),
                hideApplicationOnDismiss: false,
                onDismiss: showCarousel
            )
        } else {
            showCarousel()
        }
    }

    func presentCarousel(images: [VisionImage], onDismiss: (() -> Void)? = nil) {
        // Skip missing files rather than showing empty slides.
        let items = images.compactMap { image -> PresentedVisionImage? in
            let url = WallPersistence.imageURL(for: image)
            guard NSImage(contentsOf: url) != nil else { return nil }
            return PresentedVisionImage(
                id: image.id.uuidString, url: url, phrase: image.phrase,
                displayMode: image.displayMode, focalPoint: image.focalPoint
            )
        }
        guard !items.isEmpty else { onDismiss?(); return }
        overlay.present(
            hideApplicationOnDismiss: false,
            nonactivating: true,
            preferredSize: NSSize(width: 840, height: 680),
            dimBackground: true,
            onDismiss: onDismiss,
            dismissOnKeyDown: { _ in true }
        ) { dismiss in
            VisionBoardCarousel(images: items, dismiss: dismiss)
        }
    }

    func dismiss() {
        overlay.dismiss()
    }
}

private struct PresentedVisionImage: Identifiable {
    let id: String
    let url: URL
    let phrase: String
    var displayMode: VisionImageDisplayMode = .fit
    var focalPoint: VisionImageFocalPoint = .center
}

private struct ImmersiveVisionBoard: View {
    let images: [PresentedVisionImage]
    let dismiss: () -> Void
    @State private var appeared = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(.black.opacity(appeared ? 0.48 : 0))
                    .background(.ultraThinMaterial)

                ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                    visionCard(image, index: index, canvas: proxy.size)
                }

                VStack {
                    Spacer()
                    Text("Press any key or click anywhere to return")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.32), in: Capsule())
                        .padding(.bottom, 28)
                }
                .opacity(appeared ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: dismiss)
            .onAppear {
                withAnimation(.spring(response: 0.65, dampingFraction: 0.82)) {
                    appeared = true
                }
            }
        }
        .ignoresSafeArea()
    }

    private func visionCard(_ image: PresentedVisionImage, index: Int, canvas: CGSize) -> some View {
        let layout = VisionBoardCardLayout(index: index, imageCount: images.count, canvas: canvas)
        let width = layout.imageSize.width
        let maximumCardHeight = layout.imageSize.height

        return VStack(spacing: 10) {
            Group {
                if let nsImage = NSImage(contentsOf: image.url) {
                    VisionImageContentView(nsImage: nsImage, displayMode: image.displayMode, focalPoint: image.focalPoint)
                } else {
                    Color.secondary.opacity(0.12)
                }
            }
                .frame(
                    width: image.displayMode == .fill ? width : nil,
                    height: image.displayMode == .fill ? maximumCardHeight : nil
                )
                .frame(maxWidth: width, maxHeight: maximumCardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if !image.phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(image.phrase)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
        .padding(10)
        .background(.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        .rotationEffect(.degrees(layout.rotation))
        .position(layout.position)
        .scaleEffect(appeared ? 1 : 0.7)
        .opacity(appeared ? 1 : 0)
        .animation(
            .spring(response: 0.58, dampingFraction: 0.78)
                .delay(Double(index) * 0.055),
            value: appeared
        )
    }
}

private struct VisionBoardCarousel: View {
    let images: [PresentedVisionImage]
    let dismiss: () -> Void
    @State private var index = 0
    @State private var finished = false

    var body: some View {
        let image = images[index]
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if finished {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.green)
                    Text("Vision board complete")
                        .font(.title2.weight(.semibold))
                    Text("Keep your vision in mind.")
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                VStack(spacing: 16) {
                    if let nsImage = NSImage(contentsOf: image.url) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if !image.phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(image.phrase)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("\(index + 1) of \(images.count) · Press any key or click to return")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .foregroundStyle(.white)
                .padding(24)
            }
        }
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .task {
            for nextIndex in images.indices.dropFirst() {
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
                guard !Task.isCancelled else { return }
                index = nextIndex
            }
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            guard !Task.isCancelled else { return }
            finished = true
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}
