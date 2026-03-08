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
        let now2 = Date()
        self.activeEvent = self.events.first(where: { $0.startDate <= now2 && $0.endDate >= now2 })
    }

    // MARK: - TODO helpers

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
        // Keep lines that are NOT todo lines
        let nonTodoLines = existing
            .components(separatedBy: "\n")
            .filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("- [ ] ") && !t.hasPrefix("- [x] ")
            }
        // Rebuild: non-todo lines first, then todos
        let todoLines = todos.map { ($0.isCompleted ? "- [x] " : "- [ ] ") + $0.text }
        let allLines  = nonTodoLines + todoLines
        event.notes   = allLines.joined(separator: "\n")
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
        
        // Find index of the event
        guard let idx = events.firstIndex(where: { $0.eventIdentifier == event.eventIdentifier }) else { return }
        
        var modifiedEvents: [EKEvent] = []
        
        // 1. Modify the target event end time (if extending or shortening duration)
        // Wait, the prompt says: "If the active task is extended, it should dynamically push the start and end times of contiguously connected subsequent tasks"
        // Let's modify the end time of the active task
        event.endDate = event.endDate.addingTimeInterval(offset)
        modifiedEvents.append(event)
        
        // 2. Cascade logic for connected events
        // A "connected" event has a start time exactly equal to the previous event's end time (before modification).
        var currentEndTime = event.endDate
        var originalEndTimePreMod = event.endDate.addingTimeInterval(-offset)
        
        for i in (idx + 1)..<events.count {
            let nextEvent = events[i]
            
            // Check if it was connected to the ORIGINAL end time
            // We use a small tolerance (e.g. 1 second) due to Date precision
            if abs(nextEvent.startDate.timeIntervalSince(originalEndTimePreMod)) < 1.0 {
                // It was connected! Push its start and end times.
                originalEndTimePreMod = nextEvent.endDate
                
                nextEvent.startDate = currentEndTime
                nextEvent.endDate = nextEvent.endDate.addingTimeInterval(offset)
                
                currentEndTime = nextEvent.endDate
                modifiedEvents.append(nextEvent)
            } else {
                // Chain broken, don't cascade further
                break
            }
        }
        
        // 3. Batched saves to EKEventStore
        do {
            for e in modifiedEvents {
                try store.save(e, span: .thisEvent, commit: false)
            }
            try store.commit()
            // Notification.Name.EKEventStoreChanged will fire and reload events automatically
        } catch {
            print("Failed to save nudged events: \(error)")
            // Optionally, rollback or reload to fix local state
            fetchEvents()
        }
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
}

