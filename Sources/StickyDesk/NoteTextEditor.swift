import SwiftUI
import AppKit

/// Texte enrichi : chaque morceau de texte garde sa propre police.
/// Pas de barre de défilement, fond transparent.
struct NoteTextEditor: NSViewRepresentable {
    let controller: NoteWindowController

    static let textColor = NSColor(white: 0.12, alpha: 1)

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let tv = PlainPasteTextView(frame: .zero)
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainerInset = NSSize(width: 0, height: 4)

        tv.drawsBackground = false
        tv.isRichText = true
        tv.importsGraphics = false
        tv.usesFontPanel = false
        tv.allowsUndo = true
        tv.insertionPointColor = NSColor.black.withAlphaComponent(0.8)
        tv.delegate = context.coordinator

        // Chargement du contenu sauvegardé
        let note = controller.note
        let defaultFont = controller.defaultNSFont
        if let data = note.rtf,
           let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
            tv.textStorage?.setAttributedString(attributed)
        } else {
            tv.textStorage?.setAttributedString(NSAttributedString(
                string: note.text,
                attributes: [.font: defaultFont, .foregroundColor: Self.textColor]))
        }

        // Curseur à la fin, avec la police du dernier caractère (ou celle par défaut)
        let length = (tv.string as NSString).length
        tv.setSelectedRange(NSRange(location: length, length: 0))
        if length == 0 {
            tv.typingAttributes = [.font: defaultFont, .foregroundColor: Self.textColor]
        }

        scroll.documentView = tv
        let controller = self.controller
        DispatchQueue.main.async { [weak tv] in
            if let tv { controller.attach(tv) }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        // Le contenu vit dans le NSTextView : rien à resynchroniser ici.
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let controller: NoteWindowController
        init(controller: NoteWindowController) { self.controller = controller }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            controller.textChanged(tv)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            controller.refreshCurrentFont()
        }

        /// Entrée dans une liste → nouvelle puce / numéro suivant.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return controller.handleNewline(in: textView)
            }
            return false
        }
    }
}

/// Le collage se fait sans mise en forme : le texte collé prend la police en cours.
final class PlainPasteTextView: NSTextView {
    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }
}
