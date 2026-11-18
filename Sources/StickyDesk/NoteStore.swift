import Foundation

/// Sauvegarde les post-it dans ~/Library/Application Support/StickyDesk/notes.json
final class NoteStore {
    static let shared = NoteStore()

    private(set) var notes: [Note] = []
    let fileURL: URL
    private var saveWork: DispatchWorkItem?

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StickyDesk", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("notes.json")
        load()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else { return }
        do {
            notes = try JSONDecoder().decode([Note].self, from: data)
        } catch {
            // Fichier illisible : on le met de côté au lieu de l'écraser.
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("notes-corrompu-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            notes = []
        }
    }

    func note(id: UUID) -> Note? {
        notes.first { $0.id == id }
    }

    func upsert(_ note: Note) {
        if let i = notes.firstIndex(where: { $0.id == note.id }) {
            notes[i] = note
        } else {
            notes.append(note)
        }
        scheduleSave()
    }

    func delete(id: UUID) {
        notes.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Sauvegarde regroupée (pas à chaque frappe de clavier).
    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(notes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
