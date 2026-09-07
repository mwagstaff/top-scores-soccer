import Foundation
import Observation

/// One actor owns network checks and the atomic cache. A match receives value copies.
actor PremierLeagueRepository {
    static let endpoint = URL(string: "https://api.skynolimit.dev/top-scores/api/v1/reference/competitions/1/export")!
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    struct Result: Sendable {
        var catalogue: PremierLeagueCatalogue
        var checkedAt: Date
        var source: String
    }

    private struct Cache: Codable {
        var export: Data
        var etag: String?
        var checkedAt: Date
    }

    private let cacheURL: URL
    private let fetch: Fetch
    private let appearanceOverrides: [String: PlayerAppearance]
    private var cache: Cache?
    private var hasReadCache = false
    private var retryNotBefore: Date?

    init(cacheDirectory: URL? = nil, appearanceOverrides: [String: PlayerAppearance] = [:], fetch: Fetch? = nil) {
        let directory = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PremierLeague", isDirectory: true)
        self.cacheURL = directory.appendingPathComponent("catalogue-cache.json")
        self.appearanceOverrides = appearanceOverrides
        self.fetch = fetch ?? { request in try await URLSession.shared.data(for: request) }
    }

    func cached() -> Result? {
        readCacheIfNeeded()
        guard let cache, let catalogue = try? PremierLeagueCatalogue.decode(cache.export, appearanceOverrides: appearanceOverrides) else { return nil }
        return Result(catalogue: catalogue, checkedAt: cache.checkedAt, source: "Saved league data")
    }

    func refresh(force: Bool = false, now: Date = Date()) async throws -> Result {
        readCacheIfNeeded()
        try Task.checkCancellation()
        if !force, let cached = cached(), now.timeIntervalSince(cached.checkedAt) < 24 * 60 * 60 { return cached }
        if let retryNotBefore, now < retryNotBefore { throw CatalogueError.rateLimited }

        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag = cache?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await fetch(request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw CatalogueError.invalidResponse }
        if response.statusCode == 304 {
            guard var unchanged = cache else { throw CatalogueError.invalidResponse }
            let catalogue = try PremierLeagueCatalogue.decode(unchanged.export, appearanceOverrides: appearanceOverrides)
            unchanged.checkedAt = now
            try persist(unchanged)
            cache = unchanged
            return Result(catalogue: catalogue, checkedAt: now, source: "League data up to date")
        }
        guard response.statusCode == 200 else {
            if response.statusCode == 429 || response.statusCode == 503 {
                let delay = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 60
                retryNotBefore = now.addingTimeInterval(max(1, delay))
            }
            switch response.statusCode {
            case 429: throw CatalogueError.rateLimited
            case 503: throw CatalogueError.unavailable
            default: throw CatalogueError.http(response.statusCode)
            }
        }
        guard data.count <= 15_000_000 else { throw CatalogueError.invalidSnapshot }
        // Decode and validate the entire unpaginated export before replacing any usable data.
        let catalogue = try PremierLeagueCatalogue.decode(data, appearanceOverrides: appearanceOverrides)
        try Task.checkCancellation()
        let staged = Cache(export: data, etag: response.value(forHTTPHeaderField: "ETag"), checkedAt: now)
        try persist(staged)
        cache = staged
        retryNotBefore = nil
        return Result(catalogue: catalogue, checkedAt: now, source: "Latest league data")
    }

    private func readCacheIfNeeded() {
        guard !hasReadCache else { return }
        hasReadCache = true
        guard let data = try? Data(contentsOf: cacheURL), let saved = try? JSONDecoder().decode(Cache.self, from: data),
              (try? PremierLeagueCatalogue.decode(saved.export, appearanceOverrides: appearanceOverrides)) != nil else { return }
        cache = saved
    }

    private func persist(_ staged: Cache) throws {
        let data = try JSONEncoder().encode(staged)
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // The export and its ETag are one file, so interruption cannot pair unrelated versions.
        try data.write(to: cacheURL, options: .atomic)
    }
}

@MainActor @Observable
final class PremierLeagueStore {
    private(set) var teams: [ClubTeam] = []
    private(set) var seasonName = "Premier League"
    private(set) var snapshotID = ""
    private(set) var publishedAt: String?
    private(set) var sourceDescription = "Included league data"
    private(set) var statusMessage = ""
    private(set) var isRefreshing = false
    @ObservationIgnored private let repository: PremierLeagueRepository
    @ObservationIgnored private var hasLoadedCache = false

    init(repository: PremierLeagueRepository? = nil, bundle: Bundle = .main) {
        self.repository = repository ?? PremierLeagueRepository(appearanceOverrides: PremierLeagueCatalogue.appearanceOverrides(bundle: bundle))
        do { apply(try .bundled(bundle: bundle), source: "Included league data") }
        catch { statusMessage = error.localizedDescription }
    }

    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if !hasLoadedCache {
            hasLoadedCache = true
            if let result = await repository.cached(), isAtLeastAsRecent(result.catalogue) {
                apply(result.catalogue, source: result.source)
            }
        }
        do {
            let result = try await repository.refresh(force: force)
            try Task.checkCancellation()
            if isAtLeastAsRecent(result.catalogue) { apply(result.catalogue, source: result.source) }
        } catch is CancellationError {
            // Leaving the picker cancels a check without presenting a misleading failure.
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            statusMessage = teams.isEmpty ? error.localizedDescription : "Using saved league data. \(error.localizedDescription)"
        }
    }

    private func isAtLeastAsRecent(_ catalogue: PremierLeagueCatalogue) -> Bool {
        guard !teams.isEmpty, let current = publishedAt, let incoming = catalogue.publishedAt else { return true }
        return incoming >= current
    }

    private func apply(_ catalogue: PremierLeagueCatalogue, source: String) {
        teams = catalogue.teams
        seasonName = catalogue.seasonName
        snapshotID = catalogue.snapshotID
        publishedAt = catalogue.publishedAt
        sourceDescription = source
        statusMessage = catalogue.isStale ? "The service reports this snapshot is older. You can still play." : ""
    }
}
