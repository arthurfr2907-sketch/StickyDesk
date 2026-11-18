import AppKit

/// Affiche les post-it "écran verrouillé" en les incrustant dans le fond d'écran.
/// (macOS montre le fond d'écran sur l'écran verrouillé ; aucune app ne peut y afficher une fenêtre.)
/// Le fond d'écran d'origine est mémorisé et remis quand plus aucun post-it n'utilise l'option.
final class LockScreenWallpaper {
    static let shared = LockScreenWallpaper()

    private let folder: URL
    private let defaultsKey = "StickyDesk.originalWallpapers"
    private var work: DispatchWorkItem?

    private init() {
        folder = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StickyDesk/LockScreen", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// `collect` fournit (de façon asynchrone) les post-it à incruster : cadre + image.
    func scheduleUpdate(delay: TimeInterval = 1.5,
                        collect: @escaping (@escaping ([(NSRect, NSImage)]) -> Void) -> Void) {
        work?.cancel()
        let w = DispatchWorkItem { [weak self] in
            collect { items in self?.apply(items) }
        }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    // MARK: Fonds d'écran d'origine

    private var originals: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    private func key(for screen: NSScreen) -> String {
        if let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return n.stringValue
        }
        return screen.localizedName
    }

    private func isOurs(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path)
    }

    // MARK: Mise à jour

    private func apply(_ items: [(NSRect, NSImage)]) {
        if items.isEmpty {
            restoreOriginals()
            return
        }
        let ws = NSWorkspace.shared
        var saved = originals

        for screen in NSScreen.screens {
            let k = key(for: screen)
            if let current = ws.desktopImageURL(for: screen), !isOurs(current) {
                saved[k] = current.path   // le vrai fond d'écran de l'utilisateur
            }
            let base = saved[k].flatMap { NSImage(contentsOf: URL(fileURLWithPath: $0)) }
            guard let data = render(screen: screen, base: base, items: items) else { continue }

            // Nom unique à chaque fois : sinon macOS garde l'ancienne image en cache.
            let url = folder.appendingPathComponent("lock-\(k)-\(Int(Date().timeIntervalSince1970 * 1000)).png")
            do {
                try data.write(to: url)
                try ws.setDesktopImageURL(url, for: screen, options: [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                    .allowClipping: true
                ])
            } catch {
                NSLog("StickyDesk – fond d'écran : \(error)")
            }
        }
        originals = saved
        cleanUpLater()
    }

    private func restoreOriginals() {
        let saved = originals
        guard !saved.isEmpty else { return }
        let ws = NSWorkspace.shared
        for screen in NSScreen.screens {
            guard isOurs(ws.desktopImageURL(for: screen)), let path = saved[key(for: screen)] else { continue }
            try? ws.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true
            ])
        }
        originals = [:]
        cleanUpLater()
    }

    /// Supprime les anciennes images qui ne sont plus utilisées.
    private func cleanUpLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [folder] in
            let inUse = Set(NSScreen.screens.compactMap {
                NSWorkspace.shared.desktopImageURL(for: $0)?.standardizedFileURL.path
            })
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for f in files where !inUse.contains(f.standardizedFileURL.path) {
                try? FileManager.default.removeItem(at: f)
            }
        }
    }

    // MARK: Dessin

    private func render(screen: NSScreen, base: NSImage?, items: [(NSRect, NSImage)]) -> Data? {
        let frame = screen.frame
        let scale = screen.backingScaleFactor
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(frame.width * scale), pixelsHigh: Int(frame.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = frame.size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        let canvas = NSRect(origin: .zero, size: frame.size)
        NSColor(white: 0.15, alpha: 1).setFill()
        canvas.fill()
        if let base {
            base.draw(in: Self.aspectFill(base.size, in: canvas), from: .zero, operation: .copy, fraction: 1)
        }
        for (rect, image) in items where rect.intersects(frame) {
            let r = rect.offsetBy(dx: -frame.minX, dy: -frame.minY)
            image.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
        }

        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private static func aspectFill(_ size: NSSize, in rect: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let s = max(rect.width / size.width, rect.height / size.height)
        let w = size.width * s, h = size.height * s
        return NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}
