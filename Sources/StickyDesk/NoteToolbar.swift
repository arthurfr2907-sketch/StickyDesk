import SwiftUI
import AppKit

// MARK: - Éléments de la barre

enum ToolItem: CaseIterable, Hashable {
    case style, font, size, textColor, highlight, align, bullets, numbers, arrows, noteColor

    /// Largeur approximative dans la barre
    var width: CGFloat {
        switch self {
        case .style: return 70
        case .size: return 62
        case .font: return 26
        default: return 24
        }
    }

    /// Uniquement utile pour un post-it texte (pas une to-do list)
    var textOnly: Bool {
        switch self {
        case .font, .size, .noteColor: return false
        default: return true
        }
    }

    /// Ordre dans lequel les éléments restent dans la barre quand elle rétrécit
    static let byPriority: [ToolItem] = [
        .style, .size, .bullets, .font, .textColor, .highlight, .align, .noteColor, .numbers, .arrows
    ]
}

struct NamedColor: Identifiable {
    let id = UUID()
    let name: String
    let color: NSColor?
}

enum Palette {
    static let text: [NamedColor] = [
        NamedColor(name: "Noir", color: NoteTextEditor.textColor),
        NamedColor(name: "Gris", color: NSColor(white: 0.45, alpha: 1)),
        NamedColor(name: "Rouge", color: NSColor(red: 0.85, green: 0.18, blue: 0.15, alpha: 1)),
        NamedColor(name: "Orange", color: NSColor(red: 0.90, green: 0.45, blue: 0.05, alpha: 1)),
        NamedColor(name: "Vert", color: NSColor(red: 0.13, green: 0.58, blue: 0.25, alpha: 1)),
        NamedColor(name: "Bleu", color: NSColor(red: 0.15, green: 0.40, blue: 0.85, alpha: 1)),
        NamedColor(name: "Violet", color: NSColor(red: 0.50, green: 0.25, blue: 0.75, alpha: 1))
    ]

    static let highlight: [NamedColor] = [
        NamedColor(name: "Aucun", color: nil),
        NamedColor(name: "Jaune", color: NSColor(red: 1.00, green: 0.90, blue: 0.25, alpha: 1)),
        NamedColor(name: "Vert", color: NSColor(red: 0.65, green: 0.93, blue: 0.55, alpha: 1)),
        NamedColor(name: "Rose", color: NSColor(red: 1.00, green: 0.68, blue: 0.82, alpha: 1)),
        NamedColor(name: "Bleu", color: NSColor(red: 0.62, green: 0.83, blue: 1.00, alpha: 1)),
        NamedColor(name: "Orange", color: NSColor(red: 1.00, green: 0.75, blue: 0.45, alpha: 1))
    ]

    static let arrows = ["→", "⇒", "↳", "←", "↑", "↓", "↔", "➜"]
}

// MARK: - Barre d'outils

struct NoteToolbar: View {
    @ObservedObject var controller: NoteWindowController
    @Binding var popover: ToolItem?
    var horizontalPadding: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let candidates = ToolItem.byPriority.filter { controller.note.kind == .text || !$0.textOnly }
            let visible = visibleItems(candidates, width: geo.size.width - horizontalPadding * 2)
            let hidden = Set(candidates).subtracting(visible)

            HStack(spacing: 2) {
                ForEach(ToolItem.allCases.filter { visible.contains($0) }, id: \.self) { item in
                    view(for: item)
                }
                if controller.note.kind == .checklist && !controller.note.items.isEmpty {
                    let done = controller.note.items.filter(\.done).count
                    Text("\(done)/\(controller.note.items.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.leading, 4)
                }
                Spacer(minLength: 2)
                lockScreenButton
                overflowMenu(hidden: hidden)
                ToolButton(help: "Retirer du bureau (⌘W)", action: { controller.hide() }) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundStyle(Color.black.opacity(0.65))
            .padding(.horizontal, horizontalPadding)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
    }

    /// Garde les éléments les plus importants tant qu'il y a de la place.
    private func visibleItems(_ candidates: [ToolItem], width: CGFloat) -> Set<ToolItem> {
        var remaining = width - 24 - 24 - 24 - 8   // rond écran verrouillé + ⋯ + ✕ + marge
        var result = Set<ToolItem>()
        for item in candidates {
            let w = item.width + 2
            if w <= remaining {
                result.insert(item)
                remaining -= w
            } else {
                break
            }
        }
        return result
    }

    // MARK: Un élément

    @ViewBuilder
    private func view(for item: ToolItem) -> some View {
        switch item {
        case .style:
            HStack(spacing: 1) {
                ToolButton(active: controller.isBold, help: "Gras (⌘B)", action: { controller.toggleBold() }) {
                    Image(systemName: "bold")
                }
                ToolButton(active: controller.isItalic, help: "Italique (⌘I)", action: { controller.toggleItalic() }) {
                    Image(systemName: "italic")
                }
                ToolButton(active: controller.isUnderlined, help: "Souligné (⌘U)", action: { controller.toggleUnderline() }) {
                    Image(systemName: "underline")
                }
            }

        case .font:
            popoverButton(.font, help: "Police") {
                Text("Aa").font(.system(size: 12, weight: .semibold))
            } content: {
                fontList
            }

        case .size:
            HStack(spacing: 0) {
                ToolButton(help: "Réduire le texte (⌘−)", action: { controller.changeFontSize(by: -1) }) {
                    Image(systemName: "minus").font(.system(size: 10, weight: .bold))
                }
                Text("\(Int(controller.currentSize.rounded()))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .frame(minWidth: 18)
                ToolButton(help: "Agrandir le texte (⌘+)", action: { controller.changeFontSize(by: 1) }) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                }
            }

        case .textColor:
            popoverButton(.textColor, help: "Couleur du texte") {
                colorGlyph(Text("A"), color: controller.currentTextColor ?? NoteTextEditor.textColor)
            } content: {
                colorGrid(Palette.text) { controller.setTextColor($0) }
            }

        case .highlight:
            popoverButton(.highlight, help: "Surligneur") {
                colorGlyph(Image(systemName: "highlighter"), color: controller.currentHighlight)
            } content: {
                colorGrid(Palette.highlight) { controller.setHighlight($0) }
            }

        case .align:
            popoverButton(.align, help: "Alignement") {
                Image(systemName: Self.alignIcon(controller.alignment))
            } content: {
                HStack(spacing: 2) {
                    ForEach([NSTextAlignment.left, .center, .right, .justified], id: \.self) { a in
                        ToolButton(active: controller.alignment == a, help: Self.alignName(a),
                                   action: { controller.setAlignment(a); popover = nil }) {
                            Image(systemName: Self.alignIcon(a))
                        }
                    }
                }
                .padding(6)
            }

        case .bullets:
            ToolButton(active: controller.currentList == .bullet, help: "Liste à puces",
                       action: { controller.toggleList(.bullet) }) {
                Image(systemName: "list.bullet")
            }

        case .numbers:
            ToolButton(active: controller.currentList == .numbered, help: "Liste numérotée",
                       action: { controller.toggleList(.numbered) }) {
                Image(systemName: "list.number")
            }

        case .arrows:
            popoverButton(.arrows, help: "Flèches") {
                Image(systemName: "arrow.right")
            } content: {
                arrowsPanel
            }

        case .noteColor:
            popoverButton(.noteColor, help: "Couleur du post-it") {
                Circle()
                    .fill(controller.note.color.color)
                    .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                    .frame(width: 13, height: 13)
            } content: {
                HStack(spacing: 6) {
                    ForEach(NoteColor.allCases) { c in
                        Button {
                            controller.note.color = c
                            popover = nil
                        } label: {
                            Circle()
                                .fill(c.color)
                                .overlay(Circle().stroke(Color.black.opacity(controller.note.color == c ? 0.7 : 0.2),
                                                         lineWidth: controller.note.color == c ? 2 : 1))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help(c.label)
                    }
                }
                .padding(8)
            }
        }
    }

    // MARK: Rond "écran verrouillé"

    private var lockScreenButton: some View {
        let on = controller.note.showOnLockScreen
        return ToolButton(
            help: on ? "Visible quand le Mac est verrouillé (activé)"
                     : "Afficher ce post-it quand le Mac est verrouillé",
            action: { controller.note.showOnLockScreen.toggle() }
        ) {
            Image(systemName: on ? "circle.fill" : "circle")
                .font(.system(size: 11, weight: .semibold))
        }
    }

    // MARK: Contenus des popovers

    private var fontList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(NoteFont.allCases) { f in
                Button {
                    controller.apply(font: f)
                    popover = nil
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .opacity(controller.currentFont == f ? 1 : 0)
                        Text(f.label).font(Font(f.nsFont(size: 14) as CTFont))
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(width: 210)
    }

    private var arrowsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                controller.toggleList(.arrow)
                popover = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right")
                    Text("Liste à flèches")
                    Spacer()
                }
                .font(.system(size: 13))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider()
            HStack(spacing: 2) {
                ForEach(Palette.arrows, id: \.self) { s in
                    Button {
                        controller.insertSymbol(s)
                        popover = nil
                    } label: {
                        Text(s)
                            .font(.system(size: 15))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Insérer \(s)")
                }
            }
        }
        .padding(8)
        .frame(width: 230)
    }

    private func colorGrid(_ colors: [NamedColor], onPick: @escaping (NSColor?) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(colors) { c in
                Button {
                    onPick(c.color)
                    popover = nil
                } label: {
                    ZStack {
                        if let col = c.color {
                            Circle().fill(Color(nsColor: col))
                        } else {
                            Circle().fill(Color.white)
                            Image(systemName: "line.diagonal")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.red)
                        }
                        Circle().stroke(Color.black.opacity(0.25), lineWidth: 1)
                    }
                    .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(c.name)
            }
        }
        .padding(8)
    }

    // MARK: Menu ⋯ (éléments qui ne tiennent pas + actions du post-it)

    private func overflowMenu(hidden: Set<ToolItem>) -> some View {
        Menu {
            if hidden.contains(.style) {
                Toggle("Gras", isOn: Binding(get: { controller.isBold }, set: { _ in controller.toggleBold() }))
                Toggle("Italique", isOn: Binding(get: { controller.isItalic }, set: { _ in controller.toggleItalic() }))
                Toggle("Souligné", isOn: Binding(get: { controller.isUnderlined }, set: { _ in controller.toggleUnderline() }))
            }
            if hidden.contains(.font) {
                Picker("Police", selection: Binding(get: { controller.currentFont },
                                                    set: { controller.apply(font: $0) })) {
                    ForEach(NoteFont.allCases) { Text($0.label).tag($0) }
                }
            }
            if hidden.contains(.size) {
                Picker("Taille du texte", selection: Binding(get: { controller.currentSize },
                                                             set: { controller.apply(size: $0) })) {
                    ForEach(NoteFontSize.all, id: \.size) { Text($0.label).tag($0.size) }
                }
            }
            if hidden.contains(.textColor) {
                Menu("Couleur du texte") {
                    ForEach(Palette.text) { c in Button(c.name) { controller.setTextColor(c.color) } }
                }
            }
            if hidden.contains(.highlight) {
                Menu("Surligneur") {
                    ForEach(Palette.highlight) { c in Button(c.name) { controller.setHighlight(c.color) } }
                }
            }
            if hidden.contains(.align) {
                Picker("Alignement", selection: Binding(get: { controller.alignment },
                                                        set: { controller.setAlignment($0) })) {
                    ForEach([NSTextAlignment.left, .center, .right, .justified], id: \.self) {
                        Text(Self.alignName($0)).tag($0)
                    }
                }
            }
            if hidden.contains(.bullets) {
                Button("Liste à puces") { controller.toggleList(.bullet) }
            }
            if hidden.contains(.numbers) {
                Button("Liste numérotée") { controller.toggleList(.numbered) }
            }
            if hidden.contains(.arrows) {
                Menu("Flèches") {
                    Button("Liste à flèches") { controller.toggleList(.arrow) }
                    Divider()
                    ForEach(Palette.arrows, id: \.self) { s in Button("Insérer \(s)") { controller.insertSymbol(s) } }
                }
            }
            if hidden.contains(.noteColor) {
                Picker("Couleur du post-it", selection: $controller.note.color) {
                    ForEach(NoteColor.allCases) { Text($0.label).tag($0) }
                }
            }
            if !hidden.isEmpty { Divider() }
            noteActions
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 22, height: 22)
        .help("Plus d'options")
    }

    @ViewBuilder
    private var noteActions: some View {
        Toggle("Toujours au premier plan", isOn: $controller.note.pinnedOnTop)
        Button(controller.note.kind == .text ? "Convertir en to-do list" : "Convertir en texte") {
            controller.toggleKind()
        }
        Divider()
        Button("Nouveau post-it") { controller.manager?.createNote() }
        Button("Retirer du bureau") { controller.hide() }
        Button("Supprimer…", role: .destructive) { controller.delete() }
    }

    // MARK: Aides

    private func popoverButton<L: View, C: View>(
        _ item: ToolItem, help: String,
        @ViewBuilder label: () -> L,
        @ViewBuilder content: @escaping () -> C
    ) -> some View {
        let l = label()
        return ToolButton(active: popover == item, help: help,
                          action: { popover = (popover == item) ? nil : item }) { l }
            .popover(isPresented: Binding(
                get: { popover == item },
                set: { if !$0, popover == item { popover = nil } }),
                     arrowEdge: .bottom, content: content)
    }

    private func colorGlyph<V: View>(_ glyph: V, color: NSColor?) -> some View {
        VStack(spacing: 1) {
            glyph.font(.system(size: 11, weight: .bold))
            RoundedRectangle(cornerRadius: 1)
                .fill(color.map { Color(nsColor: $0) } ?? Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 1)
                    .stroke(Color.black.opacity(color == nil ? 0.35 : 0), lineWidth: 0.5))
                .frame(width: 13, height: 3)
        }
    }

    static func alignIcon(_ a: NSTextAlignment) -> String {
        switch a {
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        case .justified: return "text.justify"
        default: return "text.alignleft"
        }
    }

    static func alignName(_ a: NSTextAlignment) -> String {
        switch a {
        case .center: return "Centré"
        case .right: return "À droite"
        case .justified: return "Justifié"
        default: return "À gauche"
        }
    }
}

// MARK: - Bouton de la barre

struct ToolButton<Label: View>: View {
    var active = false
    var help: String
    var action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.black.opacity(active ? 0.14 : (hover ? 0.07 : 0)))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

// MARK: - Détection du survol (fonctionne même quand l'app n'est pas active)

struct HoverTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let v = TrackingView()
        v.onChange = onChange
        return v
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil))
        }

        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }

        // Ne capte aucun clic : c'est juste un détecteur.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
