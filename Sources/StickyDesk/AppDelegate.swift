import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let manager = NoteWindowManager()
    private let notesMenu = NSMenu(title: "Post-it")
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        closeOtherCopies()
        setupMainMenu()
        setupStatusItem()

        if NoteStore.shared.notes.isEmpty {
            manager.createNote(text: """
            Bienvenue 👋

            • Survole le post-it pour voir la barre d'outils
            • Glisse la bande du haut pour le déplacer
            • Coin en bas à droite pour redimensionner
            • Clic droit sur l'icône du Dock : tous tes post-it
            """)
        } else {
            manager.restore()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NoteStore.shared.saveNow()
    }

    /// Clic sur l'icône du Dock : réaffiche les post-it s'il n'y en a aucun à l'écran.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if NoteStore.shared.notes.isEmpty {
            manager.createNote()
        } else if manager.shownCount == 0 {
            manager.showAll()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clic droit sur l'icône du Dock
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(item("Nouveau post-it", #selector(newNote)))
        menu.addItem(item("Nouvelle to-do list", #selector(newChecklist)))
        menu.addItem(.separator())
        fillNotes(menu)
        return menu
    }

    /// Ferme les anciennes copies de StickyDesk encore ouvertes
    /// (ex. version lancée depuis Xcode) : sinon leur icône reste dans la barre de menus.
    private func closeOtherCopies() {
        let me = NSRunningApplication.current
        let myID = Bundle.main.bundleIdentifier
        let others = NSWorkspace.shared.runningApplications.filter { app in
            guard app != me else { return false }
            if let myID, app.bundleIdentifier == myID { return true }
            return app.executableURL?.lastPathComponent == "StickyDesk"
        }
        for app in others {
            app.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if !app.isTerminated { app.forceTerminate() }
            }
        }
    }

    // MARK: Icône dans la barre de menus (en haut à droite)

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBarIcon()
        item.button?.toolTip = "StickyDesk"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Le post-it à coin plié du logo, dessiné en noir : macOS l'adapte au mode clair / sombre.
    static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let r = NSRect(x: 2.5, y: 2.5, width: 13, height: 13)
            let fold: CGFloat = 4.5
            let radius: CGFloat = 3

            let outline = NSBezierPath()
            outline.move(to: NSPoint(x: r.minX + radius, y: r.minY))
            outline.line(to: NSPoint(x: r.maxX - radius, y: r.minY))
            outline.appendArc(from: NSPoint(x: r.maxX, y: r.minY),
                              to: NSPoint(x: r.maxX, y: r.minY + radius), radius: radius)
            outline.line(to: NSPoint(x: r.maxX, y: r.maxY - fold))
            outline.line(to: NSPoint(x: r.maxX - fold, y: r.maxY))
            outline.line(to: NSPoint(x: r.minX + radius, y: r.maxY))
            outline.appendArc(from: NSPoint(x: r.minX, y: r.maxY),
                              to: NSPoint(x: r.minX, y: r.maxY - radius), radius: radius)
            outline.line(to: NSPoint(x: r.minX, y: r.minY + radius))
            outline.appendArc(from: NSPoint(x: r.minX, y: r.minY),
                              to: NSPoint(x: r.minX + radius, y: r.minY), radius: radius)
            outline.close()
            outline.lineWidth = 1.6
            outline.lineJoinStyle = .round
            NSColor.black.setStroke()
            outline.stroke()

            let flap = NSBezierPath()
            flap.move(to: NSPoint(x: r.maxX - fold, y: r.maxY))
            flap.line(to: NSPoint(x: r.maxX - fold, y: r.maxY - fold))
            flap.line(to: NSPoint(x: r.maxX, y: r.maxY - fold))
            flap.close()
            flap.lineWidth = 1.6
            flap.lineJoinStyle = .round
            NSColor.black.setFill()
            flap.fill()
            flap.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: Barre de menus de l'app (en haut à gauche quand StickyDesk est active)

    private func setupMainMenu() {
        let main = NSMenu()

        // StickyDesk
        let appMenu = NSMenu(title: "StickyDesk")
        appMenu.addItem(withTitle: "À propos de StickyDesk",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quitter StickyDesk",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(appMenu, to: main)

        // Fichier
        let fileMenu = NSMenu(title: "Fichier")
        fileMenu.addItem(item("Nouveau post-it", #selector(newNote), key: "n"))
        fileMenu.addItem(item("Nouvelle to-do list", #selector(newChecklist), key: "t"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Ouvrir le dossier des données", #selector(openDataFolder)))
        addSubmenu(fileMenu, to: main)

        // Édition
        let editMenu = NSMenu(title: "Édition")
        editMenu.addItem(withTitle: "Annuler", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Rétablir", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(editMenu, to: main)

        // Post-it (liste, reconstruite à chaque ouverture)
        notesMenu.delegate = self
        addSubmenu(notesMenu, to: main)

        NSApp.mainMenu = main
    }

    private func addSubmenu(_ submenu: NSMenu, to main: NSMenu) {
        let holder = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        holder.submenu = submenu
        main.addItem(holder)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === notesMenu {
            menu.removeAllItems()
            fillNotes(menu)
        } else if menu === statusItem?.menu {
            menu.removeAllItems()
            menu.addItem(item("Nouveau post-it", #selector(newNote)))
            menu.addItem(item("Nouvelle to-do list", #selector(newChecklist)))
            menu.addItem(.separator())
            fillNotes(menu)
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quitter StickyDesk",
                                    action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        }
    }

    /// Liste de tous les post-it (cochés = posés sur le bureau).
    private func fillNotes(_ menu: NSMenu) {
        let notes = NoteStore.shared.notes.sorted { $0.createdAt > $1.createdAt }
        if notes.isEmpty {
            let empty = NSMenuItem(title: "Aucun post-it", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for note in notes {
            let it = item(note.displayTitle, #selector(toggleNote(_:)))
            it.representedObject = note.id
            it.state = manager.isShown(id: note.id) ? .on : .off
            it.image = swatch(for: note.color)
            menu.addItem(it)
        }
        menu.addItem(.separator())
        menu.addItem(item("Tout afficher", #selector(showAll)))
        menu.addItem(item("Tout ranger", #selector(hideAll)))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        return it
    }

    /// Petite pastille de couleur à côté du nom du post-it.
    private func swatch(for color: NoteColor) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        return NSImage(size: size, flipped: false) { rect in
            NSColor(color.color).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
            return true
        }
    }

    // MARK: Actions

    @objc private func newNote() { manager.createNote() }
    @objc private func newChecklist() { manager.createNote(kind: .checklist) }

    @objc private func toggleNote(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        manager.toggle(id: id)
    }

    @objc private func showAll() { manager.showAll() }
    @objc private func hideAll() { manager.hideAll() }

    @objc private func openDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([NoteStore.shared.fileURL])
    }
}
