import SwiftUI
import EventKit

// MARK: - TodoPanelView

struct TodoPanelView: View {
    @ObservedObject var calendarManager = CalendarManager.shared
    @State private var todos: [TodoItem] = []
    @State private var editingID: UUID? = nil

    private var activeEvent: EKEvent? { calendarManager.activeEvent }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ───────────────────────────────────────────────
            HStack {
                Text("TODO")
                    .font(.caption).bold()
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Button(action: addItem) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.70))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add todo item")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08))

            // ── List ─────────────────────────────────────────────────
            if todos.isEmpty {
                Text("No todos")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 2) {
                    ForEach($todos) { $item in
                        TodoRowView(
                            item: $item,
                            isEditing: editingID == item.id,
                            onToggle: { save() },
                            onEditBegin:  { editingID = item.id },
                            onEditCommit: { editingID = nil; save() },
                            onDelete: { delete(item) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .onAppear(perform: loadTodos)
        .onReceive(
            NotificationCenter.default.publisher(for: .EKEventStoreChanged)
        ) { _ in
            // Slight delay so EventKit finishes flushing the updated event
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { loadTodos() }
        }
        .onChange(of: calendarManager.activeEvent?.calendarItemIdentifier) { _, _ in
            loadTodos()
        }
        .onChange(of: calendarManager.activeEvent?.notes) { _, _ in
            loadTodos()
        }
    }

    // MARK: - Helpers

    private func loadTodos() {
        guard let ev = activeEvent else { todos = []; return }
        todos = CalendarManager.parseTodos(from: ev.notes ?? "")
    }

    private func save() {
        guard let ev = activeEvent else { return }
        calendarManager.saveTodos(todos, to: ev)
    }

    private func addItem() {
        let item = TodoItem(text: "", isCompleted: false)
        todos.append(item)
        editingID = item.id
        // Don't save yet — save on commit so the EKEvent doesn't get a blank line
    }

    private func delete(_ item: TodoItem) {
        todos.removeAll { $0.id == item.id }
        save()
    }
}

// MARK: - TodoRowView

private struct TodoRowView: View {
    @Binding var item: TodoItem
    let isEditing:    Bool
    let onToggle:     () -> Void
    let onEditBegin:  () -> Void
    let onEditCommit: () -> Void
    let onDelete:     () -> Void

    @State private var isHovering   = false
    @State private var checkScale: CGFloat  = 1.0
    @State private var checkOpacity: Double = 1.0
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // ── Round checkbox ────────────────────────────────────
            Button(action: toggleCheck) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            item.isCompleted
                                ? Color.green.opacity(0.9)
                                : Color.white.opacity(0.45),
                            lineWidth: 1.5
                        )
                        .background(
                            Circle()
                                .fill(item.isCompleted
                                      ? Color.green.opacity(0.25)
                                      : Color.white.opacity(0.06))
                        )
                        .frame(width: 16, height: 16)

                    if item.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                            .scaleEffect(checkScale)
                            .opacity(checkOpacity)
                    }
                }
            }
            .buttonStyle(.plain)
            .contentShape(Circle())

            // ── Text / edit field ────────────────────────────────
            Group {
                if isEditing {
                    TextField("", text: $item.text)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.88))
                        .textFieldStyle(.plain)
                        .focused($fieldFocused)
                        .onSubmit { onEditCommit() }
                        .onAppear { fieldFocused = true }
                        .onChange(of: fieldFocused) { _, val in
                            if !val { onEditCommit() }
                        }
                } else {
                    Text(item.text.isEmpty ? "New item…" : item.text)
                        .font(.caption)
                        .foregroundColor(
                            item.text.isEmpty
                            ? .white.opacity(0.35)
                            : (item.isCompleted ? .white.opacity(0.40) : .white.opacity(0.88))
                        )
                        .strikethrough(item.isCompleted, color: .white.opacity(0.35))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { onEditBegin() }
                }
            }

            // ── Trash icon (hover-revealed) ──────────────────────
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.red.opacity(0.75))
                        .contentShape(Rectangle().size(width: 22, height: 22))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.white.opacity(0.07) : Color.clear)
        )
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = h }
        }
    }

    private func toggleCheck() {
        if !item.isCompleted {
            // Animate a satisfying "pop" when checking
            withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) {
                checkScale = 1.4
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                    checkScale = 1.0
                }
            }
        }
        item.isCompleted.toggle()
        onToggle()
    }
}
