import AppKit
import SwiftUI

enum DesktopPanelAnchor {
    case topRight
    case topLeft
    case bottomRight
    case bottomLeft
}

struct DesktopWidgetSnapResult {
    var frame: NSRect
    var verticalGuide: CGFloat?
    var horizontalGuide: CGFloat?
}

@MainActor
enum DesktopPanelSupport {
    static let minimumWidgetSpacing: CGFloat = 4

    static func migratedFrame(
        currentSize: NSSize,
        legacyFrame: NSRect,
        visibleFrame: NSRect
    ) -> NSRect {
        let width = min(currentSize.width, visibleFrame.width)
        let height = min(currentSize.height, visibleFrame.height)
        let size = NSSize(width: width, height: height)
        let maxX = visibleFrame.maxX - width
        let maxY = visibleFrame.maxY - height
        let origin = NSPoint(
            x: min(max(legacyFrame.minX, visibleFrame.minX), maxX),
            y: min(max(legacyFrame.minY, visibleFrame.minY), maxY)
        )
        return NSRect(origin: origin, size: size)
    }

    static func makePanel<Content: View>(
        initialSize: NSSize,
        minimumSize: NSSize,
        frameAutosaveName: String,
        defaultAnchor: DesktopPanelAnchor = .topRight,
        defaultOffset: NSPoint = NSPoint(x: 36, y: 36),
        @ViewBuilder content: () -> Content
    ) -> DesktopWallPanel {
        let screen = screenUnderPointer() ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let origin: NSPoint
        switch defaultAnchor {
        case .topRight:
            origin = NSPoint(
                x: visibleFrame.maxX - initialSize.width - defaultOffset.x,
                y: visibleFrame.maxY - initialSize.height - defaultOffset.y
            )
        case .topLeft:
            origin = NSPoint(
                x: visibleFrame.minX + defaultOffset.x,
                y: visibleFrame.maxY - initialSize.height - defaultOffset.y
            )
        case .bottomRight:
            origin = NSPoint(
                x: visibleFrame.maxX - initialSize.width - defaultOffset.x,
                y: visibleFrame.minY + defaultOffset.y
            )
        case .bottomLeft:
            origin = NSPoint(
                x: visibleFrame.minX + defaultOffset.x,
                y: visibleFrame.minY + defaultOffset.y
            )
        }
        let panel = DesktopWallPanel(
            contentRect: NSRect(origin: origin, size: initialSize),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: content())
        panel.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        )
        panel.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.setContentEditing(false)
        panel.isExcludedFromWindowsMenu = true
        panel.minSize = minimumSize
        panel.setFrameAutosaveName(frameAutosaveName)
        DesktopWidgetSpacingCoordinator.shared.register(panel)
        return panel
    }

    static func spacedFrame(
        _ proposedFrame: NSRect,
        avoiding occupiedFrames: [NSRect],
        within visibleFrame: NSRect,
        spacing: CGFloat = 4
    ) -> NSRect {
        guard !occupiedFrames.isEmpty else {
            return clampedFrame(proposedFrame, within: visibleFrame)
        }

        let exclusionFrames = occupiedFrames.map {
            $0.insetBy(dx: -spacing, dy: -spacing)
        }
        var candidate = clampedFrame(proposedFrame, within: visibleFrame)
        var visitedFrames = Set<String>()
        let maximumPasses = max(4, exclusionFrames.count * 4)

        for _ in 0..<maximumPasses {
            let currentConflicts = conflictCount(candidate, exclusionFrames: exclusionFrames)
            guard currentConflicts > 0 else { break }

            let frameKey = "\(candidate.minX),\(candidate.minY)"
            guard visitedFrames.insert(frameKey).inserted else { break }

            let alternatives = exclusionFrames.flatMap { exclusion -> [NSRect] in
                [
                    NSRect(
                        x: exclusion.minX - candidate.width,
                        y: candidate.minY,
                        width: candidate.width,
                        height: candidate.height
                    ),
                    NSRect(
                        x: exclusion.maxX,
                        y: candidate.minY,
                        width: candidate.width,
                        height: candidate.height
                    ),
                    NSRect(
                        x: candidate.minX,
                        y: exclusion.minY - candidate.height,
                        width: candidate.width,
                        height: candidate.height
                    ),
                    NSRect(
                        x: candidate.minX,
                        y: exclusion.maxY,
                        width: candidate.width,
                        height: candidate.height
                    )
                ]
            }
            .map { clampedFrame($0, within: visibleFrame) }

            guard let best = alternatives.min(by: { first, second in
                let firstScore = conflictCount(first, exclusionFrames: exclusionFrames)
                let secondScore = conflictCount(second, exclusionFrames: exclusionFrames)
                if firstScore != secondScore { return firstScore < secondScore }
                return squaredDistance(from: proposedFrame.origin, to: first.origin)
                    < squaredDistance(from: proposedFrame.origin, to: second.origin)
            }) else { break }

            let bestConflicts = conflictCount(best, exclusionFrames: exclusionFrames)
            guard bestConflicts < currentConflicts || best != candidate else { break }
            candidate = best
        }

        return candidate
    }

    static func constrainedFrame(
        _ proposedFrame: NSRect,
        from previousFrame: NSRect,
        avoiding occupiedFrames: [NSRect],
        within visibleFrame: NSRect,
        spacing: CGFloat = 4
    ) -> NSRect {
        let exclusionFrames = occupiedFrames.map {
            $0.insetBy(dx: -spacing, dy: -spacing)
        }
        var candidate = clampedFrame(proposedFrame, within: visibleFrame)

        for exclusion in exclusionFrames {
            var barriers: [NSRect] = []

            if previousFrame.maxX <= exclusion.minX,
               candidate.maxX > exclusion.minX,
               candidate.maxY > exclusion.minY,
               candidate.minY < exclusion.maxY {
                barriers.append(NSRect(
                    x: exclusion.minX - candidate.width,
                    y: candidate.minY,
                    width: candidate.width,
                    height: candidate.height
                ))
            }

            if previousFrame.minX >= exclusion.maxX,
               candidate.minX < exclusion.maxX,
               candidate.maxY > exclusion.minY,
               candidate.minY < exclusion.maxY {
                barriers.append(NSRect(
                    x: exclusion.maxX,
                    y: candidate.minY,
                    width: candidate.width,
                    height: candidate.height
                ))
            }

            if previousFrame.maxY <= exclusion.minY,
               candidate.maxY > exclusion.minY,
               candidate.maxX > exclusion.minX,
               candidate.minX < exclusion.maxX {
                barriers.append(NSRect(
                    x: candidate.minX,
                    y: exclusion.minY - candidate.height,
                    width: candidate.width,
                    height: candidate.height
                ))
            }

            if previousFrame.minY >= exclusion.maxY,
               candidate.minY < exclusion.maxY,
               candidate.maxX > exclusion.minX,
               candidate.minX < exclusion.maxX {
                barriers.append(NSRect(
                    x: candidate.minX,
                    y: exclusion.maxY,
                    width: candidate.width,
                    height: candidate.height
                ))
            }

            if let closestBarrier = barriers.min(by: {
                squaredDistance(from: proposedFrame.origin, to: $0.origin)
                    < squaredDistance(from: proposedFrame.origin, to: $1.origin)
            }) {
                candidate = clampedFrame(closestBarrier, within: visibleFrame)
            } else if candidate.intersects(exclusion) {
                candidate = spacedFrame(
                    candidate,
                    avoiding: occupiedFrames,
                    within: visibleFrame,
                    spacing: spacing
                )
            }
        }

        return candidate
    }

    static func snappedFrame(
        _ proposedFrame: NSRect,
        to occupiedFrames: [NSRect],
        within visibleFrame: NSRect,
        spacing: CGFloat = 4,
        threshold: CGFloat = 5
    ) -> DesktopWidgetSnapResult {
        var horizontalCandidates: [(origin: CGFloat, guide: CGFloat)] = [
            (visibleFrame.minX, visibleFrame.minX),
            (visibleFrame.maxX - proposedFrame.width, visibleFrame.maxX)
        ]
        var verticalCandidates: [(origin: CGFloat, guide: CGFloat)] = [
            (visibleFrame.minY, visibleFrame.minY),
            (visibleFrame.maxY - proposedFrame.height, visibleFrame.maxY)
        ]

        for occupied in occupiedFrames {
            horizontalCandidates.append(contentsOf: [
                (occupied.minX, occupied.minX),
                (occupied.maxX - proposedFrame.width, occupied.maxX),
                (occupied.midX - proposedFrame.width / 2, occupied.midX)
            ])
            verticalCandidates.append(contentsOf: [
                (occupied.minY, occupied.minY),
                (occupied.maxY - proposedFrame.height, occupied.maxY),
                (occupied.midY - proposedFrame.height / 2, occupied.midY)
            ])

            let verticallyRelated = proposedFrame.maxY >= occupied.minY - threshold
                && proposedFrame.minY <= occupied.maxY + threshold
            if verticallyRelated {
                horizontalCandidates.append(contentsOf: [
                    (
                        occupied.minX - spacing - proposedFrame.width,
                        occupied.minX - spacing / 2
                    ),
                    (occupied.maxX + spacing, occupied.maxX + spacing / 2)
                ])
            }

            let horizontallyRelated = proposedFrame.maxX >= occupied.minX - threshold
                && proposedFrame.minX <= occupied.maxX + threshold
            if horizontallyRelated {
                verticalCandidates.append(contentsOf: [
                    (
                        occupied.minY - spacing - proposedFrame.height,
                        occupied.minY - spacing / 2
                    ),
                    (occupied.maxY + spacing, occupied.maxY + spacing / 2)
                ])
            }
        }

        var snappedFrame = proposedFrame
        var verticalGuide: CGFloat?
        var horizontalGuide: CGFloat?

        if let snap = closestSnap(
            to: proposedFrame.minX,
            candidates: horizontalCandidates,
            threshold: threshold
        ) {
            snappedFrame.origin.x = snap.value
            verticalGuide = snap.guide
        }

        if let snap = closestSnap(
            to: proposedFrame.minY,
            candidates: verticalCandidates,
            threshold: threshold
        ) {
            snappedFrame.origin.y = snap.value
            horizontalGuide = snap.guide
        }

        let clamped = clampedFrame(snappedFrame, within: visibleFrame)
        if abs(clamped.minX - snappedFrame.minX) > 0.25 { verticalGuide = nil }
        if abs(clamped.minY - snappedFrame.minY) > 0.25 { horizontalGuide = nil }
        return DesktopWidgetSnapResult(
            frame: clamped,
            verticalGuide: verticalGuide,
            horizontalGuide: horizontalGuide
        )
    }

    static func constrainedResizeFrame(
        _ proposedFrame: NSRect,
        from previousFrame: NSRect,
        avoiding occupiedFrames: [NSRect],
        minimumSize: NSSize,
        spacing: CGFloat = 4
    ) -> NSRect {
        let exclusionFrames = occupiedFrames.map {
            $0.insetBy(dx: -spacing, dy: -spacing)
        }
        var candidate = proposedFrame
        let activeEdges = resizedEdges(from: previousFrame, to: proposedFrame)

        for exclusion in exclusionFrames {
            if activeEdges.right,
               previousFrame.maxX <= exclusion.minX,
               candidate.maxX > exclusion.minX,
               rangesOverlap(candidate.minY, candidate.maxY, exclusion.minY, exclusion.maxY) {
                candidate.size.width = max(minimumSize.width, exclusion.minX - candidate.minX)
            }

            if activeEdges.left,
               previousFrame.minX >= exclusion.maxX,
               candidate.minX < exclusion.maxX,
               rangesOverlap(candidate.minY, candidate.maxY, exclusion.minY, exclusion.maxY) {
                let fixedMaximumX = candidate.maxX
                candidate.origin.x = min(exclusion.maxX, fixedMaximumX - minimumSize.width)
                candidate.size.width = fixedMaximumX - candidate.minX
            }

            if activeEdges.top,
               previousFrame.maxY <= exclusion.minY,
               candidate.maxY > exclusion.minY,
               rangesOverlap(candidate.minX, candidate.maxX, exclusion.minX, exclusion.maxX) {
                candidate.size.height = max(minimumSize.height, exclusion.minY - candidate.minY)
            }

            if activeEdges.bottom,
               previousFrame.minY >= exclusion.maxY,
               candidate.minY < exclusion.maxY,
               rangesOverlap(candidate.minX, candidate.maxX, exclusion.minX, exclusion.maxX) {
                let fixedMaximumY = candidate.maxY
                candidate.origin.y = min(exclusion.maxY, fixedMaximumY - minimumSize.height)
                candidate.size.height = fixedMaximumY - candidate.minY
            }
        }

        return candidate
    }

    static func snappedResizeFrame(
        _ proposedFrame: NSRect,
        from previousFrame: NSRect,
        to occupiedFrames: [NSRect],
        within visibleFrame: NSRect,
        minimumSize: NSSize,
        spacing: CGFloat = 4,
        threshold: CGFloat = 5
    ) -> DesktopWidgetSnapResult {
        let activeEdges = resizedEdges(from: previousFrame, to: proposedFrame)
        let edgeTargets = [visibleFrame.minX, visibleFrame.maxX]
            + occupiedFrames.flatMap {
                [$0.minX, $0.maxX, $0.minX - spacing, $0.maxX + spacing]
            }
        let verticalTargets = [visibleFrame.minY, visibleFrame.maxY]
            + occupiedFrames.flatMap {
                [$0.minY, $0.maxY, $0.minY - spacing, $0.maxY + spacing]
            }
        var candidate = proposedFrame
        var verticalGuide: CGFloat?
        var horizontalGuide: CGFloat?

        if activeEdges.left,
           let target = closestValue(to: proposedFrame.minX, values: edgeTargets, threshold: threshold),
           proposedFrame.maxX - target >= minimumSize.width {
            let maximumX = proposedFrame.maxX
            candidate.origin.x = target
            candidate.size.width = maximumX - target
            verticalGuide = target
        } else if activeEdges.right,
                  let target = closestValue(to: proposedFrame.maxX, values: edgeTargets, threshold: threshold),
                  target - proposedFrame.minX >= minimumSize.width {
            candidate.size.width = target - proposedFrame.minX
            verticalGuide = target
        }

        if activeEdges.bottom,
           let target = closestValue(to: proposedFrame.minY, values: verticalTargets, threshold: threshold),
           proposedFrame.maxY - target >= minimumSize.height {
            let maximumY = proposedFrame.maxY
            candidate.origin.y = target
            candidate.size.height = maximumY - target
            horizontalGuide = target
        } else if activeEdges.top,
                  let target = closestValue(to: proposedFrame.maxY, values: verticalTargets, threshold: threshold),
                  target - proposedFrame.minY >= minimumSize.height {
            candidate.size.height = target - proposedFrame.minY
            horizontalGuide = target
        }

        return DesktopWidgetSnapResult(
            frame: candidate,
            verticalGuide: verticalGuide,
            horizontalGuide: horizontalGuide
        )
    }

    private static func clampedFrame(_ frame: NSRect, within visibleFrame: NSRect) -> NSRect {
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - frame.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - frame.height)
        return NSRect(
            x: min(max(frame.minX, visibleFrame.minX), maximumX),
            y: min(max(frame.minY, visibleFrame.minY), maximumY),
            width: frame.width,
            height: frame.height
        )
    }

    private static func conflictCount(
        _ frame: NSRect,
        exclusionFrames: [NSRect]
    ) -> Int {
        exclusionFrames.reduce(into: 0) { count, exclusion in
            if frame.intersects(exclusion) { count += 1 }
        }
    }

    private static func squaredDistance(from first: NSPoint, to second: NSPoint) -> CGFloat {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return deltaX * deltaX + deltaY * deltaY
    }

    private static func closestSnap(
        to value: CGFloat,
        candidates: [(origin: CGFloat, guide: CGFloat)],
        threshold: CGFloat
    ) -> (value: CGFloat, guide: CGFloat)? {
        candidates
            .map { (value: $0.origin, guide: $0.guide, distance: abs(value - $0.origin)) }
            .filter { $0.distance <= threshold }
            .min { $0.distance < $1.distance }
            .map { (value: $0.value, guide: $0.guide) }
    }

    private static func closestValue(
        to value: CGFloat,
        values: [CGFloat],
        threshold: CGFloat
    ) -> CGFloat? {
        values
            .map { (value: $0, distance: abs(value - $0)) }
            .filter { $0.distance <= threshold }
            .min { $0.distance < $1.distance }?
            .value
    }

    private static func resizedEdges(
        from previousFrame: NSRect,
        to proposedFrame: NSRect
    ) -> (left: Bool, right: Bool, bottom: Bool, top: Bool) {
        let tolerance: CGFloat = 0.25
        return (
            abs(previousFrame.minX - proposedFrame.minX) > tolerance,
            abs(previousFrame.maxX - proposedFrame.maxX) > tolerance,
            abs(previousFrame.minY - proposedFrame.minY) > tolerance,
            abs(previousFrame.maxY - proposedFrame.maxY) > tolerance
        )
    }

    private static func rangesOverlap(
        _ firstMinimum: CGFloat,
        _ firstMaximum: CGFloat,
        _ secondMinimum: CGFloat,
        _ secondMaximum: CGFloat
    ) -> Bool {
        firstMaximum > secondMinimum && firstMinimum < secondMaximum
    }

    private static func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
    }
}

@MainActor
private final class DesktopWidgetSpacingCoordinator: NSObject {
    static let shared = DesktopWidgetSpacingCoordinator()

    private var pendingAdjustments: [ObjectIdentifier: DispatchWorkItem] = [:]
    private var adjustingPanels: Set<ObjectIdentifier> = []
    private var lastValidFrames: [ObjectIdentifier: NSRect] = [:]

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidFinishResizing(_:)),
            name: NSWindow.didEndLiveResizeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: nil
        )
    }

    func register(_ panel: DesktopWallPanel) {
        lastValidFrames[ObjectIdentifier(panel)] = panel.frame
        scheduleAdjustment(for: panel, delay: 0.1)
    }

    @objc private func panelDidMove(_ notification: Notification) {
        guard let panel = notification.object as? DesktopWallPanel,
              !panel.inLiveResize,
              !adjustingPanels.contains(ObjectIdentifier(panel)) else { return }
        pendingAdjustments[ObjectIdentifier(panel)]?.cancel()
        constrainLiveMovement(of: panel)
    }

    @objc private func panelDidResize(_ notification: Notification) {
        guard let panel = notification.object as? DesktopWallPanel,
              panel.inLiveResize,
              !adjustingPanels.contains(ObjectIdentifier(panel)) else { return }
        constrainLiveResize(of: panel)
    }

    @objc private func panelDidFinishResizing(_ notification: Notification) {
        guard let panel = notification.object as? DesktopWallPanel else { return }
        DesktopAlignmentGuideController.shared.scheduleHide()
        scheduleAdjustment(for: panel, delay: 0)
    }

    private func scheduleAdjustment(for panel: DesktopWallPanel, delay: TimeInterval) {
        let identifier = ObjectIdentifier(panel)
        pendingAdjustments[identifier]?.cancel()

        let workItem = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.pendingAdjustments[identifier] = nil
            self.adjust(panel)
        }
        pendingAdjustments[identifier] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func adjust(_ panel: DesktopWallPanel) {
        guard panel.isVisible else { return }

        let occupiedFrames = NSApp.windows.compactMap { window -> NSRect? in
            guard let other = window as? DesktopWallPanel,
                  other !== panel,
                  other.isVisible else { return nil }
            return other.frame
        }
        guard !occupiedFrames.isEmpty else { return }

        let visibleFrame = panel.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? panel.frame
        let adjustedFrame = DesktopPanelSupport.spacedFrame(
            panel.frame,
            avoiding: occupiedFrames,
            within: visibleFrame
        )
        guard adjustedFrame != panel.frame else {
            lastValidFrames[ObjectIdentifier(panel)] = panel.frame
            return
        }

        let identifier = ObjectIdentifier(panel)
        adjustingPanels.insert(identifier)
        panel.setFrame(adjustedFrame, display: true, animate: false)
        adjustingPanels.remove(identifier)
        lastValidFrames[identifier] = adjustedFrame
    }

    private func constrainLiveMovement(of panel: DesktopWallPanel) {
        guard panel.isVisible else { return }

        let identifier = ObjectIdentifier(panel)
        let occupiedFrames = NSApp.windows.compactMap { window -> NSRect? in
            guard let other = window as? DesktopWallPanel,
                  other !== panel,
                  other.isVisible else { return nil }
            return other.frame
        }
        guard !occupiedFrames.isEmpty else {
            lastValidFrames[identifier] = panel.frame
            return
        }

        let visibleFrame = panel.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? panel.frame
        let previousFrame = lastValidFrames[identifier] ?? panel.frame
        let constrainedFrame = DesktopPanelSupport.constrainedFrame(
            panel.frame,
            from: previousFrame,
            avoiding: occupiedFrames,
            within: visibleFrame
        )
        let snapResult = DesktopPanelSupport.snappedFrame(
            constrainedFrame,
            to: occupiedFrames,
            within: visibleFrame
        )
        let adjustedFrame = DesktopPanelSupport.constrainedFrame(
            snapResult.frame,
            from: previousFrame,
            avoiding: occupiedFrames,
            within: visibleFrame
        )

        if adjustedFrame != panel.frame {
            adjustingPanels.insert(identifier)
            panel.setFrame(adjustedFrame, display: true, animate: false)
            adjustingPanels.remove(identifier)
        }
        lastValidFrames[identifier] = adjustedFrame
        showGuides(
            vertical: adjustedFrame == snapResult.frame ? snapResult.verticalGuide : nil,
            horizontal: adjustedFrame == snapResult.frame ? snapResult.horizontalGuide : nil,
            for: panel
        )
    }

    private func constrainLiveResize(of panel: DesktopWallPanel) {
        guard panel.isVisible else { return }

        let identifier = ObjectIdentifier(panel)
        let previousFrame = lastValidFrames[identifier] ?? panel.frame
        let occupiedFrames = NSApp.windows.compactMap { window -> NSRect? in
            guard let other = window as? DesktopWallPanel,
                  other !== panel,
                  other.isVisible else { return nil }
            return other.frame
        }
        let visibleFrame = panel.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? panel.frame
        let constrainedFrame = DesktopPanelSupport.constrainedResizeFrame(
            panel.frame,
            from: previousFrame,
            avoiding: occupiedFrames,
            minimumSize: panel.minSize
        )
        let snapResult = DesktopPanelSupport.snappedResizeFrame(
            constrainedFrame,
            from: previousFrame,
            to: occupiedFrames,
            within: visibleFrame,
            minimumSize: panel.minSize
        )
        let adjustedFrame = DesktopPanelSupport.constrainedResizeFrame(
            snapResult.frame,
            from: previousFrame,
            avoiding: occupiedFrames,
            minimumSize: panel.minSize
        )

        if adjustedFrame != panel.frame {
            adjustingPanels.insert(identifier)
            panel.setFrame(adjustedFrame, display: true, animate: false)
            adjustingPanels.remove(identifier)
        }
        lastValidFrames[identifier] = adjustedFrame
        showGuides(
            vertical: adjustedFrame == snapResult.frame ? snapResult.verticalGuide : nil,
            horizontal: adjustedFrame == snapResult.frame ? snapResult.horizontalGuide : nil,
            for: panel
        )
    }

    private func showGuides(
        vertical: CGFloat?,
        horizontal: CGFloat?,
        for panel: DesktopWallPanel
    ) {
        guard vertical != nil || horizontal != nil,
              let screen = panel.screen ?? NSScreen.main else {
            DesktopAlignmentGuideController.shared.hide()
            return
        }
        DesktopAlignmentGuideController.shared.show(
            vertical: vertical,
            horizontal: horizontal,
            on: screen
        )
    }
}

@MainActor
private final class DesktopAlignmentGuideController {
    static let shared = DesktopAlignmentGuideController()

    private var panel: NSPanel?
    private var guideView: DesktopAlignmentGuideView?
    private var hideWorkItem: DispatchWorkItem?

    private init() {}

    func show(vertical: CGFloat?, horizontal: CGFloat?, on screen: NSScreen) {
        let panel = guidePanel(for: screen)
        guideView?.verticalGuide = vertical
        guideView?.horizontalGuide = horizontal
        guideView?.screenFrame = screen.visibleFrame
        guideView?.needsDisplay = true
        panel.orderFrontRegardless()
        scheduleHide()
    }

    func scheduleHide() {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.hide() }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        panel?.orderOut(nil)
    }

    private func guidePanel(for screen: NSScreen) -> NSPanel {
        if let panel, panel.frame == screen.visibleFrame { return panel }

        panel?.orderOut(nil)
        let guideView = DesktopAlignmentGuideView(frame: NSRect(origin: .zero, size: screen.visibleFrame.size))
        let panel = NSPanel(
            contentRect: screen.visibleFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = guideView
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)
        panel.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true
        self.panel = panel
        self.guideView = guideView
        return panel
    }
}

private final class DesktopAlignmentGuideView: NSView {
    var verticalGuide: CGFloat?
    var horizontalGuide: CGFloat?
    var screenFrame = NSRect.zero

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard verticalGuide != nil || horizontalGuide != nil else { return }

        NSColor.lightGray.withAlphaComponent(0.72).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.setLineDash([4, 4], count: 2, phase: 0)

        if let verticalGuide {
            let x = verticalGuide - screenFrame.minX
            path.move(to: NSPoint(x: x, y: bounds.minY))
            path.line(to: NSPoint(x: x, y: bounds.maxY))
        }

        if let horizontalGuide {
            let y = horizontalGuide - screenFrame.minY
            path.move(to: NSPoint(x: bounds.minX, y: y))
            path.line(to: NSPoint(x: bounds.maxX, y: y))
        }

        path.stroke()
    }
}

final class DesktopWallPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setContentEditing(_ isEditing: Bool) {
        isMovableByWindowBackground = !isEditing
    }
}

struct DesktopPanelBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .ignoresSafeArea()
    }
}

struct DesktopPanelControlMenu<Items: View>: View {
    let isVisible: Bool
    private let items: Items

    init(isVisible: Bool, @ViewBuilder items: () -> Items) {
        self.isVisible = isVisible
        self.items = items()
    }

    var body: some View {
        Menu {
            items
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.bold())
                .frame(width: 24, height: 24)
                .background(.ultraThinMaterial, in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .animation(.easeOut(duration: 0.12), value: isVisible)
    }
}
