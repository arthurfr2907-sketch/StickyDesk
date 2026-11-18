import SwiftUI
import AppKit

struct NoteView: View {
    @ObservedObject var controller: NoteWindowController
    @State private var hovering = false
    @State private var popover: ToolItem?

    /// La barre s'affiche au survol (et reste tant qu'un menu de la barre est ouvert).
    private var showToolbar: Bool { (hovering || popover != nil) && !controller.isCapturing }

    var body: some View {
        let note = controller.note
        let shape = note.shape.shape

        ZStack {
            shape.fill(note.color.color)

            if note.shape == .folded {
                FoldFlap().fill(Color.black.opacity(0.10))
            }

            VStack(spacing: 0) {
                NoteToolbar(controller: controller,
                            popover: $popover,
                            horizontalPadding: note.shape == .circle ? 34 : 6)
                    .frame(height: 30)
                    .opacity(showToolbar ? 1 : 0)
                    .allowsHitTesting(showToolbar)
                    .animation(controller.isCapturing ? nil : .easeInOut(duration: 0.15), value: showToolbar)
                    .background(WindowDragArea())   // glisser la bande du haut = déplacer
                content
                    .padding(.horizontal, note.shape.horizontalPadding)
                    .padding(.bottom, note.shape.bottomPadding)
            }
            .padding(.top, note.shape.topPadding)

            resizeGrip
        }
        .background(HoverTracker { hovering = $0 })
        .clipShape(shape)
        .environment(\.colorScheme, .light)   // texte toujours foncé, même en mode sombre
    }

    // MARK: Contenu

    @ViewBuilder
    private var content: some View {
        switch controller.note.kind {
        case .text:
            NoteTextEditor(controller: controller)
        case .checklist:
            ChecklistView(
                items: $controller.note.items,
                newItemFont: controller.note.font,
                newItemSize: controller.note.fontSize,
                onFocusItem: { id in
                    controller.focusedItemID = id
                    controller.refreshCurrentFont()
                })
        }
    }

    // MARK: Poignée de redimensionnement

    private var resizeGrip: some View {
        let shape = controller.note.shape
        let alignment: Alignment = shape == .circle ? .bottom : .bottomTrailing
        return GripShape()
            .stroke(Color.black.opacity(0.35), lineWidth: 1.2)
            .frame(width: 10, height: 10)
            .padding(7)
            .contentShape(Rectangle())
            .opacity(showToolbar ? 1 : 0.01)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { controller.resize(translation: $0.translation) }
                    .onEnded { _ in controller.endResize() }
            )
            .padding(.trailing, shape == .folded ? 22 : 0)
            .padding(.bottom, shape == .circle ? 4 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .help("Redimensionner")
    }
}

// MARK: - To-do list

struct ChecklistView: View {
    @Binding var items: [ChecklistItem]
    var newItemFont: NoteFont = .system
    var newItemSize: Double = 14
    var onFocusItem: (UUID?) -> Void = { _ in }

    @State private var newText = ""
    @FocusState private var focus: Field?

    enum Field: Hashable {
        case item(UUID)
        case newItem
    }

    /// Police des libellés de l'interface (ne change jamais)
    private let uiFont = Font.system(size: 14)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    row(for: item)
                }
                addRow
            }
            .foregroundStyle(Color.black.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .onChange(of: focus) { newValue in
            switch newValue {
            case .item(let id): onFocusItem(id)
            case .newItem: onFocusItem(nil)
            case nil: break   // ex. clic sur le menu : on garde la dernière tâche
            }
        }
    }

    private var addRow: some View {
        let font = newItemFont.nsFont(size: CGFloat(newItemSize))
        return HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16)
            ZStack(alignment: .leading) {
                if newText.isEmpty {
                    Text("Ajouter une tâche")
                        .font(uiFont)
                        .allowsHitTesting(false)
                }
                TextField("", text: $newText)
                    .textFieldStyle(.plain)
                    .font(Font(font as CTFont))
                    .focused($focus, equals: .newItem)
                    .onSubmit(addItem)
            }
        }
        .foregroundStyle(Color.black.opacity(0.5))
        .padding(.top, 2)
    }

    private func row(for item: ChecklistItem) -> some View {
        let binding = Binding<ChecklistItem>(
            get: { items.first { $0.id == item.id } ?? item },
            set: { newValue in
                if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = newValue }
            }
        )
        let font = item.nsFont
        return HStack(spacing: 8) {
            Button {
                binding.wrappedValue.done.toggle()
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .frame(width: 16)
            }
            .buttonStyle(.plain)

            TextField("", text: binding.text)
                .textFieldStyle(.plain)
                .font(Font(font as CTFont))
                .strikethrough(item.done)
                .opacity(item.done ? 0.5 : 1)
                .focused($focus, equals: .item(item.id))

            Button {
                let id = item.id
                DispatchQueue.main.async { items.removeAll { $0.id == id } }
            } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .opacity(0.35)
            .help("Supprimer la tâche")
        }
    }

    private func addItem() {
        let text = newText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        items.append(ChecklistItem(text: text, font: newItemFont, fontSize: newItemSize))
        newText = ""
    }
}

// MARK: - Utilitaires

/// Zone qui permet de déplacer la fenêtre en glissant.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// Trois petits traits diagonaux (poignée de redimensionnement).
struct GripShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 1...3 {
            let o = CGFloat(i) * r.width / 3
            p.move(to: CGPoint(x: r.maxX - o, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - o))
        }
        return p
    }
}
