import Foundation
import Observation

@MainActor @Observable
final class WorldCupStore {
    private(set) var save: WorldCupSave?
    private(set) var loadError: String?
    private(set) var actionError: String?
    @ObservationIgnored let saveURL: URL
    @ObservationIgnored private let write: (Data, URL) throws -> Void

    init(saveURL: URL? = nil, write: ((Data, URL) throws -> Void)? = nil) {
        let arguments = ProcessInfo.processInfo.arguments
        let uiTesting = arguments.contains("--world-cup-ui-testing")
        let directory: URL
        if uiTesting {
            let proposedID = ProcessInfo.processInfo.environment["WORLD_CUP_TEST_STORE_ID"] ?? "default"
            let safeID = String(proposedID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }.prefix(100))
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("WorldCupUITests", isDirectory: true)
                .appendingPathComponent(safeID.isEmpty ? "default" : safeID, isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("WorldCup", isDirectory: true)
        }
        self.saveURL = saveURL ?? directory.appendingPathComponent("world-cup.json")
        self.write = write ?? { data, url in
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        if uiTesting, saveURL == nil, arguments.contains("--reset-world-cup-ui") { try? FileManager.default.removeItem(at: self.saveURL) }
        load()
    }

    func start(teamID: String, date: Date = Date()) throws {
        try perform {
            var staged = try WorldCupSave.new(selectedTeamID: teamID, date: date)
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--world-cup-final-ui") {
                let win = WorldCupUserMatchOutcome(regulationUserGoals: 1, regulationOpponentGoals: 0,
                    userGoals: 1, opponentGoals: 0, wentToExtraTime: false,
                    userPenalties: nil, opponentPenalties: nil)
                for _ in 0..<7 {
                    let ticket = try staged.prepareMatch()
                    try staged.completeFixture(ticketID: ticket.id, outcome: win)
                }
            }
#endif
            try persist(staged)
        }
    }

    func prepareMatch() throws -> WorldCupMatchTicket {
        guard let save else { throw WorldCupError.noTournament }
        return try save.prepareMatch()
    }

    func updateLineup(_ lineup: ClubLineup) throws {
        try perform {
            guard var staged = save else { throw WorldCupError.noTournament }
            try staged.updateLineup(lineup)
            try persist(staged)
        }
    }

    @discardableResult
    func completeFixture(ticketID: String, outcome: WorldCupUserMatchOutcome) throws -> Bool {
        try perform {
            guard var staged = save else { throw WorldCupError.noTournament }
            let changed = try staged.completeFixture(ticketID: ticketID, outcome: outcome)
            if changed { try persist(staged) }
            return changed
        }
    }

    func finishTournament() throws {
        try perform {
            guard var staged = save else { throw WorldCupError.noTournament }
            try staged.finishTournament()
            try persist(staged)
        }
    }

    func acknowledgeCelebration() throws {
        try perform {
            guard var staged = save else { throw WorldCupError.noTournament }
            staged.acknowledgeCelebration()
            try persist(staged)
        }
    }

    func deleteTournament() throws {
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
            guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 30_000_000 else { throw WorldCupError.unreadableSave }
            let data = try Data(contentsOf: saveURL)
            let decoded = try JSONDecoder().decode(WorldCupSave.self, from: data)
            try decoded.validate()
            save = decoded
        } catch {
            loadError = (error as? WorldCupError ?? .unreadableSave).localizedDescription
        }
    }

    private func persist(_ staged: WorldCupSave) throws {
        try staged.validate()
        let data = try JSONEncoder().encode(staged)
        guard data.count <= 30_000_000 else { throw WorldCupError.saveTooLarge }
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
            actionError = "Your World Cup was not changed. \(error.localizedDescription)"
            throw error
        }
    }
}
