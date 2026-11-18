import AppKit
import SwiftUI

// MARK: - Fenêtre sans bordure

/// Fenêtre sans barre de titre ni boutons : on ne voit que le post-it.
final class NotePanel: NSPanel {
    var onClose: (() -> Void)?
    var onNewNote: (() -> Void)?
    var onFontSize: ((Int) -> Void)?
    var onShortcut: ((String) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Raccourcis clavier (l'app n'a pas de menu "Édition" visible).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let action: Selector?
        switch key {
        case "x": action = #selector(NSText.cut(_:))
        case "c": action = #selector(NSText.copy(_:))
        case "v": action = #selector(NSText.paste(_:))
        case "a": action = #selector(NSText.selectAll(_:))
        case "z": action = flags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
        case "w": onClose?(); return true
        case "n": onNewNote?(); return true
        case "b", "i", "u":
            if !flags.contains(.shift), onShortcut?(key) == true { return true }
            action = nil
        case "=", "+": onFontSize?(1); return true
        case "-": onFontSize?(-1); return true
        default: action = nil
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Contrôleur d'un post-it

final class NoteWindowController: NSObject, ObservableObject, NSWindowDelegate {
    /// Niveau "bureau" : au-dessus des icônes du bureau, derrière toutes les fenêtres.
    static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    @Published var note: Note {
        didSet {
            NoteStore.shared.upsert(note)
            applyWindowStyle()
            if note.showOnLockScreen || oldValue.showOnLockScreen {
                manager?.lockScreenNeedsUpdate()
            }
        }
    }
    @Published var isKey = false
    /// Pendant la photo pour l'écran verrouillé : barre d'outils et poignée masquées.
    @Published var isCapturing = false

    // Police affichée dans le menu = celle du texte sélectionné / du curseur
    @Published var currentFont: NoteFont = .system
    @Published var currentSize: Double = 14
    @Published var isBold = false
    @Published var isItalic = false
    @Published var isUnderlined = false
    @Published var alignment: NSTextAlignment = .left
    @Published var currentTextColor: NSColor?
    @Published var currentHighlight: NSColor?
    @Published var currentList: ListStyle?
    /// Dernière tâche éditée dans une to-do list
    var focusedItemID: UUID?
    weak var textView: NSTextView?

    let panel: NotePanel
    weak var manager: NoteWindowManager?
    private var resizeStart: NSRect?

    init(note: Note, manager: NoteWindowManager) {
        self.note = note
        self.manager = manager
        self.panel = NotePanel(contentRect: note.frame,
                               styleMask: [.borderless],
                               backing: .buffered,
                               defer: false)
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        // Visible sur tous les bureaux (Spaces), reste en place avec Mission Control.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.delegate = self
        panel.onClose = { [weak self] in self?.hide() }
        panel.onNewNote = { [weak manager] in manager?.createNote() }
        panel.onFontSize = { [weak self] step in self?.changeFontSize(by: step) }
        panel.onShortcut = { [weak self] key in self?.handleShortcut(key) ?? false }

        let host = NSHostingView(rootView: NoteView(controller: self))
        host.sizingOptions = []   // c'est nous qui gérons la taille de la fenêtre
        panel.contentView = host

        applyWindowStyle()
    }

    func applyWindowStyle() {
        panel.level = note.pinnedOnTop ? .floating : Self.desktopLevel
        panel.alphaValue = CGFloat(note.opacity)
        // L'ombre suit la forme : on la recalcule après le rendu.
        DispatchQueue.main.async { [weak panel] in panel?.invalidateShadow() }
    }

    // MARK: Actions

    /// Image du post-it tel qu'il apparaît à l'écran.
    func snapshot() -> NSImage? {
        guard let view = panel.contentView, panel.isVisible else { return nil }
        let bounds = view.bounds
        guard bounds.width > 0, let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }


    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        note.isOnDesktop = false
        panel.orderOut(nil)
        manager?.didHide(id: note.id)
        // Casse la référence circulaire vue <-> contrôleur.
        DispatchQueue.main.async { [panel] in panel.contentView = nil }
    }

    func delete() {
        let id = note.id
        DispatchQueue.main.async { [weak manager] in manager?.delete(id: id) }
    }

    func toggleKind() {
        var n = note
        switch n.kind {
        case .text:
            let font = n.font, size = n.fontSize
            n.items = n.text
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { ChecklistItem(text: $0, font: font, fontSize: size) }
            n.text = ""
            n.rtf = nil
            n.kind = .checklist
        case .checklist:
            n.text = n.items.map { ($0.done ? "✓ " : "") + $0.text }.joined(separator: "\n")
            n.items = []
            n.rtf = nil
            n.kind = .text
        }
        textView = nil
        focusedItemID = nil
        note = n
        refreshCurrentFont()
    }

    // MARK: Polices et mise en forme

    /// Police par défaut du post-it (dernière choisie).
    var defaultNSFont: NSFont {
        note.font.nsFont(size: CGFloat(note.fontSize))
    }

    func attach(_ tv: NSTextView) {
        textView = tv
        refreshCurrentFont()
    }

    func textChanged(_ tv: NSTextView) {
        let range = NSRange(location: 0, length: (tv.string as NSString).length)
        var n = note
        n.text = tv.string
        n.rtf = tv.rtf(from: range)
        note = n
    }

    private func baseAttributes(_ attrs: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var a = attrs
        if a[.font] == nil { a[.font] = defaultNSFont }
        if a[.foregroundColor] == nil { a[.foregroundColor] = NoteTextEditor.textColor }
        return a
    }

    private func currentAttributes(_ tv: NSTextView) -> [NSAttributedString.Key: Any] {
        let sel = tv.selectedRange()
        if sel.length > 0, let storage = tv.textStorage, sel.location < storage.length {
            return baseAttributes(storage.attributes(at: sel.location, effectiveRange: nil))
        }
        return baseAttributes(tv.typingAttributes)
    }

    private func focusText(_ tv: NSTextView) {
        tv.window?.makeKey()
        tv.window?.makeFirstResponder(tv)
    }

    /// Met à jour l'état affiché dans la barre (gras actif, police, alignement…).
    func refreshCurrentFont() {
        var font = note.font
        var size = note.fontSize
        var bold = false, italic = false, underline = false
        var align: NSTextAlignment = .left
        var color: NSColor? = nil
        var highlight: NSColor? = nil
        var list: ListStyle? = nil

        switch note.kind {
        case .text:
            if let tv = textView {
                let a = currentAttributes(tv)
                if let f = a[.font] as? NSFont {
                    font = NoteFont.matching(f) ?? note.font
                    size = Double(f.pointSize)
                    let traits = NSFontManager.shared.traits(of: f)
                    bold = traits.contains(.boldFontMask)
                    italic = f.fontDescriptor.symbolicTraits.contains(.italic)
                        || traits.contains(.italicFontMask)
                }
                if let oblique = a[.obliqueness] as? NSNumber, oblique.doubleValue > 0 {
                    italic = true
                }
                underline = ((a[.underlineStyle] as? Int) ?? 0) != 0
                if let p = a[.paragraphStyle] as? NSParagraphStyle {
                    align = p.alignment == .natural ? .left : p.alignment
                }
                color = a[.foregroundColor] as? NSColor
                highlight = a[.backgroundColor] as? NSColor
                let ns = tv.string as NSString
                let pr = ns.paragraphRange(for: NSRange(location: tv.selectedRange().location, length: 0))
                list = ListPrefix.detect(in: ns, paragraph: pr)?.style
            }
        case .checklist:
            if let id = focusedItemID, let item = note.items.first(where: { $0.id == id }) {
                font = item.font ?? .system
                size = item.fontSize ?? 14
            }
        }
        if currentFont != font { currentFont = font }
        if currentSize != size { currentSize = size }
        if isBold != bold { isBold = bold }
        if isItalic != italic { isItalic = italic }
        if isUnderlined != underline { isUnderlined = underline }
        if alignment != align { alignment = align }
        if currentTextColor != color { currentTextColor = color }
        if currentHighlight != highlight { currentHighlight = highlight }
        if currentList != list { currentList = list }
    }

    /// Applique une transformation d'attributs :
    /// - texte sélectionné → seulement la sélection
    /// - sinon → ce qui sera tapé ensuite
    private func modifyAttributes(_ transform: ([NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any]) {
        guard note.kind == .text, let tv = textView else { return }
        focusText(tv)
        let sel = tv.selectedRange()
        if sel.length > 0, let storage = tv.textStorage,
           tv.shouldChangeText(in: sel, replacementString: nil) {
            var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
            storage.enumerateAttributes(in: sel, options: []) { attrs, range, _ in
                runs.append((range, transform(baseAttributes(attrs))))
            }
            storage.beginEditing()
            for (range, attrs) in runs { storage.setAttributes(attrs, range: range) }
            storage.endEditing()
            tv.didChangeText()   // annulation (⌘Z) + sauvegarde
        }
        tv.typingAttributes = transform(baseAttributes(tv.typingAttributes))
        refreshCurrentFont()
    }

    /// Change la police / taille (texte : sélection ou suite ; to-do : tâche en cours + suivantes).
    func apply(font newFont: NoteFont? = nil, size newSize: Double? = nil) {
        var n = note
        if let f = newFont { n.font = f }
        if let s = newSize { n.fontSize = s }

        if n.kind == .checklist {
            if let id = focusedItemID, let i = n.items.firstIndex(where: { $0.id == id }) {
                if let f = newFont { n.items[i].font = f }
                if let s = newSize { n.items[i].fontSize = s }
            }
            note = n
            refreshCurrentFont()
            return
        }

        note = n
        let fm = NSFontManager.shared
        modifyAttributes { attrs in
            var a = attrs
            guard let old = a[.font] as? NSFont else { return a }
            let size = newSize.map { CGFloat($0) } ?? old.pointSize
            var f: NSFont
            if let nf = newFont {
                f = nf.nsFont(size: size)
                let traits = fm.traits(of: old)
                if traits.contains(.boldFontMask) { f = fm.convert(f, toHaveTrait: .boldFontMask) }
                if old.fontDescriptor.symbolicTraits.contains(.italic) {
                    f = Self.font(f, with: .italic, on: true)
                }
            } else {
                f = fm.convert(old, toSize: size)
            }
            a[.font] = f
            return a
        }
    }

    /// ⌘+ / ⌘− et boutons − / + : taille suivante / précédente.
    func changeFontSize(by step: Int) {
        let sizes = NoteFontSize.all.map(\.size)
        let current = sizes.firstIndex(of: currentSize)
            ?? sizes.firstIndex(where: { $0 >= currentSize })
            ?? sizes.count - 1
        let next = min(max(current + step, 0), sizes.count - 1)
        apply(size: sizes[next])
    }

    func toggleBold() { toggleTrait(.boldFontMask, on: !isBold) }
    func toggleItalic() {
        let on = !isItalic
        modifyAttributes { attrs in
            var a = attrs
            a.removeValue(forKey: .obliqueness)
            guard let f = a[.font] as? NSFont else { return a }
            let italic = Self.font(f, with: .italic, on: on)
            a[.font] = italic
            // Polices sans version italique (Manuscrite, Feutre…) : on penche le texte.
            if on && !italic.fontDescriptor.symbolicTraits.contains(.italic) {
                a[.obliqueness] = 0.2
            }
            return a
        }
    }

    /// Ajoute / retire un style (italique, gras) via le descripteur de police.
    static func font(_ f: NSFont, with trait: NSFontDescriptor.SymbolicTraits, on: Bool) -> NSFont {
        var traits = f.fontDescriptor.symbolicTraits
        if on { traits.insert(trait) } else { traits.remove(trait) }
        let descriptor = f.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: f.pointSize) ?? f
    }

    private func toggleTrait(_ trait: NSFontTraitMask, on: Bool) {
        let fm = NSFontManager.shared
        modifyAttributes { attrs in
            var a = attrs
            if let f = a[.font] as? NSFont {
                a[.font] = on ? fm.convert(f, toHaveTrait: trait) : fm.convert(f, toNotHaveTrait: trait)
            }
            return a
        }
    }

    func toggleUnderline() {
        let on = !isUnderlined
        modifyAttributes { attrs in
            var a = attrs
            if on { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            else { a.removeValue(forKey: .underlineStyle) }
            return a
        }
    }

    func setTextColor(_ color: NSColor?) {
        modifyAttributes { attrs in
            var a = attrs
            a[.foregroundColor] = color ?? NoteTextEditor.textColor
            return a
        }
    }

    func setHighlight(_ color: NSColor?) {
        modifyAttributes { attrs in
            var a = attrs
            if let color { a[.backgroundColor] = color } else { a.removeValue(forKey: .backgroundColor) }
            return a
        }
    }

    func setAlignment(_ value: NSTextAlignment) {
        guard note.kind == .text, let tv = textView else { return }
        focusText(tv)
        switch value {
        case .center: tv.alignCenter(nil)
        case .right: tv.alignRight(nil)
        case .justified: tv.alignJustified(nil)
        default: tv.alignLeft(nil)
        }
        refreshCurrentFont()
    }

    func insertSymbol(_ symbol: String) {
        guard note.kind == .text, let tv = textView else { return }
        focusText(tv)
        tv.insertText(symbol, replacementRange: tv.selectedRange())
    }

    /// ⌘B / ⌘I / ⌘U
    func handleShortcut(_ key: String) -> Bool {
        guard note.kind == .text, textView != nil else { return false }
        switch key {
        case "b": toggleBold()
        case "i": toggleItalic()
        case "u": toggleUnderline()
        default: return false
        }
        return true
    }

    // MARK: Listes (puces, numéros, flèches)

    func toggleList(_ style: ListStyle) {
        guard note.kind == .text, let tv = textView else { return }
        focusText(tv)
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        let paras = ListPrefix.paragraphs(in: ns, covering: sel)
        let prefixes = paras.map { ListPrefix.detect(in: ns, paragraph: $0) }
        let removing = prefixes.allSatisfy { $0?.style == style }

        var number = 1
        if style == .numbered, let first = paras.first, first.location > 0 {
            let prev = ns.paragraphRange(for: NSRange(location: first.location - 1, length: 0))
            if let p = ListPrefix.detect(in: ns, paragraph: prev), p.style == .numbered {
                number = p.number + 1
            }
        }

        var edits: [(NSRange, String)] = []
        for (i, pr) in paras.enumerated() {
            let old = NSRange(location: pr.location, length: prefixes[i]?.length ?? 0)
            if removing {
                edits.append((old, ""))
            } else {
                edits.append((old, ListPrefix.string(style, number: number)))
                number += 1
            }
        }

        // Position du curseur après les modifications
        func map(_ p: Int) -> Int {
            var offset = 0
            for (r, s) in edits {
                let newLen = (s as NSString).length
                if p >= NSMaxRange(r) { offset += newLen - r.length }
                else if p >= r.location { return r.location + offset + newLen }
                else { break }
            }
            return p + offset
        }
        let newStart = map(sel.location)
        let newEnd = map(NSMaxRange(sel))
        let delta = edits.reduce(0) { $0 + ($1.1 as NSString).length - $1.0.length }
        let start = paras.first?.location ?? 0
        let end = (paras.last.map { NSMaxRange($0) } ?? start) + delta

        tv.undoManager?.beginUndoGrouping()
        for (range, string) in edits.reversed() {
            replaceText(in: tv, range: range, with: string)
        }
        updateListIndent(in: tv, covering: NSRange(location: start, length: max(0, end - start)))
        tv.undoManager?.endUndoGrouping()

        tv.setSelectedRange(NSRange(location: newStart, length: max(0, newEnd - newStart)))
        updateTypingIndent(in: tv)
        refreshCurrentFont()
    }

    /// Entrée dans une liste : continue la liste, ou la termine si la ligne est vide.
    func handleNewline(in tv: NSTextView) -> Bool {
        guard note.kind == .text else { return false }
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        let pr = ns.paragraphRange(for: NSRange(location: sel.location, length: 0))
        guard let p = ListPrefix.detect(in: ns, paragraph: pr),
              sel.location >= pr.location + p.length else { return false }

        let end = ListPrefix.contentEnd(pr, in: ns)
        let contentRange = NSRange(location: pr.location + p.length, length: max(0, end - pr.location - p.length))
        let content = ns.substring(with: contentRange)

        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            tv.undoManager?.beginUndoGrouping()
            replaceText(in: tv, range: NSRange(location: pr.location, length: p.length), with: "")
            updateListIndent(in: tv, covering: NSRange(location: pr.location, length: 0))
            tv.undoManager?.endUndoGrouping()
            tv.setSelectedRange(NSRange(location: pr.location, length: 0))
            updateTypingIndent(in: tv)
            refreshCurrentFont()
            return true
        }

        let next = ListPrefix.string(p.style, number: p.number + 1)
        tv.insertText("\n" + next, replacementRange: sel)
        refreshCurrentFont()
        return true
    }

    private func replaceText(in tv: NSTextView, range: NSRange, with string: String) {
        guard let storage = tv.textStorage,
              tv.shouldChangeText(in: range, replacementString: string) else { return }
        var attrs: [NSAttributedString.Key: Any]
        if range.location < storage.length {
            attrs = storage.attributes(at: range.location, effectiveRange: nil)
        } else if storage.length > 0 {
            attrs = storage.attributes(at: storage.length - 1, effectiveRange: nil)
        } else {
            attrs = tv.typingAttributes
        }
        attrs = baseAttributes(attrs)
        attrs.removeValue(forKey: .underlineStyle)
        attrs.removeValue(forKey: .backgroundColor)
        storage.replaceCharacters(in: range, with: NSAttributedString(string: string, attributes: attrs))
        tv.didChangeText()
    }

    /// Retrait des lignes suivantes d'un élément de liste (le texte s'aligne après la puce).
    private func listIndent(for pr: NSRange, in ns: NSString, storage: NSTextStorage) -> CGFloat {
        guard let p = ListPrefix.detect(in: ns, paragraph: pr), pr.location < storage.length else { return 0 }
        let font = (storage.attribute(.font, at: pr.location, effectiveRange: nil) as? NSFont) ?? defaultNSFont
        let prefix = ns.substring(with: NSRange(location: pr.location, length: p.length)) as NSString
        return ceil(prefix.size(withAttributes: [.font: font]).width)
    }

    private func updateListIndent(in tv: NSTextView, covering range: NSRange) {
        guard let storage = tv.textStorage else { return }
        let ns = tv.string as NSString
        for pr in ListPrefix.paragraphs(in: ns, covering: range) where pr.length > 0 {
            let indent = listIndent(for: pr, in: ns, storage: storage)
            let current = (storage.attribute(.paragraphStyle, at: pr.location, effectiveRange: nil) as? NSParagraphStyle)
                ?? NSParagraphStyle.default
            guard current.headIndent != indent || current.firstLineHeadIndent != 0,
                  let style = current.mutableCopy() as? NSMutableParagraphStyle else { continue }
            style.headIndent = indent
            style.firstLineHeadIndent = 0
            if tv.shouldChangeText(in: pr, replacementString: nil) {
                storage.addAttribute(.paragraphStyle, value: style, range: pr)
                tv.didChangeText()
            }
        }
    }

    private func updateTypingIndent(in tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let ns = tv.string as NSString
        let pr = ns.paragraphRange(for: NSRange(location: tv.selectedRange().location, length: 0))
        let indent = listIndent(for: pr, in: ns, storage: storage)
        var attrs = baseAttributes(tv.typingAttributes)
        let current = (attrs[.paragraphStyle] as? NSParagraphStyle) ?? NSParagraphStyle.default
        if let style = current.mutableCopy() as? NSMutableParagraphStyle {
            style.headIndent = indent
            style.firstLineHeadIndent = 0
            attrs[.paragraphStyle] = style
        }
        tv.typingAttributes = attrs
    }

    // MARK: Redimensionnement (poignée en bas à droite)

    func resize(translation: CGSize) {
        if resizeStart == nil { resizeStart = panel.frame }
        guard let start = resizeStart else { return }
        let width = max(160, start.width + translation.width)
        let height = max(120, start.height + translation.height)
        // On garde le coin supérieur gauche fixe.
        let frame = NSRect(x: start.minX, y: start.maxY - height, width: width, height: height)
        panel.setFrame(frame, display: true)
    }

    func endResize() {
        resizeStart = nil
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) { syncFrame() }
    func windowDidResize(_ notification: Notification) { syncFrame() }
    func windowDidBecomeKey(_ notification: Notification) { isKey = true }
    func windowDidResignKey(_ notification: Notification) { isKey = false }

    private func syncFrame() {
        guard panel.isVisible, note.frame != panel.frame else { return }
        note.frame = panel.frame
    }
}

// MARK: - Gestionnaire de tous les post-it

final class NoteWindowManager {
    private var controllers: [UUID: NoteWindowController] = [:]
    private let store = NoteStore.shared

    func restore() {
        for note in store.notes where note.isOnDesktop {
            show(note)
        }
        lockScreenNeedsUpdate()
    }

    /// Recalcule le fond d'écran avec les post-it "écran verrouillé".
    func lockScreenNeedsUpdate() {
        LockScreenWallpaper.shared.scheduleUpdate { [weak self] done in
            guard let self else { done([]); return }
            let active = self.controllers.values.filter { $0.note.showOnLockScreen && $0.panel.isVisible }
            guard !active.isEmpty else { done([]); return }
            // On masque la barre d'outils, on laisse SwiftUI redessiner, puis on prend la photo.
            active.forEach { $0.isCapturing = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let items = active.compactMap { c in c.snapshot().map { (c.panel.frame, $0) } }
                active.forEach { $0.isCapturing = false }
                done(items)
            }
        }
    }

    func isShown(id: UUID) -> Bool { controllers[id] != nil }
    var shownCount: Int { controllers.count }

    func show(_ note: Note) {
        if let c = controllers[note.id] {
            c.show()
            return
        }
        var n = note
        n.isOnDesktop = true
        n.frame = Self.ensureOnScreen(n.frame)
        store.upsert(n)
        let c = NoteWindowController(note: n, manager: self)
        controllers[n.id] = c
        c.show()
    }

    func toggle(id: UUID) {
        if let c = controllers[id] {
            c.hide()
        } else if let note = store.note(id: id) {
            show(note)
        }
    }

    func didHide(id: UUID) {
        controllers[id] = nil
    }

    @discardableResult
    func createNote(kind: NoteKind = .text, text: String = "") -> Note {
        var n = Note()
        n.kind = kind
        n.text = text
        n.frame = Self.newNoteFrame()
        store.upsert(n)
        show(n)
        if let c = controllers[n.id] {
            NSApp.activate(ignoringOtherApps: true)
            c.panel.makeKeyAndOrderFront(nil)
        }
        return n
    }

    func showAll() {
        for note in store.notes { show(note) }
    }

    func hideAll() {
        for c in Array(controllers.values) { c.hide() }
    }

    func delete(id: UUID) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Supprimer ce post-it ?"
        alert.informativeText = "Cette action est définitive."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Supprimer")
        alert.addButton(withTitle: "Annuler")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if let c = controllers[id] {
            c.panel.orderOut(nil)
            DispatchQueue.main.async { c.panel.contentView = nil }
        }
        controllers[id] = nil
        store.delete(id: id)
        lockScreenNeedsUpdate()
    }

    // MARK: Position

    private static func newNoteFrame() -> CGRect {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 240, height: 240)
        let x = screen.midX - size.width / 2 + CGFloat.random(in: -120...120)
        let y = screen.midY - size.height / 2 + CGFloat.random(in: -90...90)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// Si l'écran où était le post-it a été débranché, on le ramène sur l'écran principal.
    private static func ensureOnScreen(_ frame: CGRect) -> CGRect {
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        if visible { return frame }
        var f = newNoteFrame()
        f.size = frame.size
        return f
    }
}
