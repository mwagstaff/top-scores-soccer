import Foundation
import Observation

/// One atomic file contains the frozen catalogue, schedule, results and selected XI.
/// No observable progress changes until its complete replacement reaches disk.
@MainActor @Observable
final class CareerStore {
    private(set) var save: CareerSave?
    private(set) var loadError: String?
    private(set) var actionError: String?
    @ObservationIgnored let saveURL: URL
    @ObservationIgnored private let write: (Data, URL) throws -> Void
    @ObservationIgnored private let startsAtFinalMatchForUITest: Bool

    init(saveURL: URL? = nil, write: ((Data, URL) throws -> Void)? = nil) {
        let arguments = ProcessInfo.processInfo.arguments
        let uiTesting = arguments.contains("--career-ui-testing")
        let directory: URL
        if uiTesting {
            let proposedID = ProcessInfo.processInfo.environment["CAREER_TEST_STORE_ID"] ?? "default"
            let safeID = String(proposedID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }.prefix(100))
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("CareerUITests", isDirectory: true)
                .appendingPathComponent(safeID.isEmpty ? "default" : safeID, isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Career", isDirectory: true)
        }
        self.saveURL = saveURL ?? directory.appendingPathComponent("career.json")
        self.startsAtFinalMatchForUITest = saveURL == nil && uiTesting
            && arguments.contains("--uitesting") && arguments.contains("--career-final-match-ui")
        self.write = write ?? { data, url in
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        if uiTesting, saveURL == nil, arguments.contains("--reset-career-ui") {
            try? FileManager.default.removeItem(at: self.saveURL)
        }
        load()
    }

    /// The caller confirms replacement when a career or unreadable saved file already exists.
    func start(teams: [ClubTeam], clubID: String, snapshotID: String, date: Date = Date()) throws {
        try perform {
            var staged = try CareerSave.new(teams: teams, clubID: clubID, snapshotID: snapshotID, date: date)
            if startsAtFinalMatchForUITest {
                for _ in 0..<37 {
                    let ticket = try staged.prepareMatch()
                    try staged.completeFixture(ticketID: ticket.id, userGoals: 0, opponentGoals: 0)
                }
            }
            try persist(staged)
        }
    }

    func prepareMatch() throws -> CareerMatchTicket {
        guard let save else { throw CareerError.noCareer }
        return try save.prepareMatch()
    }

    func updateLineup(_ lineup: ClubLineup) throws {
        try perform {
            guard var staged = save else { throw CareerError.noCareer }
            try staged.updateLineup(lineup)
            try persist(staged)
        }
    }

    @discardableResult
    func completeFixture(ticketID: String, userGoals: Int, opponentGoals: Int) throws -> Bool {
        try perform {
            guard var staged = save else { throw CareerError.noCareer }
            let changed = try staged.completeFixture(ticketID: ticketID, userGoals: userGoals, opponentGoals: opponentGoals)
            if changed { try persist(staged) }
            return changed
        }
    }

    func startNextSeason() throws {
        try perform {
            guard var staged = save else { throw CareerError.noCareer }
            try staged.startNextSeason()
            try persist(staged)
        }
    }

    /// Call only after the user confirms deletion, including recovery from an unreadable save.
    func deleteCareer() throws {
        try perform {
            if FileManager.default.fileExists(atPath: saveURL.path) { try FileManager.default.removeItem(at: saveURL) }
            save = nil
            loadError = nil
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: saveURL.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 30_000_000 else { throw CareerError.unreadableSave }
            let data = try Data(contentsOf: saveURL)
            let decoded = try JSONDecoder().decode(CareerSave.self, from: data)
            try decoded.validate()
            save = decoded
        } catch {
            loadError = (error as? CareerError ?? .unreadableSave).localizedDescription
        }
    }

    private func persist(_ staged: CareerSave) throws {
        try staged.validate()
        let data = try JSONEncoder().encode(staged)
        guard data.count <= 30_000_000 else { throw CareerError.saveTooLarge }
        try write(data, saveURL)
        save = staged
        loadError = nil
    }

    private func perform<T>(_ action: () throws -> T) throws -> T {
        do {
            let result = try action()
            actionError = nil
            return result
        } catch {
            actionError = "Your career was not changed. \(error.localizedDescription)"
            throw error
        }
    }
}
