import SwiftUI

/// A career owns its original clubs and players. The live catalogue is used only
/// when the player chooses to start a new career.
struct CareerView: View {
    @State private var catalogue = PremierLeagueStore()
    @State private var career = CareerStore()
    @State private var editingLineup = false
    @State private var creatingCareer = false
    @State private var pendingClubID: String?
    @State private var confirmingReplacement = false
    @State private var errorMessage: String?
    @State private var presentedMatch: CareerMatchTicket?

    var body: some View {
        NavigationStack {
            Group {
                if let save = career.save {
                    dashboard(save)
                } else {
                    CareerCreationView(catalogue: catalogue, loadError: career.loadError, onStart: requestStart)
                }
            }
            .navigationTitle("Career")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FriendlyStyle.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if career.save != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New career", systemImage: "plus") { creatingCareer = true }
                            .accessibilityIdentifier("career.new")
                    }
                }
            }
            .sheet(isPresented: $creatingCareer) {
                NavigationStack {
                    CareerCreationView(catalogue: catalogue, loadError: nil, onStart: requestStart)
                        .navigationTitle("New career")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { creatingCareer = false }
                            }
                        }
                }
                .tint(FriendlyStyle.lime).preferredColorScheme(.dark)
                .confirmationDialog("Replace your saved career?", isPresented: $confirmingReplacement,
                                    titleVisibility: .visible) {
                    Button("Replace career", role: .destructive) { startPendingCareer() }
                    Button("Cancel", role: .cancel) { pendingClubID = nil }
                } message: {
                    Text("Your current career and its season history will be replaced. Your new career will use the currently available squads.")
                }
                .alert("Couldn’t save career", isPresented: errorIsPresented) {
                    Button("OK", role: .cancel) { errorMessage = nil }
                } message: { Text(errorMessage ?? "Please try again.") }
            }
            .sheet(isPresented: $editingLineup) {
                if let save = career.save {
                    FriendlyLineupEditor(lineup: save.lineup) { lineup in
                        do {
                            try career.updateLineup(lineup)
                            editingLineup = false
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .alert("Couldn’t save lineup", isPresented: errorIsPresented) {
                        Button("OK", role: .cancel) { errorMessage = nil }
                    } message: { Text(errorMessage ?? "Please try again.") }
                }
            }
            .fullScreenCover(item: $presentedMatch) { ticket in
                PreMatchGate(configuration: ticket.configuration, userIsAway: ticket.userIsAway,
                             onExit: { presentedMatch = nil }, onSave: { try career.updateLineup($0) }) { prepared, playing in
                SandboxView(configuration: prepared,
                            careerContext: CareerMatchContext(fixtureTitle: "Matchweek \(ticket.fixture.round) · \(ticket.userIsAway ? "Away" : "Home")",
                                                             userIsAway: ticket.userIsAway),
                            onCareerComplete: { userGoals, opponentGoals in
                    _ = try career.completeFixture(ticketID: ticket.id, userGoals: userGoals, opponentGoals: opponentGoals)
                }, onExit: { presentedMatch = nil })
                }
            }
            .confirmationDialog("Replace your saved career?", isPresented: replacementWithoutSheet,
                                titleVisibility: .visible) {
                Button("Replace career", role: .destructive) { startPendingCareer() }
                Button("Cancel", role: .cancel) { pendingClubID = nil }
            } message: {
                Text("The saved career could not be opened. Starting again will replace that save.")
            }
            .alert("Couldn’t save career", isPresented: errorWithoutSheet) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Please try again.") }
            .task { await catalogue.refresh() }
        }
        .tint(FriendlyStyle.lime)
        .preferredColorScheme(.dark)
    }

    private func dashboard(_ save: CareerSave) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                identity(save)
                if save.isSeasonComplete {
                    seasonReview(save)
                } else if let fixture = save.nextFixture {
                    nextFixture(fixture, save: save)
                }
                lineupCard(save)
                seasonLinks(save)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Progress saved on this device", systemImage: "checkmark.circle")
                        .font(.caption.weight(.semibold))
                        .accessibilityIdentifier("career.saveStatus")
                    Text("Squads and ratings stay as they were when this career began. New seasons use these same clubs and players.")
                        .font(.caption)
                    Text("Started \(save.startedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                }
                .foregroundStyle(FriendlyStyle.secondary)
            }
            .frame(maxWidth: 700)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(FriendlyStyle.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CareerActionBar(title: save.isSeasonComplete ? "Start season \(save.seasonNumber + 1)" : "Play next match",
                            symbol: save.isSeasonComplete ? "arrow.right" : "soccerball",
                            identifier: save.isSeasonComplete ? "career.nextSeason" : "career.play") {
                if save.isSeasonComplete {
                    perform { try career.startNextSeason() }
                } else {
                    perform { presentedMatch = try career.prepareMatch() }
                }
            }
        }
    }

    private func identity(_ save: CareerSave) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("PREMIER LEAGUE · SEASON \(save.seasonNumber)", systemImage: "trophy")
                .font(.caption.bold()).tracking(1.2).foregroundStyle(FriendlyStyle.lime)
                .accessibilityIdentifier("career.season")
                .accessibilityValue("season:\(save.seasonNumber);")
            Text(save.selectedClub.name)
                .font(.largeTitle.bold()).foregroundStyle(.white)
                .accessibilityIdentifier("career.clubName")
            Text(save.isSeasonComplete ? "Season complete · 38 of 38 games played" : "Matchweek \(save.currentRound) of 38")
                .font(.subheadline).foregroundStyle(FriendlyStyle.secondary)
                .accessibilityIdentifier("career.progress")
                .accessibilityValue("round:\(save.currentRound);")
            if let index = save.standings.firstIndex(where: { $0.clubID == save.selectedClubID }) {
                let row = save.standings[index]
                Text(row.played == 0 ? "A fresh season. Make your mark." : "Position \(index + 1) · \(row.points) \(row.points == 1 ? "point" : "points") from \(row.played) \(row.played == 1 ? "game" : "games")")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.white)
                    .accessibilityIdentifier("career.record")
            }
        }
    }

    private func nextFixture(_ fixture: CareerFixture, save: CareerSave) -> some View {
        let kits = fixtureKits(fixture, save: save)
        return VStack(alignment: .leading, spacing: 17) {
            Text("NEXT MATCH")
                .font(.caption.bold()).tracking(1.2).foregroundStyle(FriendlyStyle.lime)
            VStack(spacing: 13) {
                fixtureClub(fixture.homeClubID, venue: "HOME", kit: kits?.home, clash: false, save: save)
                HStack(spacing: 12) {
                    Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                    Text("VS").font(.caption.bold()).foregroundStyle(FriendlyStyle.secondary)
                    Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                }
                .accessibilityHidden(true)
                fixtureClub(fixture.awayClubID, venue: "AWAY", kit: kits?.away, clash: kits?.awayIsClash == true, save: save)
            }
            Text("Three-minute match · Other results are simulated at full time")
                .font(.caption).foregroundStyle(FriendlyStyle.secondary)
        }
        .padding(20)
        .background(FriendlyStyle.panel, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityIdentifier("career.nextFixture")
    }

    private func fixtureKits(_ fixture: CareerFixture, save: CareerSave) -> MatchKits? {
        guard let home = save.teams.first(where: { $0.id == fixture.homeClubID }),
              let away = save.teams.first(where: { $0.id == fixture.awayClubID }) else { return nil }
        let homeLineup = home.id == save.selectedClubID ? save.lineup : .autoSelect(team: home)
        let awayLineup = away.id == save.selectedClubID ? save.lineup : .autoSelect(team: away)
        return MatchKits.resolve(configuration: .init(home: homeLineup, away: awayLineup))
    }

    private func fixtureClub(_ id: String, venue: String, kit: ClubKit?, clash: Bool, save: CareerSave) -> some View {
        let club = save.teams.first { $0.id == id }
        return HStack(spacing: 13) {
            if let kit {
                FriendlyKitPreview(kit: kit).frame(width: 48, height: 70).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(venue + (id == save.selectedClubID ? " · YOUR CLUB" : ""))
                    .font(.caption2.bold()).tracking(1)
                    .foregroundStyle(id == save.selectedClubID ? FriendlyStyle.lime : FriendlyStyle.secondary)
                Text(club?.name ?? "Club unavailable").font(.title3.bold()).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if clash { Text("Clash kit").font(.caption).foregroundStyle(FriendlyStyle.secondary) }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func lineupCard(_ save: CareerSave) -> some View {
        Button { editingLineup = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.3.sequence.fill").foregroundStyle(FriendlyStyle.lime)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your starting XI").font(.headline).foregroundStyle(.white)
                    Text("\(save.lineup.formation.title) · Choose your players")
                        .font(.caption).foregroundStyle(FriendlyStyle.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(FriendlyStyle.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(FriendlyStyle.panel, in: RoundedRectangle(cornerRadius: 18))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your starting XI, \(save.lineup.formation.title)")
        .accessibilityIdentifier("career.lineup")
    }

    private func seasonLinks(_ save: CareerSave) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                CareerTableView(save: save)
            } label: {
                CareerNavigationRow(title: "League table", subtitle: "20 clubs · Three points for a win", symbol: "list.number")
            }
            .accessibilityIdentifier("career.table")
            Rectangle().fill(.white.opacity(0.10)).frame(height: 1).padding(.horizontal, 18)
            NavigationLink {
                CareerFixturesView(save: save)
            } label: {
                CareerNavigationRow(title: "Fixtures & results", subtitle: "All 38 matchweeks", symbol: "calendar")
            }
            .accessibilityIdentifier("career.fixtures")
            if !save.archives.isEmpty {
                Rectangle().fill(.white.opacity(0.10)).frame(height: 1).padding(.horizontal, 18)
                NavigationLink {
                    CareerHistoryView(save: save)
                } label: {
                    CareerNavigationRow(title: "Season history", subtitle: "Your completed campaigns", symbol: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("career.history")
            }
        }
        .buttonStyle(.plain)
        .background(FriendlyStyle.panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func seasonReview(_ save: CareerSave) -> some View {
        let champion = save.standings.first
        let winner = champion?.clubID == save.selectedClubID
        return VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "trophy.fill").font(.largeTitle).foregroundStyle(FriendlyStyle.lime)
            Text(winner ? "Champions!" : "Season \(save.seasonNumber) complete")
                .font(.title2.bold()).foregroundStyle(.white)
            if let champion {
                Text("\(champion.clubName) win the league with \(champion.points) points.")
                    .font(.body).foregroundStyle(.white)
            }
            Text("Review the final table, then go again. Your season record is kept and your starting XI carries forward.")
                .font(.subheadline).foregroundStyle(FriendlyStyle.secondary)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(FriendlyStyle.panel, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityIdentifier("career.seasonComplete")
    }

    private func requestStart(_ clubID: String) {
        pendingClubID = clubID
        if career.save != nil || career.loadError != nil {
            confirmingReplacement = true
        } else {
            startPendingCareer()
        }
    }

    private func startPendingCareer() {
        guard let clubID = pendingClubID else { return }
        perform {
            try career.start(teams: catalogue.teams, clubID: clubID, snapshotID: catalogue.snapshotID)
            pendingClubID = nil
            creatingCareer = false
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var errorWithoutSheet: Binding<Bool> {
        Binding(get: { errorMessage != nil && !creatingCareer && !editingLineup && presentedMatch == nil },
                set: { if !$0 { errorMessage = nil } })
    }

    private var replacementWithoutSheet: Binding<Bool> {
        Binding(get: { confirmingReplacement && !creatingCareer },
                set: { if !$0 { confirmingReplacement = false } })
    }
}

private struct CareerCreationView: View {
    let catalogue: PremierLeagueStore
    let loadError: String?
    let onStart: (String) -> Void
    @State private var selectedClubID: String?
    @State private var choosingClub = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("PREMIER LEAGUE", systemImage: "trophy")
                        .font(.caption.bold()).tracking(1.8).foregroundStyle(FriendlyStyle.lime)
                    Text("Your club. Every match.")
                        .font(.largeTitle.bold()).foregroundStyle(.white)
                    Text("Choose your club and play a full 38-game season. Chase the title, then come back for another campaign.")
                        .font(.subheadline).foregroundStyle(FriendlyStyle.secondary)
                }
                if let loadError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Saved career unavailable", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text(loadError).font(.subheadline)
                        Text("You can start a new career below. You’ll be asked before replacing the saved career.")
                            .font(.caption)
                    }
                    .foregroundStyle(.white).padding(18)
                    .background(FriendlyStyle.panel, in: RoundedRectangle(cornerRadius: 18))
                }
                if let team = selectedClub {
                    Button { choosingClub = true } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "tshirt.fill")
                                .font(.system(size: 42)).foregroundStyle(Color(hex: team.primaryHex))
                                .frame(width: 58).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("YOUR CLUB").font(.caption2.bold()).tracking(1.2).foregroundStyle(FriendlyStyle.lime)
                                Text(team.name).font(.title3.bold()).foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Choose from 20 Premier League clubs")
                                    .font(.caption).foregroundStyle(FriendlyStyle.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.bold()).foregroundStyle(FriendlyStyle.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20).background(FriendlyStyle.panel, in: RoundedRectangle(cornerRadius: 22))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Your club, \(team.name)")
                    .accessibilityIdentifier("career.chooseClub")
                } else {
                    ContentUnavailableView("Clubs unavailable", systemImage: "soccerball",
                                           description: Text("Refresh the squads to start a career."))
                }
                VStack(alignment: .leading, spacing: 18) {
                    CareerFeatureRow(symbol: "soccerball", title: "You play every league game", detail: "Short 11-a-side matches, home and away. Other clubs’ results are simulated after your match.")
                    CareerFeatureRow(symbol: "checkmark.circle", title: "Pick up where you left off", detail: "Your lineup, results and table are saved on this device after each change.")
                    CareerFeatureRow(symbol: "person.3", title: "Your starting squads stay together", detail: "Squads and ratings are fixed when you start. Future seasons keep the same clubs and players.")
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(catalogue.seasonName + " squads").font(.footnote.bold()).foregroundStyle(.white)
                            Text(catalogue.sourceDescription).font(.caption).foregroundStyle(FriendlyStyle.secondary)
                        }
                        Spacer(minLength: 8)
                        if catalogue.isRefreshing {
                            ProgressView().frame(width: 44, height: 44).accessibilityLabel("Checking for squad updates")
                        } else {
                            Button {
                                Task { await catalogue.refresh(force: true) }
                            } label: {
                                Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                            }
                            .buttonStyle(.bordered).accessibilityLabel("Refresh squads")
                        }
                    }
                    if !catalogue.statusMessage.isEmpty {
                        Text(catalogue.statusMessage).font(.caption).foregroundStyle(FriendlyStyle.secondary)
                    }
                }
            }
            .frame(maxWidth: 700).padding(20).frame(maxWidth: .infinity)
        }
        .background(FriendlyStyle.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CareerActionBar(title: "Start career", symbol: "arrow.up.right", identifier: "career.start",
                            disabled: selectedClub == nil) {
                if let team = selectedClub { onStart(team.id) }
            }
        }
        .sheet(isPresented: $choosingClub) {
            CareerClubPicker(teams: catalogue.teams, selectedID: selectedClub?.id) { club in
                selectedClubID = club.id
                choosingClub = false
            }
        }
    }

    private var selectedClub: ClubTeam? {
        catalogue.teams.first { $0.id == selectedClubID } ?? catalogue.teams.first
    }
}

private struct CareerClubPicker: View {
    let teams: [ClubTeam]
    let selectedID: String?
    let onSelect: (ClubTeam) -> Void
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Premier League · \(teams.count) clubs") {
                    ForEach(filteredTeams, id: \.id) { team in
                        Button { onSelect(team) } label: {
                            HStack(spacing: 13) {
                                Image(systemName: "tshirt.fill")
                                    .font(.title2).foregroundStyle(Color(hex: team.primaryHex))
                                    .frame(width: 34).accessibilityHidden(true)
                                Text(team.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 4)
                                if team.id == selectedID {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(FriendlyStyle.lime)
                                }
                            }
                            .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(team.name)
                        .accessibilityValue(team.id == selectedID ? "Selected" : "")
                        .accessibilityIdentifier("career.club.\(team.id)")
                    }
                }
            }
            .searchable(text: $search, prompt: "Find your club")
            .overlay { if filteredTeams.isEmpty { ContentUnavailableView.search(text: search) } }
            .navigationTitle("Choose your club").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(FriendlyStyle.lime).preferredColorScheme(.dark)
    }

    private var filteredTeams: [ClubTeam] {
        teams.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
}

private struct CareerTableView: View {
    let save: CareerSave
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(Array(save.standings.enumerated()), id: \.element.id) { index, standing in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)").font(.body.monospacedDigit()).frame(minWidth: 25, alignment: .leading)
                                .foregroundStyle(standing.clubID == save.selectedClubID ? FriendlyStyle.lime : FriendlyStyle.secondary)
                            Text(standing.clubName).font(.body.weight(standing.clubID == save.selectedClubID ? .bold : .medium))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(standing.points)").font(.headline.monospacedDigit())
                                Text("PTS").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { record(standing) }
                            VStack(alignment: .leading, spacing: 4) { record(standing) }
                        }
                        .font(.caption).foregroundStyle(.secondary).padding(.leading, 37)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(standing.clubID == save.selectedClubID ? FriendlyStyle.panel : nil)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Position \(index + 1), \(standing.clubName)\(standing.clubID == save.selectedClubID ? ", your club" : ""), \(standing.points) points, played \(standing.played), won \(standing.won), drawn \(standing.drawn), lost \(standing.lost), goal difference \(standing.goalDifference)")
                    .accessibilityIdentifier("career.table.club.\(standing.clubID)")
                    .accessibilityValue("played:\(standing.played);points:\(standing.points);")
                }
            } header: {
                Text("Season \(save.seasonNumber) · \(save.isSeasonComplete ? "Final table" : "Matchweek \(save.currentRound)")")
            } footer: {
                Text("Ranked by points, goal difference, then goals scored. Clubs still level are ordered by name.")
            }
        }
        .navigationTitle("League table").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    @ViewBuilder private func record(_ standing: CareerStanding) -> some View {
        Text("P \(standing.played) · W \(standing.won) · D \(standing.drawn) · L \(standing.lost)")
        Text("GD \(standing.goalDifference > 0 ? "+" : "")\(standing.goalDifference)")
    }
}

private struct CareerFixturesView: View {
    let save: CareerSave
    @State private var onlyYourClub = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollViewReader { reader in
            List {
                Section {
                    Toggle("Your club only", isOn: $onlyYourClub)
                        .accessibilityIdentifier("career.fixtures.filter")
                }
                ForEach(1...38, id: \.self) { round in
                    Section("Matchweek \(round)") {
                        ForEach(fixtures(round: round)) { fixture in
                            fixtureRow(fixture)
                        }
                    }
                    .id("round-\(round)")
                }
            }
            .onAppear {
                if save.currentRound > 1 { reader.scrollTo("round-\(save.currentRound)", anchor: .top) }
            }
        }
        .navigationTitle("Fixtures & results").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    private func fixtures(round: Int) -> [CareerFixture] {
        save.fixtures.filter { fixture in
            fixture.round == round && (!onlyYourClub || fixture.homeClubID == save.selectedClubID || fixture.awayClubID == save.selectedClubID)
        }
    }

    private func fixtureRow(_ fixture: CareerFixture) -> some View {
        let home = save.teams.first { $0.id == fixture.homeClubID }?.name ?? "Unknown club"
        let away = save.teams.first { $0.id == fixture.awayClubID }?.name ?? "Unknown club"
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(home).fontWeight(fixture.homeClubID == save.selectedClubID ? .bold : .regular)
                Spacer(minLength: 8)
                Text(fixture.result.map { "\($0.homeGoals)" } ?? "–").monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline) {
                Text(away).fontWeight(fixture.awayClubID == save.selectedClubID ? .bold : .regular)
                Spacer(minLength: 8)
                Text(fixture.result.map { "\($0.awayGoals)" } ?? "–").monospacedDigit()
            }
            if fixture.id == save.nextFixture?.id {
                Text("NEXT MATCH").font(.caption2.bold()).tracking(0.8).foregroundStyle(FriendlyStyle.lime)
            }
        }
        .padding(.vertical, 7)
        .listRowBackground(fixture.homeClubID == save.selectedClubID || fixture.awayClubID == save.selectedClubID ? FriendlyStyle.panel : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Matchweek \(fixture.round), \(home) versus \(away), \(fixture.result.map { "\($0.homeGoals) to \($0.awayGoals)" } ?? "not played")")
        .accessibilityIdentifier("career.fixture.\(fixture.id)")
    }
}

private struct CareerHistoryView: View {
    let save: CareerSave
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(save.archives.reversed()) { archive in
                Section("Season \(archive.seasonNumber)") {
                    CareerHistorySummary(archive: archive, clubID: save.selectedClubID,
                                         clubName: save.selectedClub.name)
                    NavigationLink {
                        CareerTableView(save: snapshot(for: archive))
                    } label: {
                        Label("Final table", systemImage: "list.number")
                    }
                    .accessibilityIdentifier("career.history.table.\(archive.seasonNumber)")
                    NavigationLink {
                        CareerFixturesView(save: snapshot(for: archive))
                    } label: {
                        Label("Season results", systemImage: "calendar")
                    }
                    .accessibilityIdentifier("career.history.fixtures.\(archive.seasonNumber)")
                }
            }
        }
        .navigationTitle("Season history").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    /// Reconstructs a display-only season without touching the career store.
    private func snapshot(for archive: CareerSeasonArchive) -> CareerSave {
        var historical = save
        historical.seasonNumber = archive.seasonNumber
        historical.fixtures = archive.fixtures
        historical.archives = save.archives.filter { $0.seasonNumber < archive.seasonNumber }
        return historical
    }
}

private struct CareerHistorySummary: View {
    let archive: CareerSeasonArchive
    let clubID: String
    let clubName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let champion = archive.standings.first {
                Label(champion.clubName + " · Champions", systemImage: "trophy.fill")
                    .font(.headline).foregroundStyle(FriendlyStyle.lime)
            }
            if let finish = clubFinish {
                Text(verbatim: finish).font(.body.weight(.semibold))
            }
            if let record = clubRecord {
                Text(verbatim: record).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("career.history.season.\(archive.seasonNumber)")
    }

    private var clubFinish: String? {
        guard let index = archive.standings.firstIndex(where: { $0.clubID == clubID }) else { return nil }
        return clubName + " finished " + String(index + 1) + " of 20"
    }

    private var clubRecord: String? {
        guard let row = archive.standings.first(where: { $0.clubID == clubID }) else { return nil }
        let parts = ["\(row.points) points", "\(row.won) wins", "\(row.drawn) draws", "\(row.lost) losses"]
        return parts.joined(separator: " · ")
    }
}

struct CareerNavigationRow: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).foregroundStyle(FriendlyStyle.lime).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(FriendlyStyle.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(FriendlyStyle.secondary)
        }
        .padding(18).frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct CareerFeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol).font(.title3).foregroundStyle(FriendlyStyle.lime).frame(width: 30)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                Text(detail).font(.caption).foregroundStyle(FriendlyStyle.secondary)
            }
        }
    }
}

struct CareerActionBar: View {
    let title: String
    let symbol: String
    let identifier: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title).font(.headline)
                Image(systemName: symbol).font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.borderedProminent).tint(FriendlyStyle.lime).foregroundStyle(FriendlyStyle.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .disabled(disabled).accessibilityIdentifier(identifier)
        .frame(maxWidth: 700)
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
        .frame(maxWidth: .infinity).background(FriendlyStyle.background.opacity(0.97))
    }
}
