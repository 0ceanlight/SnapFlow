import SwiftUI
import EventKit
import AppKit
import Combine

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

