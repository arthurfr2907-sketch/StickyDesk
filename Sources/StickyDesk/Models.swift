import SwiftUI
import AppKit

// MARK: - Couleurs

enum NoteColor: String, Codable, CaseIterable, Identifiable {
    case yellow, pink, blue, green, orange, purple, gray

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yellow: return "Jaune"
        case .pink: return "Rose"
        case .blue: return "Bleu"
        case .green: return "Vert"
        case .orange: return "Orange"
        case .purple: return "Violet"
        case .gray: return "Gris"
        }
    }

    var color: Color {
        switch self {
        case .yellow: return Color(red: 1.00, green: 0.93, blue: 0.55)
        case .pink:   return Color(red: 1.00, green: 0.76, blue: 0.83)
        case .blue:   return Color(red: 0.72, green: 0.87, blue: 1.00)
        case .green:  return Color(red: 0.77, green: 0.93, blue: 0.72)
        case .orange: return Color(red: 1.00, green: 0.81, blue: 0.58)
        case .purple: return Color(red: 0.85, green: 0.78, blue: 1.00)
        case .gray:   return Color(red: 0.91, green: 0.91, blue: 0.89)
        }
    }
}

// MARK: - Formes

enum NoteShape: String, Codable, CaseIterable, Identifiable {
    case rounded, square, folded, circle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rounded: return "Arrondi"
        case .square: return "Carré"
        case .folded: return "Coin plié"
        case .circle: return "Rond"
        }
    }

    var shape: AnyShape {
        switch self {
        case .rounded: return AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .square:  return AnyShape(Rectangle())
        case .folded:  return AnyShape(FoldedCornerShape())
        case .circle:  return AnyShape(Ellipse())
        }
    }

    /// Marge intérieure pour que le texte reste dans la forme.
    var horizontalPadding: CGFloat { self == .circle ? 34 : 12 }
    var bottomPadding: CGFloat { self == .circle ? 34 : 12 }
    var topPadding: CGFloat { self == .circle ? 22 : 0 }
}

/// Rectangle dont le coin inférieur droit est coupé (effet papier plié).
struct FoldedCornerShape: Shape {
    var fold: CGFloat = 22
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - fold))
        p.addLine(to: CGPoint(x: r.maxX - fold, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Le petit rabat dessiné dans le coin plié.
struct FoldFlap: Shape {
    var fold: CGFloat = 22
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX - fold, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - fold, y: r.maxY - fold))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - fold))
        p.closeSubpath()
        return p
    }
}

// MARK: - Polices

enum NoteFont: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif, mono, handwritten, marker, bradley

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Système"
        case .rounded: return "Arrondie"
        case .serif: return "Serif"
        case .mono: return "Machine à écrire"
        case .handwritten: return "Manuscrite"
        case .marker: return "Feutre"
        case .bradley: return "Écriture à la main"
        }
    }

    func nsFont(size: CGFloat) -> NSFont {
        switch self {
        case .system: return .systemFont(ofSize: size)
        case .rounded: return Self.systemDesign(.rounded, size)
        case .serif: return Self.systemDesign(.serif, size)
        case .mono: return .monospacedSystemFont(ofSize: size, weight: .regular)
        case .handwritten: return NSFont(name: "Noteworthy-Light", size: size) ?? .systemFont(ofSize: size)
        case .marker: return NSFont(name: "MarkerFelt-Thin", size: size) ?? .systemFont(ofSize: size)
        case .bradley: return NSFont(name: "BradleyHandITCTT-Bold", size: size) ?? .systemFont(ofSize: size)
        }
    }

    /// Retrouve la police de la liste qui correspond à une NSFont.
    static func matching(_ font: NSFont) -> NoteFont? {
        allCases.first { $0.nsFont(size: font.pointSize).familyName == font.familyName }
    }

    private static func systemDesign(_ design: NSFontDescriptor.SystemDesign, _ size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        if let desc = base.fontDescriptor.withDesign(design),
           let font = NSFont(descriptor: desc, size: size) {
            return font
        }
        return base
    }
}

struct NoteFontSize: Hashable {
    let label: String
    let size: Double

    static let all: [NoteFontSize] = [
        NoteFontSize(label: "Petite", size: 12),
        NoteFontSize(label: "Normale", size: 14),
        NoteFontSize(label: "Moyenne", size: 16),
        NoteFontSize(label: "Grande", size: 19),
        NoteFontSize(label: "Très grande", size: 23),
        NoteFontSize(label: "Titre", size: 28)
    ]
}

// MARK: - Listes

enum ListStyle {
    case bullet, numbered, arrow
}

/// Préfixe de liste en début de ligne : "• ", "→ " ou "12. "
struct ListPrefix {
    let style: ListStyle
    let number: Int
    let length: Int   // en unités UTF-16 (NSString)

    static func string(_ style: ListStyle, number: Int) -> String {
        switch style {
        case .bullet: return "• "
        case .arrow: return "→ "
        case .numbered: return "\(number). "
        }
    }

    /// Fin du paragraphe, sans le retour à la ligne.
    static func contentEnd(_ pr: NSRange, in ns: NSString) -> Int {
        let end = NSMaxRange(pr)
        if end > pr.location, ns.character(at: end - 1) == 10 { return end - 1 }
        return end
    }

    static func detect(in ns: NSString, paragraph pr: NSRange) -> ListPrefix? {
        let end = contentEnd(pr, in: ns)
        let len = min(end - pr.location, 8)
        guard len >= 2 else { return nil }
        let head = ns.substring(with: NSRange(location: pr.location, length: len))
        if head.hasPrefix("• ") { return ListPrefix(style: .bullet, number: 0, length: 2) }
        if head.hasPrefix("→ ") { return ListPrefix(style: .arrow, number: 0, length: 2) }
        var digits = ""
        for ch in head {
            if ch.isASCII && ch.isNumber { digits.append(ch) } else { break }
        }
        if !digits.isEmpty, head.dropFirst(digits.count).hasPrefix(". "), let n = Int(digits) {
            return ListPrefix(style: .numbered, number: n, length: digits.count + 2)
        }
        return nil
    }

    /// Tous les paragraphes touchés par une plage.
    static func paragraphs(in ns: NSString, covering range: NSRange) -> [NSRange] {
        let full = ns.paragraphRange(for: range)
        if full.length == 0 { return [full] }
        var result: [NSRange] = []
        var loc = full.location
        while loc < NSMaxRange(full) {
            let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            result.append(pr)
            if NSMaxRange(pr) <= loc { break }
            loc = NSMaxRange(pr)
        }
        return result
    }
}

// MARK: - Contenu

enum NoteKind: String, Codable {
    case text, checklist
}

struct ChecklistItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var done = false
    var font: NoteFont? = nil       // nil = police système d'origine
    var fontSize: Double? = nil

    var nsFont: NSFont {
        (font ?? .system).nsFont(size: CGFloat(fontSize ?? 14))
    }
}

// MARK: - Post-it

struct Note: Codable, Identifiable {
    var id = UUID()
    var text = ""                 // version texte brut (titre, recherche)
    var rtf: Data? = nil           // version mise en forme (polices)
    var items: [ChecklistItem] = []
    var kind: NoteKind = .text
    var color: NoteColor = .yellow
    var shape: NoteShape = .rounded
    var pinnedOnTop = false          // false = posé sur le bureau, true = toujours au premier plan
    var showOnLockScreen = false     // incrusté dans le fond d'écran (visible Mac verrouillé)
    var opacity: Double = 1.0
    var font: NoteFont = .system
    var fontSize: Double = 14
    var isOnDesktop = true           // visible sur le bureau ou rangé dans le tiroir
    var frame = CGRect(x: 200, y: 200, width: 240, height: 240)
    var createdAt = Date()

    init() {}

    // Décodage tolérant : si on ajoute des champs plus tard,
    // les anciens fichiers restent lisibles.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        id = get(.id, UUID())
        text = get(.text, "")
        rtf = try? c.decodeIfPresent(Data.self, forKey: .rtf)
        items = get(.items, [])
        kind = get(.kind, .text)
        color = get(.color, .yellow)
        shape = .rounded   // options Forme et Opacité retirées : on revient au style par défaut
        pinnedOnTop = get(.pinnedOnTop, false)
        showOnLockScreen = get(.showOnLockScreen, false)
        opacity = 1.0
        font = get(.font, .system)
        fontSize = get(.fontSize, 14)
        isOnDesktop = get(.isOnDesktop, true)
        frame = get(.frame, CGRect(x: 200, y: 200, width: 240, height: 240))
        createdAt = get(.createdAt, Date())
    }

    /// Titre affiché dans le menu (première ligne non vide).
    var displayTitle: String {
        let source: String
        switch kind {
        case .text:
            source = text.split(separator: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map(String.init) ?? ""
        case .checklist:
            source = items.first?.text ?? ""
        }
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return kind == .checklist ? "To-do list vide" : "Post-it vide" }
        return trimmed.count > 32 ? String(trimmed.prefix(32)) + "…" : trimmed
    }
}
