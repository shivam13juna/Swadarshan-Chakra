import Foundation
import MeditationCore

/// Where the practice history is kept: one small file in Application Support for the app itself, or
/// memory alone for the previews, the smoke test, and the timer check, which must never touch it.
@MainActor
final class PracticeStore {
    let url: URL?
    /// The history as it was read when the store opened.
    let initial: PracticeHistory

    private init(url: URL?, initial: PracticeHistory) {
        self.url = url
        self.initial = initial
    }

    static func memory(_ history: PracticeHistory = PracticeHistory()) -> PracticeStore {
        PracticeStore(url: nil, initial: history)
    }

    /// ~/Library/Application Support/Swadarshan Chakra/practice-history.json, in the backup file's format.
    static func standard() -> PracticeStore {
        file(at: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Swadarshan Chakra", isDirectory: true)
            .appendingPathComponent("practice-history.json"))
    }

    static func file(at url: URL) -> PracticeStore {
        guard let data = try? Data(contentsOf: url) else { return PracticeStore(url: url, initial: PracticeHistory()) }
        do {
            return PracticeStore(url: url, initial: try PracticeHistory.read(data).history)
        } catch {
            // Never write over a history that can't be read: set it aside and begin a new one.
            let aside = url.deletingLastPathComponent()
                .appendingPathComponent("practice-history (unreadable \(Int(Date().timeIntervalSince1970))).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return PracticeStore(url: url, initial: PracticeHistory())
        }
    }

    @discardableResult
    func save(_ history: PracticeHistory) -> Bool {
        guard let url else { return true }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try history.document().write(to: url, options: .atomic)
            return true
        } catch {
            fputs("The practice history couldn't be saved: \(error.localizedDescription)\n", stderr)
            return false
        }
    }
}
