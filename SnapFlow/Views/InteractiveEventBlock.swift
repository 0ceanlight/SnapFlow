import SwiftUI
import EventKit
import AppKit

// MARK: - InteractiveEventBlock

struct InteractiveEventBlock: View {
    let event: EKEvent
    let todayStart: Date
    let containerWidth: CGFloat
    let pxPerMin: CGFloat
    let color: Color
    let allEvents: [EKEvent]
    
    let isSelected: Bool
    let selectedEventIDs: Set<String>
    let getIsSelected: () -> Bool
    
    let onDoubleTap: () -> Void
    let onTap: (NSEvent.ModifierFlags) -> Void
    let onDragStartUnselected: () -> Void
    
    @Binding var groupDragDelta: CGFloat
    
    let onCommit: (Date, Date) -> Void
    let onCommitGroup: (TimeInterval) -> Void

    @AppStorage("snapping_enabled") private var snappingEnabled: Bool = true
    @AppStorage("hover_show_times") private var hoverShowTimes: Bool = true
    @AppStorage("hover_show_notes") private var hoverShowNotes: Bool = true

    @State private var moveOffset:   CGFloat = 0
    @State private var resizeOffset: CGFloat = 0
    @State private var topResizeOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var isHoveringEvent = false

    // MARK: - Design Tweaks
    // Modifiable variables for the event selection styling
    private let unselectedOpacity: Double = 0.45
    private let selectedOpacity: Double   = 1.0
    private let selectedBrightnessDelta: Double = 0.001
    private let selectedSaturationDelta: Double = 0.15
    private let unselectedTitleBrightnessDelta: Double = 0.8

    private let edgeHandleH: CGFloat = 10
    private let leftInset:   CGFloat = 46

    // MARK: - Snap helpers

    /// Snap a move-drag offset (pts) to nearby event edges. Returns the (possibly snapped) offset.
    private func snappedMoveOffset(_ rawPts: CGFloat) -> CGFloat {
        guard snappingEnabled else { return rawPts }
        let rawSec    = TimeInterval(rawPts / pxPerMin * 60)
        let candStart = event.startDate.addingTimeInterval(rawSec)
        let candEnd   = event.endDate.addingTimeInterval(rawSec)
        let threshold = TimeInterval(RulerHUDView.snapMarginMinutes * 60)
        var bestDist  = threshold
        var bestPts: CGFloat? = nil

        for other in allEvents {
            guard other.eventIdentifier != event.eventIdentifier else { continue }
            if isSelected && selectedEventIDs.contains(other.eventIdentifier) { continue }
            
            // start → other.end  (B coalesces after A)
            let d1 = abs(candStart.timeIntervalSince(other.endDate))
            if d1 < bestDist { bestDist = d1; bestPts = CGFloat(other.endDate.timeIntervalSince(event.startDate) / 60) * pxPerMin }
            // end → other.start  (B coalesces before C)
            let d2 = abs(candEnd.timeIntervalSince(other.startDate))
            if d2 < bestDist { bestDist = d2; bestPts = CGFloat(other.startDate.timeIntervalSince(event.endDate) / 60) * pxPerMin }
        }
        return bestPts ?? rawPts
    }

    /// Snap a resize offset (pts, end-edge only) to nearby event edges.
    private func snappedResizeOffset(_ rawPts: CGFloat, durationMins: CGFloat) -> CGFloat {
        guard snappingEnabled else { return rawPts }
        let rawSec    = TimeInterval(rawPts / pxPerMin * 60)
        let candEnd   = event.endDate.addingTimeInterval(rawSec)
        let threshold = TimeInterval(RulerHUDView.snapMarginMinutes * 60)
        let minDurSec = TimeInterval(5 * 60)
        var bestDist  = threshold
        var bestPts: CGFloat? = nil

        for other in allEvents {
            guard other.eventIdentifier != event.eventIdentifier else { continue }
            // end → other.start
            let d1 = abs(candEnd.timeIntervalSince(other.startDate))
            let snapSec1 = other.startDate.timeIntervalSince(event.endDate)
            if d1 < bestDist && event.endDate.timeIntervalSince(event.startDate) + snapSec1 >= minDurSec {
                bestDist = d1; bestPts = CGFloat(snapSec1 / 60) * pxPerMin
            }
            // end → other.end
            let d2 = abs(candEnd.timeIntervalSince(other.endDate))
            let snapSec2 = other.endDate.timeIntervalSince(event.endDate)
            if d2 < bestDist && event.endDate.timeIntervalSince(event.startDate) + snapSec2 >= minDurSec {
                bestDist = d2; bestPts = CGFloat(snapSec2 / 60) * pxPerMin
            }
        }
        // Clamp floor: never shrink below 5 min
        let floor = -(durationMins - 5) * pxPerMin
        return max(floor, bestPts ?? rawPts)
    }

    /// Snap a top-resize offset (pts, start-edge only) to nearby event edges.
    private func snappedTopResizeOffset(_ rawPts: CGFloat, durationMins: CGFloat) -> CGFloat {
        guard snappingEnabled else { return rawPts }
        let rawSec    = TimeInterval(rawPts / pxPerMin * 60)
        let candStart = event.startDate.addingTimeInterval(rawSec)
        let threshold = TimeInterval(RulerHUDView.snapMarginMinutes * 60)
        let minDurSec = TimeInterval(5 * 60)
        var bestDist  = threshold
        var bestPts: CGFloat? = nil

        for other in allEvents {
            guard other.eventIdentifier != event.eventIdentifier else { continue }
            // start → other.start
            let d1 = abs(candStart.timeIntervalSince(other.startDate))
            let snapSec1 = other.startDate.timeIntervalSince(event.startDate)
            if d1 < bestDist && event.endDate.timeIntervalSince(event.startDate) - snapSec1 >= minDurSec {
                bestDist = d1; bestPts = CGFloat(snapSec1 / 60) * pxPerMin
            }
            // start → other.end
            let d2 = abs(candStart.timeIntervalSince(other.endDate))
            let snapSec2 = other.endDate.timeIntervalSince(event.startDate)
            if d2 < bestDist && event.endDate.timeIntervalSince(event.startDate) - snapSec2 >= minDurSec {
                bestDist = d2; bestPts = CGFloat(snapSec2 / 60) * pxPerMin
            }
        }
        // Clamp roof: never shrink below 5 min
        let roof = (durationMins - 5) * pxPerMin
        return min(roof, bestPts ?? rawPts)
    }

    private var showPopover: Binding<Bool> {
        Binding(
            get: {
                if isDragging || !isHoveringEvent { return false }
                let hasNotes = event.notes != nil && !event.notes!.isEmpty
                return hoverShowTimes || (hoverShowNotes && hasNotes)
            },
            set: { if !$0 { isHoveringEvent = false } }
        )
    }

    var body: some View {
        let startMins    = RulerHUDView.minutesFromMidnight(event.startDate)
        let durationMins = CGFloat(event.endDate.timeIntervalSince(event.startDate) / 60)
        let blockH       = max(durationMins * pxPerMin + resizeOffset - topResizeOffset, 14)
        let yOffset      = startMins * pxPerMin + (isSelected ? groupDragDelta : moveOffset) + topResizeOffset
        let width        = containerWidth - leftInset - RulerHUDView.rightMargin

        ZStack(alignment: .topLeading) {
            // Body
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? color.adjusted(saturationDelta: selectedSaturationDelta, brightnessDelta: selectedBrightnessDelta).opacity(selectedOpacity) : color.opacity(isDragging ? selectedOpacity : unselectedOpacity))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(color.opacity(isSelected ? 0.0 : 0.5), lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    Text(event.title ?? "")
                        .font(.caption).bold()
                        .foregroundColor(isSelected ? .white : color.adjusted(brightnessDelta: unselectedTitleBrightnessDelta))
                        .lineLimit(2)
                        .padding(.horizontal, 7).padding(.top, 3)
                }
                .highPriorityGesture(DragGesture(minimumDistance: 1)
                    .onChanged { v in
                        withTransaction(Transaction(animation: nil)) {
                            isDragging = true
                            if !getIsSelected() {
                                onDragStartUnselected()
                            }
                            groupDragDelta = v.translation.height
                        }
                    }
                    .onEnded { v in
                        isDragging = false
                        let raw = v.translation.height
                        let snapped = snappedMoveOffset(raw)
                        let isEventSnapped = abs(snapped - raw) > 0.5
                        let finalPts = isEventSnapped ? snapped : snapToFive(raw / pxPerMin) * pxPerMin
                        let delta = TimeInterval(finalPts / pxPerMin * 60)
                        
                        if getIsSelected() {
                            groupDragDelta = 0
                            onCommitGroup(delta)
                        } else {
                            moveOffset = 0
                            onCommit(event.startDate.addingTimeInterval(delta),
                                     event.endDate.addingTimeInterval(delta))
                        }
                    }
                )
                .onHover { hovering in
                    isHoveringEvent = hovering
                }
                .popover(isPresented: showPopover, attachmentAnchor: .point(.trailing), arrowEdge: .trailing) {
                    EventHoverPopover(event: event, showTimes: hoverShowTimes, showNotes: hoverShowNotes)
                }
                .onTapGesture(count: 2) { onDoubleTap() }
                .onTapGesture(count: 1) { onTap(NSEvent.modifierFlags) }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .frame(height: 6)
                        .padding(.top, -2)
                        .onHover { hovering in
                            if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                        }
                        .highPriorityGesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                withTransaction(Transaction(animation: nil)) {
                                    isDragging = true
                                    topResizeOffset = min((durationMins - 5) * pxPerMin, v.translation.height)
                                }
                            }
                            .onEnded { v in
                                isDragging = false
                                let raw = v.translation.height
                                let snapped = snappedTopResizeOffset(raw, durationMins: durationMins)
                                let isEventSnapped = abs(snapped - raw) > 0.5
                                let finalPts = isEventSnapped ? snapped : min((durationMins - 5) * pxPerMin,
                                                                              snapToFive(raw / pxPerMin) * pxPerMin)
                                let delta = TimeInterval(finalPts / pxPerMin * 60)
                                topResizeOffset = 0
                                let newStart = event.startDate.addingTimeInterval(delta)
                                // Prevent dragging top handle below bottom handle
                                if event.endDate.timeIntervalSince(newStart) >= 5 * 60 {
                                    onCommit(newStart, event.endDate)
                                }
                            }
                        )
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .frame(height: 6)
                        .padding(.bottom, -2)
                        .onHover { hovering in
                            if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                        }
                        .highPriorityGesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                withTransaction(Transaction(animation: nil)) {
                                    isDragging = true
                                    resizeOffset = max(-(durationMins - 5) * pxPerMin, v.translation.height)
                                }
                            }
                            .onEnded { v in
                                isDragging = false
                                let raw = v.translation.height
                                let snapped = snappedResizeOffset(raw, durationMins: durationMins)
                                let isEventSnapped = abs(snapped - raw) > 0.5
                                let finalPts = isEventSnapped ? snapped : max(-(durationMins - 5) * pxPerMin,
                                                                              snapToFive(raw / pxPerMin) * pxPerMin)
                                let delta = TimeInterval(finalPts / pxPerMin * 60)
                                resizeOffset = 0
                                let newEnd = event.endDate.addingTimeInterval(delta)
                                // Prevent dragging bottom handle above top handle
                                if newEnd.timeIntervalSince(event.startDate) >= 5 * 60 {
                                    onCommit(event.startDate, newEnd)
                                }
                            }
                        )
                }
        }
        .frame(width: width, height: blockH)
        .offset(x: leftInset, y: yOffset)
        .shadow(color: color.opacity(isDragging ? 0.5 : 0), radius: 6)
    }

    private func snapToFive(_ mins: CGFloat) -> CGFloat {
        (mins / 5).rounded() * 5
    }
}

// MARK: - EventHoverPopover

struct EventHoverPopover: View {
    let event: EKEvent
    let showTimes: Bool
    let showNotes: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showTimes {
                Text("\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))")
                    .font(.headline)
            }
            if showNotes, let notes = event.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: 300)
    }
}
