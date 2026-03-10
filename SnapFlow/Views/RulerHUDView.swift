import SwiftUI
import EventKit
import AppKit
import Combine

// MARK: - Blur background

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material; v.blendingMode = blendingMode; v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material; v.blendingMode = blendingMode
    }
}

// MARK: - ScaleController

/// Holds the vertical zoom level and owns the NSEvent key monitor.
/// A class (ObservableObject) is used so the monitor closure can safely
/// capture `self` by reference and mutate state without SwiftUI struct-copy issues.
final class ScaleController: ObservableObject {
    /// The default vertical scale (zoom level) on launch.
    /// 1.0 = entire 24h day fits in view. Larger values = more zoomed in.
    static let defaultScale: CGFloat = 1.5

    @Published var scale: CGFloat = ScaleController.defaultScale

    let min: CGFloat = 1.0   // whole 24h day fits in view
    let max: CGFloat = 10.0
    let step: CGFloat = 0.5

    private var monitor: Any?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let cmd = event.modifierFlags.contains(.command)
            guard cmd else { return event }
            let key = event.keyCode
            let ch  = event.charactersIgnoringModifiers ?? ""
            if ch == "+" || ch == "=" || key == 24 {   // Cmd+
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        self.scale = Swift.min(self.max, self.scale + self.step)
                    }
                }
                return nil
            } else if ch == "-" || key == 27 {          // Cmd-
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        self.scale = Swift.max(self.min, self.scale - self.step)
                    }
                }
                return nil
            }
            return event
        }
    }

    func remove() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// MARK: - RulerHUDView

struct RulerHUDView: View {
    @ObservedObject var calendarManager = CalendarManager.shared
    @State private var isHovering = false
    @State private var now = Date()
    @State private var normalizedMouseY: CGFloat = 1.0  // 0=top, 1=bottom

    @State private var selectedEventIDs: Set<String> = []
    @State private var lastExtractedEventID: String? = nil
    @State private var dragSelectRect: CGRect? = nil
    @State private var groupDragDelta: CGFloat = 0

    /// Owns the vertical scale value and the Cmd+/Cmd- key monitor.
    @StateObject private var scaleCtrl = ScaleController()

    @AppStorage("todo_enabled") private var todoEnabled: Bool = true

    let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // ─── Dynamic geometry (scale-aware) ──────────────────────────
    /// Points per minute — varies with the shared scale controller.
    var pxPerMin: CGFloat { scaleCtrl.scale }
    /// Total canvas height for the 24-hour day.
    var canvasHeight: CGFloat { 24 * 60 * pxPerMin }

    // ─── Shared static constants ──────────────────────────────────
    /// Right inset applied to both grid lines and event blocks for visual breathing room.
    static let rightMargin: CGFloat    = 10
    /// Snap threshold: if an event edge is within this many minutes, it snaps to align.
    static let snapMarginMinutes: Double = 10

    /// DST-safe: returns minutes since local midnight for positioning on the 0–1440 canvas.
    /// Using dateComponents avoids the 1-hour error on DST transition days where midnight
    /// and mid-day have different UTC offsets.
    static func minutesFromMidnight(_ date: Date) -> CGFloat {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return CGFloat((c.hour ?? 0) * 60 + (c.minute ?? 0)) + CGFloat(c.second ?? 0) / 60
    }

    let collapsedWidth: CGFloat = 10
    let expandedWidth:  CGFloat = 250
    let timeGutterW:    CGFloat = 44   // left gutter for hour labels

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Shared blur background (visible in expanded mode; almost invisible at 10pt)
            if isHovering {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
            } else {
                Color.clear
            }

            // ONE scrollable canvas for both states
            sharedScrollCanvas()

            // ── Mouse position tracker (invisible, full size) ──────────────
            if isHovering {
                MousePositionProxy { y in normalizedMouseY = y }
                    .allowsHitTesting(false)
            }

            // ── TODO panel (top-half hover only) ──────────────────────────
            Group {
                if isHovering && todoEnabled && normalizedMouseY <= 0.5 && calendarManager.activeEvent != nil {
                    VStack {
                        TodoPanelView()
                        Spacer()
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal:   .opacity
                    ))
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.75),
                       value: isHovering && todoEnabled && normalizedMouseY <= 0.5 && calendarManager.activeEvent != nil)
            .zIndex(10)
        }
        .frame(width: isHovering ? expandedWidth : collapsedWidth)
        .frame(maxHeight: .infinity)
        .cornerRadius(isHovering ? 12 : 0, corners: [.topRight, .bottomRight])
        // Subtle 1px border — matches macOS panel style
        .overlay(
            RoundedCorner(radius: isHovering ? 12 : 0, corners: [.topRight, .bottomRight])
                .stroke(Color.white.opacity(isHovering ? 0.15 : 0), lineWidth: 1)
        )
        .shadow(radius: isHovering ? 8 : 0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovering = hovering
            }
            if hovering {
                scaleCtrl.install()
            } else {
                scaleCtrl.remove()
            }
        }
        .onReceive(timer) { _ in now = Date() }
        .onCommand(#selector(NSResponder.moveUp(_:)))   { nudgeActive(by: +5) }
        .onCommand(#selector(NSResponder.moveDown(_:))) { nudgeActive(by: -5) }
        .focusable(true)
    }


    // MARK: - Shared scroll canvas (same coordinate system always)

    @ViewBuilder
    private func sharedScrollCanvas() -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                ZStack(alignment: .topLeading) {

                    // ── Collapsed: thin gray bar (full width of the 10pt strip) ──
                    if !isHovering {
                        Color.gray.opacity(0.30)
                    }

                    // ── Expanded: timeline grid ───────────────────────────────
                    if isHovering {
                        timelineGrid()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedEventIDs.removeAll()
                                lastExtractedEventID = nil
                            }
                            .gesture(
                                DragGesture(minimumDistance: 2)
                                    .onChanged { v in
                                        let y0 = v.startLocation.y
                                        let y1 = v.location.y
                                        let x0 = v.startLocation.x
                                        let x1 = v.location.x
                                        dragSelectRect = CGRect(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0))
                                    }
                                    .onEnded { v in
                                        guard let rect = dragSelectRect else { return }
                                        var newSelections: Set<String> = []
                                        for event in calendarManager.events {
                                            let startMins = RulerHUDView.minutesFromMidnight(event.startDate)
                                            let endMins = RulerHUDView.minutesFromMidnight(event.endDate)
                                            let yStart = max(startMins, 0) * pxPerMin
                                            let yEnd = min(endMins, 1440) * pxPerMin
                                            
                                            if rect.minY < yEnd && rect.maxY > yStart {
                                                newSelections.insert(event.eventIdentifier)
                                            }
                                        }
                                        if !newSelections.isEmpty {
                                            selectedEventIDs = newSelections
                                        } else {
                                            selectedEventIDs.removeAll()
                                        }
                                        dragSelectRect = nil
                                        lastExtractedEventID = nil
                                    }
                            )
                    }

                    // ── Events — same y-positions in both modes ───────────────
                    eventsLayer()
                    
                    // ── Drag Selection Rect ───────────────────────────────────
                    if let rect = dragSelectRect, isHovering {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.15))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gray.opacity(0.4), lineWidth: 1))
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                    }

                    // ── Now line ──────────────────────────────────────────────
                    nowLine()
                        .id("nowLine")

                    // ── Expanded tip ──────────────────────────────────────────
                    if isHovering {
                        Text("↑ +5m  ·  ↓ -5m")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(6)
                            .offset(y: canvasHeight - 20)
                    }
                }
                .frame(width: isHovering ? expandedWidth : collapsedWidth,
                       height: canvasHeight)
            }
            .onAppear { proxy.scrollTo("nowLine", anchor: .center) }
        }
    }

    // MARK: - Timeline grid (expanded only)

    private func timelineGrid() -> some View {
        // Capture scale so Canvas closure uses a value-type copy (avoids re-capture issues)
        let scale = pxPerMin
        let height = canvasHeight
        let gutterW = timeGutterW
        return Canvas { ctx, size in
            for hour in 0..<24 {
                // Only draw 15-min sub-lines when zoomed in enough to show them clearly
                let subStep = scale >= 1.5 ? 15 : 60
                for min in stride(from: 0, to: 60, by: subStep) {
                    let y = CGFloat(hour * 60 + min) * scale
                    var p = Path()
                    p.move(to: CGPoint(x: gutterW, y: y))
                    p.addLine(to: CGPoint(x: size.width - RulerHUDView.rightMargin, y: y))
                    let isHour = min == 0
                    ctx.stroke(p, with: .color(isHour ? .gray.opacity(0.45) : .gray.opacity(0.18)),
                               lineWidth: isHour ? 1 : 0.5)
                    if isHour {
                        let label = String(format: "%02d:00", hour)
                        // Fixed font size — labels never scale with zoom
                        ctx.draw(Text(label).font(.caption2).foregroundColor(.gray),
                                 at: CGPoint(x: gutterW / 2, y: y), anchor: .center)
                    }
                }
            }
        }
        .frame(height: height)
    }

    // MARK: - Events layer

    @ViewBuilder
    private func eventsLayer() -> some View {
        let todayStart = Calendar.current.startOfDay(for: now)
        let scale = pxPerMin
        let height = canvasHeight
        GeometryReader { geo in
            ForEach(calendarManager.events, id: \.eventIdentifier) { event in
                let startMin = Self.minutesFromMidnight(event.startDate)
                let endMin   = Self.minutesFromMidnight(event.endDate)

                // Only render events that fall within today's 0–1440 range
                if startMin < 1440 && endMin > 0 {
                    let yStart = max(startMin, 0) * scale
                    let yEnd   = min(endMin, 1440) * scale
                    let color  = eventColor(event)

                    if isHovering {
                        // ── Expanded: full interactive block ──────────────────
                        InteractiveEventBlock(
                            event: event,
                            todayStart: todayStart,
                            containerWidth: geo.size.width,
                            pxPerMin: scale,
                            color: color,
                            allEvents: calendarManager.events,
                            isSelected: selectedEventIDs.contains(event.eventIdentifier),
                            selectedEventIDs: selectedEventIDs,
                            getIsSelected: { selectedEventIDs.contains(event.eventIdentifier) },
                            onDoubleTap: { openInCalendar(event) },
                            onTap: { modifiers in handleEventTap(event: event, modifiers: modifiers) },
                            onDragStartUnselected: {
                                selectedEventIDs = [event.eventIdentifier]
                                lastExtractedEventID = event.eventIdentifier
                            },
                            groupDragDelta: $groupDragDelta,
                            onCommit: { ns, ne in
                                calendarManager.rescheduleEvent(event: event, newStart: ns, newEnd: ne)
                            },
                            onCommitGroup: { delta in
                                calendarManager.moveEvents(eventIDs: selectedEventIDs, delta: delta)
                            }
                        )
                    } else {
                        // ── Collapsed: thin colored bar, same y coords ────────
                        color
                            .opacity(0.85)
                            .frame(width: collapsedWidth, height: max(2, yEnd - yStart))
                            .offset(y: yStart)
                            .contentShape(Rectangle())
                            .onTapGesture { openInCalendar(event) }
                    }
                }
            }
        }
        .frame(height: height)
    }

    // MARK: - Now line

    private func nowLine() -> some View {
        let y = RulerHUDView.minutesFromMidnight(now) * pxPerMin
        return Group {
            if isHovering {
                HStack(spacing: 2) {
                    // Fixed font — label never scales with zoom
                    Text("Now").font(.caption2).bold().foregroundColor(.red).frame(width: timeGutterW - 4)
                    Rectangle().fill(Color.red).frame(height: 2)
                }
                .frame(height: 2)  // constrain layout height so offset lands on the line, not 7px below
            } else {
                Rectangle().fill(Color.white).frame(width: collapsedWidth, height: 2)
            }
        }
        .offset(y: y)
    }

    // MARK: - Pastel palette

    private static let palette: [Color] = [
        Color(hue: 0.60, saturation: 0.55, brightness: 0.90),  // sky blue
        Color(hue: 0.08, saturation: 0.60, brightness: 0.92),  // peach
        Color(hue: 0.38, saturation: 0.50, brightness: 0.82),  // sage green
        Color(hue: 0.75, saturation: 0.50, brightness: 0.88),  // soft lavender
        Color(hue: 0.14, saturation: 0.55, brightness: 0.92),  // warm gold
        Color(hue: 0.50, saturation: 0.48, brightness: 0.84),  // teal
        Color(hue: 0.93, saturation: 0.50, brightness: 0.90),  // rose
        Color(hue: 0.28, saturation: 0.45, brightness: 0.84),  // lime
        Color(hue: 0.02, saturation: 0.55, brightness: 0.88),  // coral
        Color(hue: 0.68, saturation: 0.45, brightness: 0.86),  // periwinkle
    ]

    /// Greedy graph-coloring: no two overlapping or immediately adjacent events
    /// share the same palette color.
    private var eventColorMap: [String: Color] {
        let sorted = calendarManager.events.sorted { $0.startDate < $1.startDate }
        var assignedIdx: [String: Int] = [:]

        for event in sorted {
            // Collect palette indices already used by conflicting neighbors
            let usedIdxs: Set<Int> = Set(sorted.compactMap { other -> Int? in
                guard other.eventIdentifier != event.eventIdentifier,
                      let idx = assignedIdx[other.eventIdentifier] else { return nil }
                let overlaps  = other.startDate < event.endDate && other.endDate > event.startDate
                let adjacentA = abs(other.endDate.timeIntervalSince(event.startDate)) < 60
                let adjacentB = abs(event.endDate.timeIntervalSince(other.startDate)) < 60
                return (overlaps || adjacentA || adjacentB) ? idx : nil
            })

            // Shuffle the free slots using a seed derived from this event's identifier,
            // so the pick is random across the palette but deterministic per event.
            let freeIdxs = (0..<Self.palette.count).filter { !usedIdxs.contains($0) }
            var rng = SeededRNG(seed: abs(event.eventIdentifier.hashValue))
            let chosen = freeIdxs.shuffled(using: &rng).first
                      ?? abs(event.eventIdentifier.hashValue) % Self.palette.count
            assignedIdx[event.eventIdentifier] = chosen
        }

        return assignedIdx.mapValues { Self.palette[$0] }
    }

    private func eventColor(_ event: EKEvent) -> Color {
        eventColorMap[event.eventIdentifier] ?? Self.palette[0]
    }

    private func openInCalendar(_ event: EKEvent) {
        let identifier = event.calendarItemIdentifier
        guard !identifier.isEmpty,
              let url = URL(string: "ical://ekevent/\(identifier)") else {
            print("SnapFocus: could not construct Calendar URL for event \(event.title ?? "unknown")")
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func nudgeActive(by minutes: Int) {
        let n = Date()
        guard let ev = calendarManager.events.first(where: { $0.startDate <= n && $0.endDate >= n }) else { return }
        calendarManager.nudgeEvent(event: ev, byMinutes: minutes)
    }

    private func handleEventTap(event: EKEvent, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selectedEventIDs.contains(event.eventIdentifier) {
                selectedEventIDs.remove(event.eventIdentifier)
            } else {
                selectedEventIDs.insert(event.eventIdentifier)
            }
            lastExtractedEventID = event.eventIdentifier
        } else if modifiers.contains(.shift), let lastID = lastExtractedEventID, let lastEvent = calendarManager.events.first(where: { $0.eventIdentifier == lastID }) {
            let rangeStart = min(lastEvent.startDate, event.startDate)
            let rangeEnd = max(lastEvent.endDate, event.endDate)
            
            for e in calendarManager.events {
                if e.startDate < rangeEnd && e.endDate > rangeStart {
                    selectedEventIDs.insert(e.eventIdentifier)
                }
            }
            lastExtractedEventID = event.eventIdentifier
        } else {
            selectedEventIDs = [event.eventIdentifier]
            lastExtractedEventID = event.eventIdentifier
        }
    }
}

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

    @State private var moveOffset:   CGFloat = 0
    @State private var resizeOffset: CGFloat = 0
    @State private var isDragging = false

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

    var body: some View {
        let startMins    = RulerHUDView.minutesFromMidnight(event.startDate)
        let durationMins = CGFloat(event.endDate.timeIntervalSince(event.startDate) / 60)
        let blockH       = max(durationMins * pxPerMin + resizeOffset, 14)
        let yOffset      = startMins * pxPerMin + (isSelected ? groupDragDelta : moveOffset)
        let width        = containerWidth - leftInset - RulerHUDView.rightMargin

        ZStack(alignment: .bottom) {
            // Body
            RoundedRectangle(cornerRadius: 5)
                .fill(color.opacity(isDragging ? 0.92 : 0.72))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(isSelected ? Color.primary.opacity(0.8) : color, lineWidth: isSelected ? 2 : 1))
                .overlay(alignment: .topLeading) {
                    Text(event.title ?? "")
                        .font(.caption).bold().foregroundColor(.white).lineLimit(2)
                        .padding(.horizontal, 5).padding(.top, 3)
                }
                .highPriorityGesture(DragGesture(minimumDistance: 2)
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
                .onTapGesture(count: 2) { onDoubleTap() }
                .onTapGesture(count: 1) { onTap(NSEvent.modifierFlags) }

            // Bottom resize handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.4))
                .frame(width: 28, height: 4)
                .padding(.bottom, 3)
                .contentShape(Rectangle().size(width: width, height: edgeHandleH))
                .highPriorityGesture(DragGesture(minimumDistance: 2)
                    .onChanged { v in
                        withTransaction(Transaction(animation: nil)) {
                            isDragging = true
                            resizeOffset = max(-(durationMins - 5) * pxPerMin, v.translation.height)  // raw
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
                        onCommit(event.startDate, event.endDate.addingTimeInterval(delta))
                    }
                )
        }
        .frame(width: width, height: blockH)
        .offset(x: leftInset, y: yOffset)
        .shadow(color: color.opacity(isDragging ? 0.5 : 0), radius: 6)
    }

    private func snapToFive(_ mins: CGFloat) -> CGFloat {
        (mins / 5).rounded() * 5
    }
}

// MARK: - Corner radius helpers

extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft     = RectCorner(rawValue: 1 << 0)
    static let topRight    = RectCorner(rawValue: 1 << 1)
    static let bottomLeft  = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: RectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        Path(NSBezierPath(roundedRect: NSRect(origin: rect.origin, size: rect.size),
                          xRadius: radius, yRadius: radius).cgPath)
    }
}

// MARK: - Seeded RNG (linear congruential generator)
// Deterministic per event: same seed → same shuffle → same color every render.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: Int) {
        // Mix the seed to avoid poor low-bit distributions
        state = UInt64(bitPattern: Int64(seed)) ^ 6364136223846793005
    }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

// MARK: - MousePositionProxy
// Transparent NSView that tracks the mouse Y position normalised to [0, 1]
// (0 = top, 1 = bottom). Used to decide whether to show the TODO panel.

struct MousePositionProxy: NSViewRepresentable {
    var onNormalizedY: (CGFloat) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let v = TrackingView()
        v.onNormalizedY = onNormalizedY
        return v
    }

    func updateNSView(_ v: TrackingView, context: Context) {
        v.onNormalizedY = onNormalizedY
    }

    class TrackingView: NSView {
        var onNormalizedY: ((CGFloat) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let old = trackingArea { removeTrackingArea(old) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseMoved(with event: NSEvent) {
            guard bounds.height > 0 else { return }
            // Convert from window coords to view coords, then normalise
            let pt = convert(event.locationInWindow, from: nil)
            // NSView: y = 0 at bottom, flip to 0 at top
            let fromTop = 1.0 - (pt.y / bounds.height)
            let clamped  = max(0, min(1, fromTop))
            onNormalizedY?(clamped)
        }
    }
}


