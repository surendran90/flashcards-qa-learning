import Foundation
import Observation

/// Loads and saves `progress.json`. Never touches any workbook.
@MainActor @Observable
public final class ProgressStore {
    public var data: ProgressData {
        didSet { scheduleSave() }
    }
    public private(set) var lastError: String?

    public let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    public nonisolated static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FlashCardsQA", isDirectory: true)
    }

    public init(folder: URL = ProgressStore.defaultFolder) {
        fileURL = folder.appendingPathComponent("progress.json")
        data = ProgressData()
        if let loaded = Self.load(from: fileURL) {
            data = loaded
        } else if let backup = Self.load(from: fileURL.appendingPathExtension("bak")) {
            data = backup
        }
        saveTask?.cancel()
    }

    static func load(from url: URL) -> ProgressData? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProgressData.self, from: raw)
    }

    /// Saves about 2 seconds after the last change.
    public func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    public func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let raw = try encoder.encode(data)
            if fm.fileExists(atPath: fileURL.path) {
                let backup = fileURL.appendingPathExtension("bak")
                try? fm.removeItem(at: backup)
                try? fm.copyItem(at: fileURL, to: backup)
            }
            try raw.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Could not save progress: \(error.localizedDescription)"
        }
    }
}
