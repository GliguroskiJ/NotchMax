import SwiftUI

/// Rychlé poznámky: nahoře pole pro novou poznámku, pod ním seznam karet.
struct NotesView: View {
    @ObservedObject private var store = NotesStore.shared
    @EnvironmentObject private var vm: NotchViewModel

    @State private var newText = ""
    @State private var editingID: UUID?
    @State private var newFocused = false
    @State private var editFocused = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: NotchLayout.spacingS) {
            inputField
            content
        }
        .animation(.smooth(duration: 0.2), value: store.notes)
        .onChange(of: inputFocused) { _, focused in
            newFocused = focused
            updateHold()
        }
        .onDisappear {
            newFocused = false
            editFocused = false
            editingID = nil
            vm.holdOpen = false
        }
    }

    // MARK: Pole pro novou poznámku

    private var inputField: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
            TextField("Nová poznámka…", text: $newText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.white)
                .focused($inputFocused)
                .focusEffectDisabled()
                .onSubmit { submitNew() }
        }
        .padding(.horizontal, 12)
        .frame(height: NotchLayout.controlHeight + 4)
        .notchGlass(in: Capsule(), tint: Color.white.opacity(0.06))
        .background(Capsule().fill(Color.black.opacity(0.28)))
    }

    private func submitNew() {
        store.add(text: newText)
        newText = ""
    }

    // MARK: Seznam

    @ViewBuilder
    private var content: some View {
        if store.notes.isEmpty {
            EmptyState(symbol: "note.text",
                       title: "Zatím žádné poznámky",
                       message: "Napiš první a potvrď Enterem")
        } else {
            ScrollView {
                LazyVStack(spacing: NotchLayout.spacingS) {
                    ForEach(store.notes) { note in
                        NoteCard(
                            note: note,
                            isEditing: editingID == note.id,
                            onBeginEdit: { beginEdit(note.id) },
                            onCommit: { text in commit(note.id, text: text) },
                            onCancel: { cancelEdit(note.id) },
                            onFocusChange: { focused in
                                editFocused = focused
                                updateHold()
                            },
                            onTogglePin: { store.togglePin(note.id) },
                            onDelete: { delete(note.id) }
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Akce

    private func beginEdit(_ id: UUID) {
        editingID = id
    }

    private func commit(_ id: UUID, text: String) {
        guard editingID == id else { return }
        editingID = nil
        editFocused = false
        updateHold()
        store.update(id, text: text)
    }

    private func cancelEdit(_ id: UUID) {
        guard editingID == id else { return }
        editingID = nil
        editFocused = false
        updateHold()
    }

    private func delete(_ id: UUID) {
        if editingID == id {
            editingID = nil
            editFocused = false
            updateHold()
        }
        store.delete(id)
    }

    /// Panel se nezavírá, dokud je zaostřené jakékoliv textové pole.
    private func updateHold() {
        vm.holdOpen = newFocused || editFocused
    }
}

// MARK: - Karta poznámky

private struct NoteCard: View {
    let note: Note
    let isEditing: Bool
    let onBeginEdit: () -> Void
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    let onFocusChange: (Bool) -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: NotchLayout.spacingS) {
            if isEditing {
                editor
            } else {
                Text(note.text)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onBeginEdit() }
            }
            actions
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: NotchLayout.nestedRadius, style: .continuous)
                .fill(Color.white.opacity(hovering || isEditing ? 0.11 : 0.07))
        )
        .animation(.smooth(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }

    private var editor: some View {
        TextField("Poznámka…", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Color.white)
            .lineLimit(1...3)
            .focused($focused)
            .focusEffectDisabled()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onSubmit { onCommit(draft) }
            .onExitCommand { onCancel() }
            .onAppear {
                draft = note.text
                DispatchQueue.main.async { focused = true }
            }
            .onChange(of: focused) { _, now in
                onFocusChange(now)
                if !now { onCommit(draft) }
            }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            if note.pinned || hovering {
                iconButton(symbol: note.pinned ? "pin.fill" : "pin",
                           color: note.pinned ? Color.white.opacity(0.9) : Color.white.opacity(0.6),
                           help: note.pinned ? "Odepnout" : "Připnout",
                           action: onTogglePin)
            }
            if hovering {
                iconButton(symbol: "trash",
                           color: Color.white.opacity(0.6),
                           help: "Smazat",
                           action: onDelete)
            }
        }
        .frame(height: 16)
    }

    private func iconButton(symbol: String, color: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
