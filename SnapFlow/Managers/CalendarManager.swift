import Foundation
import EventKit
import Combine

// MARK: - TodoItem

struct TodoItem: Identifiable, Equatable {
    var id = UUID()
    var text: String
    var isCompleted: Bool
}

@MainActor
class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    
    private let store = EKEventStore()
    private var snapFocusCalendar: EKCalendar?
    
    @Published var events: [EKEvent] = []
    @Published var isAuthorized: Bool = false
    @Published var activeEvent: EKEvent? = nil
    
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    private init() {
        checkPermissions()

        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.fetchEvents() }
            .store(in: &cancellables)

        // Periodic refresh so events stay visible after rapid saves that
        // may not always fire EKEventStoreChanged fast enough.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.fetchEvents() }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }
    
    func checkPermissions() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized, .fullAccess:
            self.isAuthorized = true
            setupSnapFocusCalendar()
        case .notDetermined:
            requestAccess()
        default:
            self.isAuthorized = false
        }
    }
    
    func requestAccess() {
        // iOS 17 / macOS 14+ uses requestFullAccessToEvents
        // Since we are compiling for newer macOS, we should try requestFullAccessToEvents
        // But for compatibility with slightly older we can wrap it. 
        // We'll use the trailing closure completion handler for generic compat.
        if #available(macOS 14.0, *) {
            Task {
                do {
                    let granted = try await store.requestFullAccessToEvents()
                    self.isAuthorized = granted
                    if granted {
                        self.setupSnapFocusCalendar()
                    }
                } catch {
                    print("Error requesting calendar access: \(error)")
                }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.setupSnapFocusCalendar()
                    }
                }
            }
        }
    }
    
    private func setupSnapFocusCalendar() {
        let calendarName = "SnapFocus"
        let calendars = store.calendars(for: .event)
        
        if let existing = calendars.first(where: { $0.title == calendarName }) {
            self.snapFocusCalendar = existing
        } else {
            let newCalendar = EKCalendar(for: .event, eventStore: store)
            newCalendar.title = calendarName
            
            // Prefer a local calendar or iCloud calendar
            let sources = store.sources
            newCalendar.source = sources.first(where: { $0.sourceType == .calDAV && $0.title == "iCloud" }) 
                                 ?? sources.first(where: { $0.sourceType == .local })
                                 ?? store.defaultCalendarForNewEvents?.source
            
            do {
                try store.saveCalendar(newCalendar, commit: true)
                self.snapFocusCalendar = newCalendar
            } catch {
                print("Failed to create SnapFocus calendar: \(error)")
            }
        }
        
        fetchEvents()
    }
    
    func fetchEvents() {
        guard let calendar = snapFocusCalendar, isAuthorized else { return }

        // Fetch the entire current day so events stay visible after rescheduling,
        // regardless of what the clock says (avoids the ±12h window edge problem).
        let cal      = Calendar.current
        let dayStart = cal.startOfDay(for: Date())
        let dayEnd   = cal.date(byAdding: .day, value: 1, to: dayStart)!

        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: [calendar])
        self.events   = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        let now = Date()
        self.activeEvent = self.events.first(where: { $0.startDate <= now && $0.endDate >= now })
    }

    // MARK: - TODO helpers

    private static func isTodoLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("- [ ] ") || t.hasPrefix("- [x] ")
    }

    /// Parse `- [ ]` / `- [x]` lines from an event's notes.
    static func parseTodos(from notes: String) -> [TodoItem] {
        notes.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [ ] ") {
                return TodoItem(text: String(trimmed.dropFirst(6)), isCompleted: false)
            } else if trimmed.hasPrefix("- [x] ") {
                return TodoItem(text: String(trimmed.dropFirst(6)), isCompleted: true)
            }
            return nil
        }
    }

    /// Rebuild the notes string with updated todos, preserving non-todo lines.
    func saveTodos(_ todos: [TodoItem], to event: EKEvent) {
        let existing = event.notes ?? ""
        let nonTodoLines = existing
            .components(separatedBy: "\n")
            .filter { !Self.isTodoLine($0) }
        let validTodos = todos.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let todoLines = validTodos.map { ($0.isCompleted ? "- [x] " : "- [ ] ") + $0.text }
        event.notes = (nonTodoLines + todoLines)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            print("Failed to save todos: \(error)")
        }
    }
    
    // Nudge the given event by `minutes`, shifting downstream connected events
    func nudgeEvent(event: EKEvent, byMinutes minutes: Int) {
        guard snapFocusCalendar != nil else { return }
        let offset = TimeInterval(minutes * 60)

        guard let idx = events.firstIndex(where: { $0.eventIdentifier == event.eventIdentifier }) else { return }

        var modifiedEvents: [EKEvent] = []

        event.endDate = event.endDate.addingTimeInterval(offset)
        modifiedEvents.append(event)

        var currentEndTime = event.endDate
        var originalEndTimePreMod = event.endDate.addingTimeInterval(-offset)

        for i in (idx + 1)..<events.count {
            let nextEvent = events[i]

            // Check if it was connected to the ORIGINAL end time
            // We use a small tolerance (e.g. 1 second) due to Date precision
            if abs(nextEvent.startDate.timeIntervalSince(originalEndTimePreMod)) < 1.0 {
                originalEndTimePreMod = nextEvent.endDate

                nextEvent.startDate = currentEndTime
                nextEvent.endDate = nextEvent.endDate.addingTimeInterval(offset)

                currentEndTime = nextEvent.endDate
                modifiedEvents.append(nextEvent)
            } else {
                break
            }
        }

        do {
            try batchSave(modifiedEvents)
        } catch {
            print("Failed to save nudged events: \(error)")
            fetchEvents()
        }
    }
    
    // MARK: - Private helpers

    private func batchSave(_ events: [EKEvent]) throws {
        for e in events {
            try store.save(e, span: .thisEvent, commit: false)
        }
        try store.commit()
    }

    // Helper to insert a single AI-generated task block
    func insertEvent(title: String, startDate: Date, durationMinutes: Int, notes: String) {
        guard let calendar = snapFocusCalendar else { return }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes * 60))
        event.notes = notes
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            print("Failed to insert AI event: \(error)")
        }
    }

    struct EventParams {
        let title: String
        let startDate: Date
        let durationMinutes: Int
        let notes: String
    }

    // Bulk insert — one store commit for all events
    func insertEvents(_ params: [EventParams]) {
        guard let calendar = snapFocusCalendar else { return }
        do {
            for p in params {
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                event.title = p.title
                event.startDate = p.startDate
                event.endDate = p.startDate.addingTimeInterval(TimeInterval(p.durationMinutes * 60))
                event.notes = p.notes
                try store.save(event, span: .thisEvent, commit: false)
            }
            try store.commit()
        } catch {
            print("Failed to insert AI events: \(error)")
        }
    }

    // Direct reschedule for drag-to-move / drag-to-resize (no cascade)
    func rescheduleEvent(event: EKEvent, newStart: Date, newEnd: Date) {
        guard newEnd > newStart else { return }
        event.startDate = newStart
        event.endDate   = newEnd
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            print("Failed to reschedule event: \(error)")
            fetchEvents()
        }
    }

    // Batch move events
    func moveEvents(eventIDs: Set<String>, delta: TimeInterval) {
        let index = Dictionary(uniqueKeysWithValues: events.map { ($0.eventIdentifier, $0) })
        let modifiedEvents: [EKEvent] = eventIDs.compactMap { id in
            guard let event = index[id] else { return nil }
            event.startDate = event.startDate.addingTimeInterval(delta)
            event.endDate   = event.endDate.addingTimeInterval(delta)
            return event
        }

        guard !modifiedEvents.isEmpty else { return }

        do {
            try batchSave(modifiedEvents)
        } catch {
            print("Failed to save batched events: \(error)")
            fetchEvents()
        }
    }
}

