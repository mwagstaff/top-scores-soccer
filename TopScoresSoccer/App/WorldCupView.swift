import SwiftUI

struct WorldCupView: View {
    @State private var store = WorldCupStore()
    @State private var presentedMatch: WorldCupMatchTicket?
    @State private var editingLineup = false
    @State private var creatingTournament = false
    @State private var pendingTeamID: String?
    @State private var confirmingReplacement = false
    @State private var errorMessage: String?
    @State private var celebration: WorldCupCelebrationPresentation?
    @State private var resultsExpanded = false

    var body: some View {
        NavigationStack {
            Group {
                if let save = store.save { dashboard(save) }
                else {
                    WorldCupCreationView(loadError: store.loadError, onStart: requestStart,
                                         onPreviewCelebration: previewCelebration)
                }
            }
            .navigationTitle("World Cup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FriendlyStyle.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if store.save != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("New World Cup", systemImage: "plus") { creatingTournament = true }
                        } label: { Label("World Cup options", systemImage: "ellipsis.circle") }
                        .accessibilityIdentifier("worldcup.options")
                    }
                }
            }
            .sheet(isPresented: $creatingTournament) {
                NavigationStack {
                    WorldCupCreationView(loadError: nil, onStart: requestStart,
                                         onPreviewCelebration: previewCelebration)
                        .navigationTitle("New World Cup").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { creatingTournament = false } } }
                }
                .tint(FriendlyStyle.lime).preferredColorScheme(.dark)
                .confirmationDialog("Replace your saved World Cup?", isPresented: $confirmingReplacement,
                                    titleVisibility: .visible) {
                    Button("Replace World Cup", role: .destructive) { startPendingTournament() }
                    Button("Cancel", role: .cancel) { pendingTeamID = nil }
                } message: {
                    Text("Your current World Cup results and bracket will be replaced. Your Career save is not affected.")
                }
            }
            .sheet(isPresented: $editingLineup) {
                if let save = store.save {
                    FriendlyLineupEditor(lineup: save.lineup) { lineup in
                        perform { try store.updateLineup(lineup); editingLineup = false }
                    }
                }
            }
            .fullScreenCover(item: $presentedMatch) { ticket in
                SandboxView(configuration: ticket.configuration,
                    worldCupContext: .init(fixtureTitle: ticket.fixture.stage == .group
                        ? "Group \(ticket.fixture.group ?? "") · Matchday \(ticket.fixture.matchday ?? 1)"
                        : ticket.fixture.stage.title,
                        userIsAway: ticket.userIsAway, isKnockout: ticket.fixture.stage.isKnockout,
                        shootoutSeed: ticket.seed),
                    onWorldCupComplete: { outcome in
                        _ = try store.completeFixture(ticketID: ticket.id, outcome: outcome)
                    }, onExit: {
                        presentedMatch = nil
                        presentSavedCelebrationIfNeeded()
                    })
            }
            .fullScreenCover(item: $celebration) { presentation in
                WorldCupCelebrationView(teamName: presentation.teamName) {
                    if presentation.isSavedVictory { perform { try store.acknowledgeCelebration() } }
                    celebration = nil
                }
            }
            .confirmationDialog("Replace your saved World Cup?", isPresented: replacementWithoutSheet,
                                titleVisibility: .visible) {
                Button("Replace World Cup", role: .destructive) { startPendingTournament() }
                Button("Cancel", role: .cancel) { pendingTeamID = nil }
            } message: { Text("The unreadable save will be replaced. Your Career save is not affected.") }
            .alert("Couldn’t save World Cup", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Please try again.") }
            .onAppear(perform: presentSavedCelebrationIfNeeded)
        }
        .tint(FriendlyStyle.lime).preferredColorScheme(.dark)
    }

    private func dashboard(_ save: WorldCupSave) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 9) {
                    Label("WORLD CUP 2026 · \(save.currentStage.title.uppercased())", systemImage: "globe.europe.africa.fill")
                        .font(.caption.bold()).tracking(1.2).foregroundStyle(FriendlyStyle.lime)
                    Text(save.selectedTeam.name).font(.largeTitle.bold()).foregroundStyle(.white)
                        .accessibilityIdentifier("worldcup.team-name")
                    Text(progressText(save)).font(.subheadline).foregroundStyle(FriendlyStyle.secondary)
                        .accessibilityIdentifier("worldcup.progress")
                }

                if let next = save.nextFixture {
                    nextFixture(next, save: save)
                    WorldCupResultsLozenge(save: save, nextFixture: next,
                                           isExpanded: $resultsExpanded)
                }
                else { completionCard(save) }

                Button { editingLineup = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "person.3.sequence.fill").foregroundStyle(FriendlyStyle.lime)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your starting XI").font(.headline).foregroundStyle(.white)
                            Text("\(save.lineup.formation.title) · Choose your players").font(.caption).foregroundStyle(FriendlyStyle.secondary)
                        }
                        Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(FriendlyStyle.secondary)
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(FriendlyStyle.panel, in: RoundedRectangle(cornerRadius: 18)).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("worldcup.lineup")

                if !save.groupStageComplete { selectedGroupCard(save) }

                VStack(spacing: 0) {
                    NavigationLink { WorldCupGroupsView(save: save) } label: {
                        CareerNavigationRow(title: "Group tables & results", subtitle: "Browse Groups A–L", symbol: "tablecells.fill")
                    }
                    .accessibilityIdentifier("worldcup.groups")
                    Rectangle().fill(.white.opacity(0.10)).frame(height: 1).padding(.horizontal, 18)
                    NavigationLink { WorldCupBracketView(save: save) } label: {
                        CareerNavigationRow(title: "Knockout bracket", subtitle: save.groupStageComplete ? "Round of 32 to the final" : "Available after the group stage", symbol: "trophy")
                    }
                    .disabled(!save.groupStageComplete).accessibilityIdentifier("worldcup.bracket")
                }
                .buttonStyle(.plain).background(FriendlyStyle.panel, in: RoundedRectangle(cornerRadius: 18))

                Label("Progress saved on this device", systemImage: "checkmark.circle")
                    .font(.caption.weight(.semibold)).foregroundStyle(FriendlyStyle.secondary)
                    .accessibilityIdentifier("worldcup.save-status")

            }
            .frame(maxWidth: 700).padding(20).frame(maxWidth: .infinity)
        }
        .background(FriendlyStyle.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
#if DEBUG
                WorldCupCelebrationPreviewButton(teamName: save.selectedTeam.name,
                                                  action: previewCelebration)
                    .padding(.horizontal, 20).padding(.top, 10)
#endif
                if save.nextFixture != nil {
                    CareerActionBar(title: "Play next match", symbol: "soccerball", identifier: "worldcup.play") {
                        perform { presentedMatch = try store.prepareMatch() }
                    }
                } else if !save.tournamentComplete {
                    CareerActionBar(title: "Finish tournament", symbol: "forward.end.fill", identifier: "worldcup.finish") {
                        perform { try store.finishTournament() }
                    }
                }
            }
            .frame(maxWidth: .infinity).background(FriendlyStyle.background.opacity(0.97))
        }
    }

    private func nextFixture(_ fixture: WorldCupFixture, save: WorldCupSave) -> some View {
        let home = save.teams.first { $0.id == fixture.homeTeamID }
        let away = save.teams.first { $0.id == fixture.awayTeamID }
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("NEXT MATCH").font(.caption.bold()).tracking(1.2).foregroundStyle(FriendlyStyle.lime)
                Spacer()
                Text(fixture.stage == .group ? "GROUP \(fixture.group ?? "") · MD\(fixture.matchday ?? 1)" : fixture.stage.title.uppercased())
                    .font(.caption2.bold()).foregroundStyle(FriendlyStyle.secondary)
            }
            teamRow(home, selectedID: save.selectedTeamID)
            HStack { Rectangle().fill(.white.opacity(0.12)).frame(height: 1); Text("VS").font(.caption.bold()); Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
                .foregroundStyle(FriendlyStyle.secondary)
            teamRow(away, selectedID: save.selectedTeamID)
            Text(fixture.stage.isKnockout
                 ? "Three-minute match · Extra time and penalties if level"
                 : "Three-minute match · Other matchday results are simulated at full time")
                .font(.caption).foregroundStyle(FriendlyStyle.secondary)
        }
        .padding(20).background(FriendlyStyle.panel, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityIdentifier("worldcup.next-fixture")
    }

    private func teamRow(_ team: ClubTeam?, selectedID: String) -> some View {
        HStack(spacing: 13) {
            WorldCupFlagView(teamID: team?.id, size: .large)
            VStack(alignment: .leading, spacing: 3) {
                Text(team?.id == selectedID ? "YOUR TEAM" : "OPPONENT").font(.caption2.bold()).tracking(1)
                    .foregroundStyle(team?.id == selectedID ? FriendlyStyle.lime : FriendlyStyle.secondary)
                Text(team?.name ?? "Team unavailable").font(.title3.bold()).foregroundStyle(.white)
            }
            Spacer(); Text(team?.scoreboardAbbreviation ?? "---").font(.caption.bold().monospaced()).foregroundStyle(FriendlyStyle.secondary)
        }
    }

    private func selectedGroupCard(_ save: WorldCupSave) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("GROUP \(save.selectedGroupName)").font(.caption.bold()).tracking(1.2).foregroundStyle(FriendlyStyle.lime)
            WorldCupStandingHeader()
            ForEach(Array(save.standings(forGroup: save.selectedGroupIndex).enumerated()), id: \.element.id) { index, standing in
                WorldCupStandingRow(position: index + 1, standing: standing,
                                    selectedID: save.selectedTeamID,
                                    accent: WorldCupGroupPalette.color(for: save.selectedGroupName))
                    .padding(.leading, 8)
            }
        }
        .padding(18).background(FriendlyStyle.panel, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("worldcup.selected-group")
    }

    private func completionCard(_ save: WorldCupSave) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: save.userIsChampion ? "trophy.fill" : "flag.checkered").font(.largeTitle).foregroundStyle(FriendlyStyle.lime)
            Text(save.userIsChampion ? "World champions!" : save.tournamentComplete ? "Tournament complete" : "Your World Cup is over")
                .font(.title2.bold()).foregroundStyle(.white)
            if let champion = save.championTeamID { Text("\(save.teamName(champion)) win the World Cup.").foregroundStyle(.white) }
            else { Text("Finish the tournament to discover the champions.").foregroundStyle(FriendlyStyle.secondary) }
            if save.userIsChampion {
                Button("Replay trophy celebration", systemImage: "sparkles") {
                    celebration = .init(teamName: save.selectedTeam.name, isSavedVictory: false)
                }
                .buttonStyle(.bordered).tint(FriendlyStyle.lime).accessibilityIdentifier("worldcup.replay-celebration")
            }
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(FriendlyStyle.panel, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityIdentifier("worldcup.complete")
    }

    private func progressText(_ save: WorldCupSave) -> String {
        if save.userIsChampion { return "Champions · All eight matches complete" }
        if save.selectedTeamEliminated { return save.tournamentComplete ? "Tournament complete" : "Eliminated · The tournament continues" }
        if save.currentStage == .group { return "Group \(save.selectedGroupName) · Matchday \(save.currentGroupMatchday) of 3" }
        return save.currentStage.title
    }

    private func requestStart(_ teamID: String) {
        pendingTeamID = teamID
        if store.save != nil || store.loadError != nil { confirmingReplacement = true }
        else { startPendingTournament() }
    }

    private func startPendingTournament() {
        guard let teamID = pendingTeamID else { return }
        do {
            if store.save != nil || store.loadError != nil { try store.deleteTournament() }
            try store.start(teamID: teamID)
            pendingTeamID = nil; creatingTournament = false
        } catch { errorMessage = error.localizedDescription }
    }

    private func presentSavedCelebrationIfNeeded() {
        guard celebration == nil, presentedMatch == nil, let save = store.save,
              save.celebrationPending, save.userIsChampion else { return }
        celebration = .init(teamName: save.selectedTeam.name, isSavedVictory: true)
    }

    private func previewCelebration(for teamName: String) {
#if DEBUG
        celebration = .init(teamName: teamName, isSavedVictory: false)
#endif
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    private var replacementWithoutSheet: Binding<Bool> {
        Binding(get: { confirmingReplacement && !creatingTournament }, set: { confirmingReplacement = $0 })
    }
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

private struct WorldCupCelebrationPresentation: Identifiable {
    let id = UUID()
    let teamName: String
    let isSavedVictory: Bool
}

private struct WorldCupCreationView: View {
    let loadError: String?
    let onStart: (String) -> Void
    let onPreviewCelebration: (String) -> Void
    private let snapshot = NationalTeamCatalogue.snapshot()
    @State private var selectedID = NationalTeamCatalogue.snapshot().teams.first?.id ?? ""
    @State private var search = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 9) {
                    Label("48 NATIONS · ONE TROPHY", systemImage: "globe.europe.africa.fill")
                        .font(.caption.bold()).tracking(1.4).foregroundStyle(FriendlyStyle.lime)
                    Text("Choose your nation.").font(.largeTitle.bold()).foregroundStyle(.white)
                    Text("Three group matches. The top two and eight best third-placed teams reach the Round of 32.")
                        .font(.subheadline).foregroundStyle(FriendlyStyle.secondary)
                    if let loadError { Text(loadError).font(.caption).foregroundStyle(.orange) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                    ForEach(filteredTeams) { team in
                        Button { selectedID = team.id } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    WorldCupFlagView(teamID: team.id, size: .large)
                                    Spacer()
                                    if selectedID == team.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(FriendlyStyle.lime) }
                                }
                                Text(team.name).font(.headline).foregroundStyle(.white).multilineTextAlignment(.leading)
                                Text("Group \(groupName(team.id)) · \(team.scoreboardAbbreviation)")
                                    .font(.caption).foregroundStyle(FriendlyStyle.secondary)
                            }
                            .padding(15).frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                            .background(selectedID == team.id ? FriendlyStyle.panel.opacity(1.4) : FriendlyStyle.panel,
                                        in: RoundedRectangle(cornerRadius: 17))
                            .overlay(RoundedRectangle(cornerRadius: 17).stroke(selectedID == team.id ? FriendlyStyle.lime : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("worldcup.team.\(team.id)")
                    }
                }
            }
            .frame(maxWidth: 700).padding(20).frame(maxWidth: .infinity)
        }
        .background(FriendlyStyle.background)
        .searchable(text: $search, prompt: "Find a national team")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
#if DEBUG
                WorldCupCelebrationPreviewButton(teamName: selectedTeamName,
                                                  action: onPreviewCelebration)
                    .padding(.horizontal, 20).padding(.top, 10)
#endif
                CareerActionBar(title: "Start World Cup", symbol: "trophy", identifier: "worldcup.start",
                                disabled: selectedID.isEmpty) { onStart(selectedID) }
            }
            .frame(maxWidth: .infinity).background(FriendlyStyle.background.opacity(0.97))
        }
    }

    private var filteredTeams: [ClubTeam] {
        snapshot.teams.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    private var selectedTeamName: String {
        snapshot.teams.first { $0.id == selectedID }?.name ?? "Your team"
    }
    private func groupName(_ id: String) -> String {
        guard let index = snapshot.groups.firstIndex(where: { $0.contains(id) }) else { return "–" }
        return String(UnicodeScalar(65 + index)!)
    }
}

private struct WorldCupResultsLozenge: View {
    let save: WorldCupSave
    let nextFixture: WorldCupFixture
    @Binding var isExpanded: Bool

    var body: some View {
        if !previewFixtures.isEmpty {
            VStack(alignment: .leading, spacing: isExpanded ? 14 : 10) {
                Button { isExpanded.toggle() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sportscourt.fill")
                            .font(.caption.bold()).foregroundStyle(FriendlyStyle.lime)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(previewTitle).font(.caption.bold()).tracking(0.8).foregroundStyle(FriendlyStyle.lime)
                            Text(previewSubtitle).font(.caption2).foregroundStyle(FriendlyStyle.secondary)
                        }
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.bold()).foregroundStyle(FriendlyStyle.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("worldcup.results-toggle")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

                if isExpanded {
                    Divider().overlay(.white.opacity(0.12))
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(historySections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                WorldCupResultSectionDivider(title: section.title,
                                                             accent: section.accent,
                                                             dashed: section.group != nil)
                                ForEach(section.fixtures) { fixture in
                                    WorldCupScoreGridRow(fixture: fixture, save: save,
                                                        accent: section.accent)
                                }
                            }
                        }
                        NavigationLink { WorldCupGroupsView(save: save) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "tablecells.fill")
                                Text("View all group tables").fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.bold())
                            }
                            .foregroundStyle(FriendlyStyle.lime)
                            .padding(.top, 2).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("worldcup.results-tables")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("worldcup.results-history")
                } else {
                    if nextFixture.stage == .group, let fixture = previewFixtures.first {
                        WorldCupScoreGridRow(fixture: fixture, save: save,
                                            accent: WorldCupGroupPalette.color(for: fixture.group))
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 9) {
                                ForEach(previewFixtures) { fixture in
                                    WorldCupCompactResult(fixture: fixture, save: save)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(FriendlyStyle.panel, in: RoundedRectangle(cornerRadius: isExpanded ? 20 : 24))
            .overlay {
                RoundedRectangle(cornerRadius: isExpanded ? 20 : 24)
                    .stroke(FriendlyStyle.lime.opacity(0.16), lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("worldcup.results-lozenge")
        }
    }

    private var completedFixtures: [WorldCupFixture] {
        save.fixtures.filter { $0.result != nil }.sorted { $0.matchNumber > $1.matchNumber }
    }

    private var latestCompletedKnockoutStage: WorldCupStage? {
        completedFixtures.filter { $0.stage.isKnockout }.map(\.stage).max { $0.order < $1.order }
    }

    private var selectedGroupCompanions: [WorldCupFixture] {
        completedFixtures.filter {
            $0.stage == .group && $0.group == save.selectedGroupName
                && $0.homeTeamID != save.selectedTeamID && $0.awayTeamID != save.selectedTeamID
        }
    }

    private var knockoutRoundCompanions: [WorldCupFixture] {
        guard let stage = latestCompletedKnockoutStage else { return [] }
        return completedFixtures.filter {
            $0.stage == stage && $0.homeTeamID != save.selectedTeamID && $0.awayTeamID != save.selectedTeamID
        }
    }

    private var previewFixtures: [WorldCupFixture] {
        if nextFixture.stage.isKnockout, !knockoutRoundCompanions.isEmpty { return knockoutRoundCompanions }
        return Array(selectedGroupCompanions.prefix(1))
    }

    private var previewTitle: String {
        if nextFixture.stage.isKnockout, let stage = latestCompletedKnockoutStage,
           !knockoutRoundCompanions.isEmpty { return "LATEST RESULTS · \(stage.title.uppercased())" }
        return "LATEST RESULT · GROUP \(save.selectedGroupName)"
    }

    private var previewSubtitle: String {
        if nextFixture.stage.isKnockout, knockoutRoundCompanions.count > 1 {
            return "\(knockoutRoundCompanions.count) other ties · Swipe for every score"
        }
        return "Tap to see every previous result"
    }

    private var historySections: [WorldCupResultSection] {
        var sections: [WorldCupResultSection] = []
        let knockoutStages = Set(completedFixtures.filter { $0.stage.isKnockout }.map(\.stage))
            .sorted { $0.order > $1.order }
        for stage in knockoutStages {
            sections.append(.init(title: stage.title,
                                  fixtures: completedFixtures.filter { $0.stage == stage }, group: nil))
        }
        let completedGroups = Set(completedFixtures.compactMap { $0.stage == .group ? $0.group : nil })
        let orderedGroups = [save.selectedGroupName]
            + completedGroups.filter { $0 != save.selectedGroupName }.sorted()
        for group in orderedGroups where completedGroups.contains(group) {
            sections.append(.init(title: "Group \(group)",
                                  fixtures: completedFixtures.filter { $0.stage == .group && $0.group == group },
                                  group: group))
        }
        return sections
    }
}

private struct WorldCupResultSection: Identifiable {
    let title: String
    let fixtures: [WorldCupFixture]
    let group: String?
    var id: String { title }
    var accent: Color { WorldCupGroupPalette.color(for: group) }
}

private struct WorldCupCompactResult: View {
    let fixture: WorldCupFixture
    let save: WorldCupSave

    var body: some View {
        WorldCupScoreGridRow(fixture: fixture, save: save, accent: FriendlyStyle.lime)
            .frame(width: 320)
    }
}

private struct WorldCupScoreGridRow: View {
    let fixture: WorldCupFixture
    let save: WorldCupSave
    let accent: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize { accessibilityLayout }
            else { scoreGrid }
        }
        .font(.subheadline).foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.leading, 12).padding(.trailing, 9).padding(.vertical, 9)
        .background(accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) {
            Capsule().fill(accent).frame(width: 4).padding(.vertical, 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(resultAccessibilityLabel)
    }

    private var scoreGrid: some View {
        HStack(spacing: 8) {
            WorldCupFlagView(teamID: fixture.homeTeamID, size: .small)
            Text(save.teamName(fixture.homeTeamID))
                .lineLimit(2).multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
            resultText.frame(width: 72)
            Text(save.teamName(fixture.awayTeamID))
                .lineLimit(2).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            WorldCupFlagView(teamID: fixture.awayTeamID, size: .small)
        }
    }

    private var accessibilityLayout: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Text(save.teamName(fixture.homeTeamID)).multilineTextAlignment(.trailing)
                WorldCupFlagView(teamID: fixture.homeTeamID, size: .small)
            }
            resultText
            HStack(spacing: 8) {
                WorldCupFlagView(teamID: fixture.awayTeamID, size: .small)
                Text(save.teamName(fixture.awayTeamID)).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
        }
    }

    private var resultText: some View {
        VStack(spacing: 2) {
            if let result = fixture.result {
                Text("\(result.homeGoals)–\(result.awayGoals)").font(.headline.bold().monospacedDigit())
                if let home = result.homePenalties, let away = result.awayPenalties {
                    Text("\(home)–\(away) PENS").font(.caption2.bold()).foregroundStyle(accent)
                } else if result.wentToExtraTime {
                    Text("AET").font(.caption2.bold()).foregroundStyle(accent)
                } else if fixture.stage == .group {
                    Text("MD\(fixture.matchday ?? 1)").font(.caption2.bold()).foregroundStyle(FriendlyStyle.secondary)
                } else {
                    Text("M\(fixture.matchNumber)").font(.caption2.bold()).foregroundStyle(FriendlyStyle.secondary)
                }
            } else {
                Text("VS").font(.caption.bold()).foregroundStyle(FriendlyStyle.secondary)
                Text(fixture.stage == .group ? "MD\(fixture.matchday ?? 1)" : "M\(fixture.matchNumber)")
                    .font(.caption2.bold()).foregroundStyle(FriendlyStyle.secondary)
            }
        }
        .fixedSize()
    }

    private var resultAccessibilityLabel: String {
        guard let result = fixture.result else {
            return "\(save.teamName(fixture.homeTeamID)) versus \(save.teamName(fixture.awayTeamID)), not yet played"
        }
        var label = "\(save.teamName(fixture.homeTeamID)) \(result.homeGoals), \(save.teamName(fixture.awayTeamID)) \(result.awayGoals)"
        if let home = result.homePenalties, let away = result.awayPenalties { label += ", \(home) to \(away) on penalties" }
        else if result.wentToExtraTime { label += ", after extra time" }
        if fixture.stage == .group { label += ", Group \(fixture.group ?? ""), matchday \(fixture.matchday ?? 1)" }
        return label
    }
}

private struct WorldCupResultSectionDivider: View {
    let title: String
    let accent: Color
    let dashed: Bool

    var body: some View {
        HStack(spacing: 9) {
            line
            Text(title.uppercased()).font(.caption2.bold()).tracking(1).fixedSize()
            line
        }
        .foregroundStyle(accent)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var line: some View {
        if dashed {
            WorldCupDashedLine().stroke(style: StrokeStyle(lineWidth: 1.25, dash: [6, 5]))
                .frame(height: 1)
        } else {
            Rectangle().frame(height: 1).opacity(0.55)
        }
    }
}

private struct WorldCupDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private enum WorldCupGroupPalette {
    private static let colours = [
        "#42A5F5", "#FF9F43", "#B388FF", "#2ED3C6",
        "#FF74AC", "#F3C969", "#62D67A", "#FF6B6B",
        "#7D8CFF", "#45D3F4", "#F4AE45", "#C7ED6B",
    ]

    static func color(for group: String?) -> Color {
        guard let group, let scalar = group.uppercased().unicodeScalars.first else { return FriendlyStyle.lime }
        let index = Int(scalar.value) - 65
        guard colours.indices.contains(index) else { return FriendlyStyle.lime }
        return Color(hex: colours[index])
    }
}

private struct WorldCupFlagView: View {
    enum Size: Equatable { case small, large }
    let teamID: String?
    let size: Size

    var body: some View {
        Text(teamID.map(NationalTeamCatalogue.flag(for:)) ?? "🌐")
            .font(.system(size: size == .large ? 28 : 19))
            .frame(width: size == .large ? 40 : 27, height: size == .large ? 31 : 22)
            .accessibilityHidden(true)
    }
}

#if DEBUG
private struct WorldCupCelebrationPreviewButton: View {
    let teamName: String
    let action: (String) -> Void

    var body: some View {
        Button { action(teamName) } label: {
            HStack(spacing: 11) {
                Image(systemName: "sparkles")
                    .font(.headline.bold())
                    .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.28))
                Text("DEBUG")
                    .font(.caption2.bold()).tracking(0.7)
                    .foregroundStyle(FriendlyStyle.background)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Color(red: 1, green: 0.84, blue: 0.28), in: Capsule())
                Text("View trophy celebration")
                    .font(.subheadline.bold()).foregroundStyle(.white)
                Spacer()
                Image(systemName: "play.fill")
                    .font(.caption.bold()).foregroundStyle(FriendlyStyle.lime)
            }
            .padding(.horizontal, 15).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FriendlyStyle.panel, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color(red: 1, green: 0.84, blue: 0.28).opacity(0.45), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("worldcup.preview-celebration")
        .accessibilityHint("Opens the celebration without changing World Cup progress")
    }
}
#endif

private struct WorldCupStandingHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack {
                    Text("TEAM")
                    Spacer()
                    Text("P · GD · PTS")
                }
            } else {
                HStack(spacing: 8) {
                    Text("#").frame(width: 20)
                    Color.clear.frame(width: 27, height: 1)
                    Text("TEAM")
                    Spacer()
                    Text("P").frame(width: 24)
                    Text("GD").frame(width: 32)
                    Text("PTS").frame(width: 34)
                }
            }
        }
        .font(.caption2.bold().monospaced()).foregroundStyle(FriendlyStyle.secondary)
        .frame(maxWidth: .infinity)
    }
}

private struct WorldCupStandingRow: View {
    let position: Int
    let standing: WorldCupStanding
    let selectedID: String
    var accent: Color? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text("\(position)").frame(width: 20)
                        WorldCupFlagView(teamID: standing.teamID, size: .small)
                        Text(standing.teamName).fontWeight(standing.teamID == selectedID ? .bold : .regular)
                    }
                    HStack(spacing: 14) {
                        Text("P \(standing.played)")
                        Text("GD \(goalDifference)")
                        Text("PTS \(standing.points)").fontWeight(.bold)
                    }
                    .font(.caption).foregroundStyle(FriendlyStyle.secondary)
                    .padding(.leading, 55)
                }
            } else {
                HStack(spacing: 8) {
                    Text("\(position)").frame(width: 20)
                    WorldCupFlagView(teamID: standing.teamID, size: .small)
                    Text(standing.teamName).fontWeight(standing.teamID == selectedID ? .bold : .regular).lineLimit(2)
                    Spacer(); Text("\(standing.played)").frame(width: 24)
                    Text(goalDifference).frame(width: 32)
                    Text("\(standing.points)").fontWeight(.bold).frame(width: 34)
                }
            }
        }
        .font(.subheadline).foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if let accent { Capsule().fill(accent).frame(width: 3).padding(.vertical, 2).offset(x: -8) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(position), \(standing.teamName), played \(standing.played), goal difference \(standing.goalDifference), \(standing.points) points")
    }

    private var goalDifference: String {
        standing.goalDifference > 0 ? "+\(standing.goalDifference)" : "\(standing.goalDifference)"
    }
}

private struct WorldCupGroupsView: View {
    let save: WorldCupSave
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedGroupIndex: Int

    init(save: WorldCupSave) {
        self.save = save
        _selectedGroupIndex = State(initialValue: save.selectedGroupIndex)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("GROUP STAGE").font(.caption.bold()).tracking(1.2).foregroundStyle(groupColor)
                    Text("Tables").font(.largeTitle.bold()).foregroundStyle(.white)
                    Text("Choose a group to see its standings, fixtures and completed results.")
                        .font(.subheadline).foregroundStyle(FriendlyStyle.secondary)
                }

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(save.groups.indices, id: \.self) { index in
                                let name = groupName(index)
                                let colour = WorldCupGroupPalette.color(for: name)
                                Button { selectedGroupIndex = index } label: {
                                    VStack(spacing: 3) {
                                        if !dynamicTypeSize.isAccessibilitySize {
                                            Text("GROUP").font(.caption2.bold()).tracking(0.7)
                                        }
                                        Text(name).font(.title3.bold())
                                    }
                                    .foregroundStyle(selectedGroupIndex == index ? .white : FriendlyStyle.secondary)
                                    .frame(width: 62, height: 54)
                                    .background(colour.opacity(selectedGroupIndex == index ? 0.18 : 0.045),
                                                in: RoundedRectangle(cornerRadius: 15))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 15)
                                            .stroke(selectedGroupIndex == index ? colour : .white.opacity(0.08), lineWidth: 1.5)
                                    }
                                    .overlay(alignment: .bottom) {
                                        if selectedGroupIndex == index {
                                            Capsule().fill(colour).frame(width: 28, height: 3).offset(y: 6)
                                        }
                                    }
                                }
                                .buttonStyle(.plain).id(index)
                                .accessibilityIdentifier("worldcup.group-picker.\(name)")
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .accessibilityIdentifier("worldcup.group-picker")
                    .onAppear { proxy.scrollTo(selectedGroupIndex, anchor: .center) }
                    .onChange(of: selectedGroupIndex) { _, newValue in proxy.scrollTo(newValue, anchor: .center) }
                }

                    standingsCard
                    fixturesCard
                }
                .frame(width: min(max(geometry.size.width - 40, 0), 700), alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .background(FriendlyStyle.background)
        .navigationTitle("Group tables").navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("worldcup.group-tables")
    }

    private var standingsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("GROUP \(selectedGroupName)").font(.headline.bold()).foregroundStyle(.white)
                Spacer()
                Circle().fill(groupColor).frame(width: 9, height: 9)
            }
            .padding(.bottom, 17)
            WorldCupStandingHeader().padding(.bottom, 10)
            Divider().overlay(.white.opacity(0.10))
            ForEach(Array(save.standings(forGroup: selectedGroupIndex).enumerated()), id: \.element.id) { index, row in
                WorldCupStandingRow(position: index + 1, standing: row,
                                    selectedID: save.selectedTeamID, accent: groupColor)
                    .padding(.horizontal, 8).padding(.vertical, 12)
                if index == 1 {
                    WorldCupQualificationDivider(title: "AUTOMATIC ROUND OF 32", colour: groupColor)
                } else if index == 2 {
                    WorldCupQualificationDivider(title: "BEST THIRD-PLACE RACE", colour: .orange)
                } else if index < 3 {
                    Divider().overlay(.white.opacity(0.08))
                }
            }
        }
        .padding(18)
        .background(FriendlyStyle.panel, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("worldcup.group-table.\(selectedGroupName)")
    }

    private var fixturesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorldCupResultSectionDivider(title: "Group \(selectedGroupName) fixtures & results",
                                         accent: groupColor, dashed: true)
            ForEach(selectedFixtures) { fixture in
                WorldCupScoreGridRow(fixture: fixture, save: save, accent: groupColor)
            }
        }
        .padding(16)
        .background(FriendlyStyle.panel, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("worldcup.group-results.\(selectedGroupName)")
    }

    private var selectedFixtures: [WorldCupFixture] {
        save.fixtures.filter { $0.stage == .group && $0.group == selectedGroupName }
            .sorted { lhs, rhs in
                if lhs.matchday != rhs.matchday { return (lhs.matchday ?? 0) < (rhs.matchday ?? 0) }
                return lhs.matchNumber < rhs.matchNumber
            }
    }

    private var selectedGroupName: String { groupName(selectedGroupIndex) }
    private var groupColor: Color { WorldCupGroupPalette.color(for: selectedGroupName) }
    private func groupName(_ index: Int) -> String {
        guard let scalar = UnicodeScalar(65 + index) else { return "–" }
        return String(scalar)
    }
}

private struct WorldCupQualificationDivider: View {
    let title: String
    let colour: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 5) {
                    Text(title).font(.caption2.bold()).multilineTextAlignment(.center)
                    WorldCupDashedLine()
                        .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                        .frame(height: 1)
                }
            } else {
                HStack(spacing: 8) {
                    WorldCupDashedLine().stroke(style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])).frame(height: 1)
                    Text(title).font(.caption2.bold()).fixedSize()
                    WorldCupDashedLine().stroke(style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])).frame(height: 1)
                }
            }
        }
        .foregroundStyle(colour)
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

private struct WorldCupBracketView: View {
    let save: WorldCupSave
    var body: some View {
        List {
            ForEach(WorldCupStage.allCases.filter { $0.isKnockout }, id: \.self) { stage in
                let games = save.fixtures.filter { $0.stage == stage }
                if !games.isEmpty {
                    Section(stage.title) { ForEach(games) { WorldCupFixtureRow(fixture: $0, save: save) } }
                }
            }
        }
        .navigationTitle("Knockout bracket").navigationBarTitleDisplayMode(.inline)
    }
}

private struct WorldCupFixtureRow: View {
    let fixture: WorldCupFixture
    let save: WorldCupSave
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MATCH \(fixture.matchNumber)")
                .font(.caption2.bold()).foregroundStyle(.secondary).padding(.leading, 12)
            WorldCupScoreGridRow(fixture: fixture, save: save, accent: FriendlyStyle.lime)
        }
        .padding(.vertical, 4)
    }
}

#Preview("World Cup") { WorldCupView() }
