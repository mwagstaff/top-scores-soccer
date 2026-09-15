import SwiftUI

/// The catalogue is loaded before presenting the match. Lineups are value snapshots,
/// so a background catalogue refresh cannot change a match already on the pitch.
struct FriendlySetupView: View {
    @AppStorage("gameDifficulty") private var difficulty = GameDifficulty.medium.rawValue
    @State private var store: PremierLeagueStore
    @State private var home: ClubLineup?
    @State private var away: ClubLineup?
    @State private var pickingClub: FriendlySide?
    @State private var editingLineup: FriendlySide?
    @State private var presentedMatch: PresentedFriendly?
    @State private var presentedPractice: PresentedPractice?

    init() {
        let catalogue = PremierLeagueStore()
        _store = State(initialValue: catalogue)
        _home = State(initialValue: catalogue.teams.first.map { FriendlyTeamPreferences.load($0) })
        _away = State(initialValue: catalogue.teams.dropFirst().first.map { FriendlyTeamPreferences.load($0) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    if let home, let away, let configuration {
                        matchup(home: home, away: away, configuration: configuration)
                    } else {
                        ContentUnavailableView("Clubs unavailable", systemImage: "soccerball",
                                               description: Text("Refresh the squads to choose your clubs."))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Difficulty", selection: $difficulty) {
                            ForEach(GameDifficulty.allCases, id: \.rawValue) { level in
                                Text(level.title).tag(level.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("friendly.difficulty")
                        Text((GameDifficulty(rawValue: difficulty) ?? .medium).description)
                            .font(.footnote).foregroundStyle(FriendlyStyle.secondary)
                    }
                    catalogueStatus
                }
                .frame(maxWidth: 700)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(FriendlyStyle.background)
            .safeAreaInset(edge: .bottom, spacing: 0) { kickoffBar }
            .navigationTitle("Top Scores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FriendlyStyle.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Solo practice", systemImage: "figure.soccer") {
                            presentedPractice = PresentedPractice(mode: .solo)
                        }
                        Button("Pass & defend", systemImage: "person.3.fill") {
                            presentedPractice = PresentedPractice(mode: .passing)
                        }
                    } label: {
                        Label("Training", systemImage: "sportscourt")
                    }
                    .accessibilityIdentifier("friendly.training")
                }
            }
            .sheet(item: $pickingClub) { side in
                FriendlyClubPicker(teams: store.teams, side: side,
                                   selectedID: lineup(for: side)?.team.id,
                                   unavailableID: lineup(for: side.opponent)?.team.id) { team in
                    setLineup(FriendlyTeamPreferences.load(team), for: side)
                    pickingClub = nil
                }
            }
            .sheet(item: $editingLineup) { side in
                if let lineup = lineup(for: side) {
                    FriendlyLineupEditor(lineup: lineup) { updated in
                        setLineup(updated, for: side)
                        editingLineup = nil
                    }
                }
            }
            .fullScreenCover(item: $presentedMatch, onDismiss: updateAvailableLineups) { match in
                PreMatchGate(configuration: match.configuration, onExit: { presentedMatch = nil }, onSave: { lineup in
                    setLineup(lineup, for: .home)
                }) { prepared, playing in
                    SandboxView(configuration: prepared, onRematch: { playing.wrappedValue = false }, onExit: { presentedMatch = nil })
                }
            }
            .fullScreenCover(item: $presentedPractice) { practice in
                SandboxView(startingMode: practice.mode, onExit: { presentedPractice = nil })
            }
            .task { await store.refresh() }
            .onChange(of: store.snapshotID) { _, _ in updateAvailableLineups() }
        }
        .tint(FriendlyStyle.lime)
        .preferredColorScheme(.dark)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("PREMIER LEAGUE", systemImage: "soccerball")
                .font(.caption.bold()).tracking(1.8).foregroundStyle(FriendlyStyle.lime)
            Text("Make it a match.")
                .font(.largeTitle.bold()).foregroundStyle(.white)
            Text("Real clubs. Your starting XI. Three minutes to settle it.")
                .font(.subheadline).foregroundStyle(FriendlyStyle.secondary)
            Text("11-a-side friendly · You control the home side")
                .font(.caption).foregroundStyle(FriendlyStyle.secondary)
        }
    }

    private func matchup(home: ClubLineup, away: ClubLineup, configuration: FriendlyMatchConfiguration) -> some View {
        let kits = MatchKits.resolve(configuration: configuration)
        return VStack(spacing: 16) {
            clubCard(home, side: .home, kit: kits.home, alternative: false)
            HStack(spacing: 12) {
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                Text("VS").font(.caption.bold()).foregroundStyle(FriendlyStyle.secondary)
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            }
            .accessibilityHidden(true)
            clubCard(away, side: .away, kit: kits.away, alternative: kits.awayIsClash)
        }
    }

    private func clubCard(_ lineup: ClubLineup, side: FriendlySide, kit: ClubKit, alternative: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { pickingClub = side } label: {
                HStack(spacing: 16) {
                    FriendlyKitPreview(kit: kit).frame(width: 60, height: 72)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(side == .home ? "HOME · YOUR CLUB" : "AWAY · OPPONENT")
                            .font(.caption2.bold()).tracking(1.1).foregroundStyle(FriendlyStyle.lime)
                        Text(lineup.team.name).font(.title3.bold()).foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(alternative ? "Clash kit" : "Club colours")
                            .font(.caption).foregroundStyle(FriendlyStyle.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.bold()).foregroundStyle(FriendlyStyle.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(side.title) club, \(lineup.team.name)")
            .accessibilityHint("Choose another Premier League club")
            .accessibilityIdentifier("friendly.\(side.rawValue).club")

            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
            Button { editingLineup = side } label: {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Starting XI").font(.subheadline.bold()).foregroundStyle(.white)
                        Text("\(lineup.formation.title) · \(lineup.players.count) players")
                            .font(.caption).foregroundStyle(FriendlyStyle.secondary)
                    }
                    Spacer()
                    Image(systemName: "person.3.sequence.fill")
                        .font(.body).foregroundStyle(FriendlyStyle.lime)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold()).foregroundStyle(FriendlyStyle.secondary)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(side.title) starting XI, \(lineup.formation.title), \(lineup.players.count) players")
            .accessibilityIdentifier("friendly.\(side.rawValue).lineup")
        }
        .padding(18)
        .background(FriendlyStyle.panel, in: RoundedRectangle(cornerRadius: 22))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22)
                .fill(Color(hex: kit.shirtHex)).frame(width: 4).padding(.vertical, 18)
                .accessibilityHidden(true)
        }
    }

    private var catalogueStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.seasonName.isEmpty ? "Premier League squads" : "\(store.seasonName) squads")
                        .font(.footnote.bold())
                    Text(store.sourceDescription)
                        .font(.caption).foregroundStyle(FriendlyStyle.secondary)
                    if let published = formattedPublicationDate {
                        Text("Updated \(published)").font(.caption).foregroundStyle(FriendlyStyle.secondary)
                    }
                }
                Spacer(minLength: 10)
                if store.isRefreshing {
                    ProgressView().accessibilityLabel("Checking for squad updates")
                        .frame(minWidth: 44, minHeight: 44)
                } else {
                    Button {
                        Task { await store.refresh(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered).accessibilityLabel("Refresh squads")
                    .accessibilityIdentifier("friendly.refresh")
                }
            }
            if !store.statusMessage.isEmpty {
                Text(store.statusMessage).font(.caption).foregroundStyle(FriendlyStyle.secondary)
                    .accessibilityIdentifier("friendly.catalogue-status")
            }
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private var kickoffBar: some View {
        VStack(spacing: 0) {
            Button {
                if let configuration { presentedMatch = PresentedFriendly(configuration: configuration) }
            } label: {
                HStack(spacing: 10) {
                    Text("Kick off").font(.headline)
                    Image(systemName: "arrow.up.right").font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent).tint(FriendlyStyle.lime).foregroundStyle(FriendlyStyle.background)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .disabled(configuration == nil)
            .accessibilityIdentifier("friendly.kickoff")
            .frame(maxWidth: 700)
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity).background(FriendlyStyle.background.opacity(0.97))
    }

    private var configuration: FriendlyMatchConfiguration? {
        guard let home, let away, home.isValid, away.isValid, home.team.id != away.team.id else { return nil }
        return FriendlyMatchConfiguration(home: home, away: away)
    }

    private var formattedPublicationDate: String? {
        guard let raw = store.publishedAt else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        return date?.formatted(date: .abbreviated, time: .omitted)
    }

    private func lineup(for side: FriendlySide) -> ClubLineup? { side == .home ? home : away }

    private func setLineup(_ lineup: ClubLineup, for side: FriendlySide) {
        FriendlyTeamPreferences.save(lineup)
        if side == .home { home = lineup } else { away = lineup }
    }

    private func updateAvailableLineups() {
        guard presentedMatch == nil, !store.teams.isEmpty else { return }
        func updated(_ prior: ClubLineup?, excluding: String?) -> ClubLineup? {
            guard let team = store.teams.first(where: { $0.id == prior?.team.id && $0.id != excluding })
                ?? store.teams.first(where: { $0.id != excluding }) else { return nil }
            let formation = prior?.formation ?? .fourFourTwo
            if let prior, prior.team.id == team.id {
                let players = prior.players.compactMap { previous in team.players.first { $0.id == previous.id } }
                let candidate = ClubLineup(team: team, formation: formation, players: players,
                                           style: prior.style, automaticFormation: prior.automaticFormation)
                if candidate.isValid { return candidate }
            }
            return FriendlyTeamPreferences.load(team)
        }
        home = updated(home, excluding: nil)
        away = updated(away, excluding: home?.team.id)
    }
}

private enum FriendlySide: String, Identifiable {
    case home, away
    var id: String { rawValue }
    var title: String { self == .home ? "Home" : "Away" }
    var opponent: Self { self == .home ? .away : .home }
}

private struct PresentedFriendly: Identifiable {
    let id = UUID()
    let configuration: FriendlyMatchConfiguration
}

private struct PresentedPractice: Identifiable {
    let id = UUID()
    let mode: ExerciseMode
}

enum FriendlyStyle {
    static let background = Color(red: 0.025, green: 0.075, blue: 0.065)
    static let panel = Color(red: 0.055, green: 0.14, blue: 0.115)
    static let lime = Color(red: 0.86, green: 0.98, blue: 0.60)
    static let secondary = Color.white.opacity(0.68)
}

struct FriendlyKitPreview: View {
    let kit: ClubKit
    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Image(systemName: "tshirt.fill")
                    .resizable().scaledToFit().foregroundStyle(Color(hex: kit.shirtHex))
                Capsule().fill(Color(hex: kit.trimHex)).frame(width: 7, height: 23).offset(y: 6)
            }
            .frame(height: 48)
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 3).frame(width: 17, height: 18)
                RoundedRectangle(cornerRadius: 3).frame(width: 17, height: 18)
            }
            .foregroundStyle(Color(hex: kit.shortsHex))
        }
        .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
    }
}

private struct FriendlyClubPicker: View {
    let teams: [ClubTeam]
    let side: FriendlySide
    let selectedID: String?
    let unavailableID: String?
    let onSelect: (ClubTeam) -> Void
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filteredTeams, id: \.id) { team in
                        Button { onSelect(team) } label: {
                            HStack(spacing: 13) {
                                Image(systemName: "tshirt.fill")
                                    .foregroundStyle(Color(hex: team.primaryHex))
                                    .font(.title2).frame(width: 34)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(team.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                    if team.id == unavailableID {
                                        Text("Selected for the \(side.opponent.rawValue) side")
                                            .font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text("\(team.players.count) players").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 4)
                                if team.id == selectedID {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(FriendlyStyle.lime)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                        .disabled(team.id == unavailableID)
                        .accessibilityLabel(team.name)
                        .accessibilityValue(team.id == unavailableID ? "Already selected for \(side.opponent.rawValue)" : team.id == selectedID ? "Selected" : "")
                        .accessibilityIdentifier("friendly.club.\(team.id)")
                    }
                } header: {
                    Text("Premier League · \(teams.count) clubs")
                }
            }
            .searchable(text: $search, prompt: "Find a club")
            .overlay {
                if filteredTeams.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .navigationTitle(side == .home ? "Your club" : "Choose opponent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(FriendlyStyle.lime).preferredColorScheme(.dark)
    }

    private var filteredTeams: [ClubTeam] {
        teams.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
}

struct FriendlyLineupEditor: View {
    let lineup: ClubLineup
    let onSave: (ClubLineup) -> Void
    var body: some View {
        TeamManagementView(lineup: lineup, kit: MatchKits.resolve(configuration: .init(home: lineup, away: lineup)).home) { selection, _ in
            onSave(selection)
        }
    }
}

@MainActor
private enum FriendlyTeamPreferences {
    private static var defaults: UserDefaults {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let testID = ProcessInfo.processInfo.environment["FRIENDLY_TEST_STORE_ID"] ?? "default"
            return UserDefaults(suiteName: "friendly-tests.\(testID)") ?? .standard
        }
#endif
        return .standard
    }
    static func load(_ team: ClubTeam) -> ClubLineup {
        if let data = defaults.data(forKey: "friendly.selection.\(team.id)"),
           let saved = try? JSONDecoder().decode(SavedTeamSelection.self, from: data),
           let lineup = saved.restored(for: team) { return lineup }
        return .autoSelect(team: team)
    }
    static func save(_ lineup: ClubLineup) {
        if let data = try? JSONEncoder().encode(SavedTeamSelection(lineup)) {
            defaults.set(data, forKey: "friendly.selection.\(lineup.team.id)")
        }
    }
}

#Preview("Premier League friendly", traits: .portrait) {
    FriendlySetupView()
}
