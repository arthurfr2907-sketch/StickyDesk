import AppKit

// Point d'entrée : app classique, avec son icône dans le Dock.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
