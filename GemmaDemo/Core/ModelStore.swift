import Foundation
import Observation

@Observable
final class ModelStore {

    private(set) var availableFiles: [GGUFFileInfo] = []
    private var assignments: [ModelSlot: GGUFFileInfo] = [:]
    private(set) var clearedSlots: Set<ModelSlot> = []

    private let documentsURL: URL
    private static let ggufMagic: [UInt8] = [0x47, 0x47, 0x55, 0x46]

    init(documentsURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        self.documentsURL = documentsURL
        restoreAssignments()
    }

    func refresh() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: documentsURL,
                                                 includingPropertiesForKeys: [.fileSizeKey],
                                                 options: .skipsHiddenFiles)) ?? []
        availableFiles = urls
            .filter { $0.pathExtension.lowercased() == "gguf" }
            .compactMap { url -> GGUFFileInfo? in
                guard validateMagic(url) else { return nil }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
                return GGUFFileInfo(id: url, name: url.lastPathComponent, sizeBytes: size,
                                    architecture: nil, contextLength: nil, hasTemplate: false)
            }
    }

    func assign(file: GGUFFileInfo, to slot: ModelSlot) {
        assignments[slot] = file
        persistAssignment(file.id, for: slot)
    }

    func clearAssignment(for slot: ModelSlot) {
        assignments[slot] = nil
        UserDefaults.standard.removeObject(forKey: bookmarkKey(slot))
    }

    func assignment(for slot: ModelSlot) -> GGUFFileInfo? {
        assignments[slot]
    }

    // MARK: - Private

    private func validateMagic(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let data = try? handle.read(upToCount: 4)
        return data.map { Array($0) == Self.ggufMagic } ?? false
    }

    private func bookmarkKey(_ slot: ModelSlot) -> String { "bookmark_\(slot.rawValue)" }

    private func persistAssignment(_ url: URL, for slot: ModelSlot) {
        guard let bookmark = try? url.bookmarkData(options: .minimalBookmark,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) else { return }
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey(slot))
    }

    private func restoreAssignments() {
        for slot in ModelSlot.allCases {
            guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey(slot)) else { continue }
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withoutUI,
                                      relativeTo: nil, bookmarkDataIsStale: &isStale),
                  !isStale, FileManager.default.fileExists(atPath: url.path) else {
                UserDefaults.standard.removeObject(forKey: bookmarkKey(slot))
                clearedSlots.insert(slot)
                continue
            }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
            assignments[slot] = GGUFFileInfo(id: url, name: url.lastPathComponent, sizeBytes: size,
                                              architecture: nil, contextLength: nil, hasTemplate: false)
        }
    }
}
