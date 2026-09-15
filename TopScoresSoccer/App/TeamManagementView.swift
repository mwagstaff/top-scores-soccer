import SwiftUI

struct PlayerStars: View {
    let player: ClubPlayer
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                Image(systemName: player.stars >= Double(index + 1) ? "star.fill"
                      : player.stars > Double(index) ? "star.leadinghalf.filled" : "star")
            }
        }
        .foregroundStyle(FriendlyStyle.lime)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(player.stars.formatted()) out of 5 stars\(player.isRatingEstimated ? ", estimated" : "")")
    }
}

struct PlayerPortrait: View {
    let player: ClubPlayer
    let kit: ClubKit
    var body: some View {
        Group {
            if let icon = PitchRenderer.playerIcon(player, kit: kit) {
                Image(uiImage: icon).resizable().scaledToFit()
            } else { Image(systemName: "person.fill").resizable().scaledToFit() }
        }
        .accessibilityHidden(true)
    }
}

struct TeamPlayerRow: View {
    let player: ClubPlayer
    let kit: ClubKit
    var assignedRole: String? = nil
    var status: String? = nil
    var body: some View {
        HStack(spacing: 14) {
            PlayerPortrait(player: player, kit: kit).frame(width: 38, height: 52)
            VStack(alignment: .leading, spacing: 5) {
                Text(player.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(details).font(.caption).foregroundStyle(.secondary)
                PlayerStars(player: player).font(.caption)
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
    private var details: String {
        var parts = [player.positionTitle]
        if let number = player.jerseyNumber { parts.append("No. \(number)") }
        if let role = assignedRole, role != player.role { parts.append("Playing \(role) · out of position") }
        if player.isRatingEstimated { parts.append("Estimated rating") }
        return parts.joined(separator: " · ")
    }
}

struct TeamManagementView: View {
    @State var lineup: ClubLineup
    let kit: ClubKit
    var title = "Team management"
    var actionTitle = "Done"
    var opponentName: String? = nil
    var actualLineup: ClubLineup? = nil
    var matchPlayers: [Footballer] = []
    var unavailableIDs: Set<String> = []
    var substitutionsUsed = 0
    @State var substitutions: [PendingSubstitution] = []
    var onCancel: (() -> Void)? = nil
    let onSave: (ClubLineup, [PendingSubstitution]) throws -> Void
    @State private var selectedPlayer: ClubPlayer?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    private var isLive: Bool { actualLineup != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(lineup.team.name).font(.largeTitle.bold())
                        if let opponentName { Text("vs \(opponentName)").foregroundStyle(.secondary) }
                        if isLive {
                            Text("\(max(0, 5 - substitutionsUsed - substitutions.count)) substitutions available · \(substitutions.count) pending")
                                .font(.subheadline).foregroundStyle(FriendlyStyle.lime)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Style of play").font(.headline)
                        Picker("Style of play", selection: $lineup.style) {
                            ForEach(PlayStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented).accessibilityIdentifier("team.style")
                        Text(lineup.style.description).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        let headingLayout = textSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                            : AnyLayout(HStackLayout())
                        headingLayout {
                            Text(isLive ? "On the pitch" : "Starting XI").font(.title2.bold())
                            if !textSize.isAccessibilitySize { Spacer() }
                            Text(lineup.formation.title).font(.title3.monospacedDigit().bold())
                                .foregroundStyle(FriendlyStyle.lime).accessibilityIdentifier("team.shape")
                        }
                        Toggle("Automatic formation", isOn: automaticBinding)
                            .accessibilityIdentifier("team.automatic")
                        if !lineup.automaticFormation {
                            Picker("Formation", selection: formationBinding) {
                                ForEach(MatchFormation.allCases) { Text($0.title).tag($0) }
                            }.accessibilityIdentifier("friendly.formation")
                        }
                        Text(lineup.automaticFormation ? "Your formation follows the players you choose." : "Choose a shape. Your selected players stay in the team.")
                            .font(.caption).foregroundStyle(.secondary)
                        if !textSize.isAccessibilitySize { pitch }
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(lineup.players.enumerated()), id: \.element.id) { index, player in
                            Button { selectedPlayer = player } label: {
                                TeamPlayerRow(player: player, kit: kit,
                                    assignedRole: lineup.formation.slots[index].role, status: status(for: player))
                            }
                            .buttonStyle(.plain)
                            .disabled(!canReplace(player))
                            .accessibilityIdentifier("friendly.lineup.slot.\(index)")
                            .padding(.vertical, 5)
                            if index < 10 { Divider() }
                        }
                    }
                    if isLive {
                        Text("Substitutions take effect at the next stoppage. Replaced players cannot return. Injury replacements count towards the five-player limit.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if !substitutions.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(substitutions) { change in
                                    Text("\(name(change.outgoingID)) → \(name(change.incomingID))")
                                        .font(.subheadline)
                                }
                                Button("Cancel pending substitutions", action: cancelSubstitutions)
                                    .accessibilityIdentifier("team.cancel-substitutions")
                            }
                        }
                    } else {
                        Text("Tap a player to choose a replacement. Stars compare player quality across every team; estimated ratings are labelled.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
            .background(FriendlyStyle.background)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if let onCancel { onCancel() } else { dismiss() } }
                        .accessibilityIdentifier("team.cancel")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    do { try onSave(lineup, substitutions) }
                    catch { errorMessage = error.localizedDescription }
                } label: {
                    Text(actionTitle).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent).tint(FriendlyStyle.lime).foregroundStyle(.black)
                .disabled(!lineup.isValid)
                .accessibilityIdentifier(actionTitle == "Kick off" ? "team.kickoff" : "friendly.lineup.done")
                .padding(.horizontal, 20).padding(.vertical, 10).background(FriendlyStyle.background)
            }
            .sheet(item: $selectedPlayer) { player in replacementPicker(for: player) }
            .alert("Couldn’t save team", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Please try again.") }
        }
        .tint(FriendlyStyle.lime).preferredColorScheme(.dark)
    }

    private var pitch: some View {
        let rows = Dictionary(grouping: Array(lineup.players.enumerated()), by: { lineup.formation.slots[$0.offset].position.y })
        return VStack(spacing: 18) {
            ForEach(rows.keys.sorted(by: >), id: \.self) { depth in
                HStack(alignment: .top, spacing: 2) {
                    ForEach(rows[depth] ?? [], id: \.element.id) { item in
                        let player = item.element
                        Button { selectedPlayer = player } label: {
                            VStack(spacing: 4) {
                                PlayerPortrait(player: player, kit: kit).frame(height: 40)
                                Text(player.displayName.components(separatedBy: " ").last ?? player.displayName)
                                    .font(.caption2.weight(.semibold)).lineLimit(1)
                                Text(player.positionTitle).font(.system(size: 9, weight: .bold))
                                PlayerStars(player: player).font(.system(size: 8))
                            }.frame(maxWidth: .infinity).foregroundStyle(.white)
                        }
                        .buttonStyle(.plain).disabled(!canReplace(player))
                        .opacity(status(for: player) == "Sent off" || status(for: player) == "Injured" ? 0.45 : 1)
                        .accessibilityLabel("\(player.name), \(player.positionTitle), \(player.stars.formatted()) stars")
                    }
                }
            }
        }
        .padding(.vertical, 24).padding(.horizontal, 8)
        .background {
            GeometryReader { geometry in
                ZStack {
                    Color(red: 0.08, green: 0.25, blue: 0.18)
                    Rectangle().stroke(.white.opacity(0.22), lineWidth: 1).padding(12)
                    Rectangle().fill(.white.opacity(0.20)).frame(height: 1)
                    Circle().stroke(.white.opacity(0.20), lineWidth: 1).frame(width: 65, height: 65)
                    VStack {
                        Rectangle().stroke(.white.opacity(0.20), lineWidth: 1).frame(width: geometry.size.width * 0.45, height: 35)
                        Spacer()
                        Rectangle().stroke(.white.opacity(0.20), lineWidth: 1).frame(width: geometry.size.width * 0.45, height: 35)
                    }.padding(.vertical, 12)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var automaticBinding: Binding<Bool> {
        Binding(get: { lineup.automaticFormation }, set: {
            lineup.automaticFormation = $0
            if $0 { lineup = lineup.balanced() }
        })
    }
    private var formationBinding: Binding<MatchFormation> {
        Binding(get: { lineup.formation }, set: { lineup = lineup.arranged(in: $0) })
    }
    private func name(_ id: String) -> String { lineup.team.players.first { $0.id == id }?.displayName ?? "Player" }
    private func status(for player: ClubPlayer) -> String? {
        if substitutions.contains(where: { $0.incomingID == player.id }) { return "Coming on at the next stoppage" }
        if let current = matchPlayers.first(where: { $0.clubPlayer?.id == player.id }) {
            if current.isSentOff { return "Sent off" }
            if current.isInjured { return "Injured" }
            if current.yellowCards > 0 { return "Yellow card" }
        }
        return nil
    }
    private func canReplace(_ player: ClubPlayer) -> Bool {
        guard isLive else { return true }
        if substitutions.contains(where: { $0.incomingID == player.id }) { return true }
        return substitutionsUsed + substitutions.count < 5
            && !matchPlayers.contains(where: { $0.clubPlayer?.id == player.id && $0.isUnavailable })
    }
    private func candidates(for player: ClubPlayer) -> [ClubPlayer] {
        lineup.team.players.filter { candidate in
            candidate.id != player.id && (candidate.role == "G") == (player.role == "G")
            && (!isLive || (!unavailableIDs.contains(candidate.id)
                && actualLineup?.players.contains(where: { $0.id == candidate.id }) != true
                && !lineup.players.contains(where: { $0.id == candidate.id })))
        }.sorted {
            if ($0.role == player.role) != ($1.role == player.role) { return $0.role == player.role }
            return $0.effectiveRating > $1.effectiveRating
        }
    }
    private func replacementPicker(for player: ClubPlayer) -> some View {
        NavigationStack {
            List {
                Section("Replace \(player.displayName)") {
                    ForEach(candidates(for: player)) { candidate in
                        Button {
                            guard let slot = lineup.players.firstIndex(where: { $0.id == player.id }),
                                  let updated = lineup.replacingPlayer(at: slot, with: candidate) else { return }
                            if isLive {
                                let outgoing = substitutions.first(where: { $0.incomingID == player.id })?.outgoingID ?? player.id
                                substitutions.removeAll { $0.outgoingID == outgoing }
                                substitutions.append(.init(outgoingID: outgoing, incomingID: candidate.id))
                            }
                            lineup = updated; selectedPlayer = nil
                        } label: {
                            TeamPlayerRow(player: candidate, kit: kit,
                                status: lineup.players.contains(where: { $0.id == candidate.id }) ? "In starting XI · swap positions" : nil)
                        }.buttonStyle(.plain).accessibilityIdentifier("friendly.replacement.\(candidate.id)")
                    }
                }
            }
            .overlay { if candidates(for: player).isEmpty { ContentUnavailableView("No available replacements", systemImage: "person.fill.checkmark") } }
            .navigationTitle("Choose a player").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { selectedPlayer = nil }.accessibilityIdentifier("team.replacement.cancel") } }
        }.tint(FriendlyStyle.lime).preferredColorScheme(.dark)
    }
    private func cancelSubstitutions() {
        guard var current = actualLineup else { return }
        current.style = lineup.style; current.automaticFormation = lineup.automaticFormation
        lineup = current.automaticFormation ? current.balanced() : current.arranged(in: lineup.formation)
        substitutions.removeAll()
    }
}

struct PreMatchGate<MatchContent: View>: View {
    let configuration: FriendlyMatchConfiguration
    var userIsAway = false
    let onExit: () -> Void
    let onSave: (ClubLineup) throws -> Void
    @ViewBuilder let matchContent: (FriendlyMatchConfiguration, Binding<Bool>) -> MatchContent
    @State private var prepared: FriendlyMatchConfiguration?
    @State private var playing = false

    var body: some View {
        if let prepared, playing { matchContent(prepared, $playing) }
        else {
            TeamManagementView(lineup: prepared?.home ?? configuration.home,
                kit: MatchKits.resolveForPlay(configuration: configuration, userIsAway: userIsAway).home,
                title: "Match preparation", actionTitle: "Kick off", opponentName: configuration.away.team.name,
                onCancel: onExit) { lineup, _ in
                    try onSave(lineup)
                    var updated = configuration; updated.home = lineup; prepared = updated; playing = true
                }
        }
    }
}
