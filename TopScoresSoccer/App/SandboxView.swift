import SwiftUI

struct SandboxView: View {
    @State private var session: GameSession
    @State private var confirmingExit = false
#if DEBUG
    @State private var showingWorldCupDebugControls = false
    @State private var wasPausedBeforeDebugControls = false
#endif
    private let onExit: (() -> Void)?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let lime = Color(red: 0.86, green: 0.98, blue: 0.60)

    init(configuration: FriendlyMatchConfiguration? = nil, startingMode: ExerciseMode? = nil,
         careerContext: CareerMatchContext? = nil, onCareerComplete: ((Int, Int) throws -> Void)? = nil,
         onExit: (() -> Void)? = nil) {
        _session = State(initialValue: GameSession(configuration: configuration, startingMode: startingMode,
                                                careerContext: careerContext, onCareerComplete: onCareerComplete))
        self.onExit = onExit
    }

    init(configuration: FriendlyMatchConfiguration, worldCupContext: WorldCupMatchContext,
         onWorldCupComplete: @escaping (WorldCupUserMatchOutcome) throws -> Void,
         onExit: (() -> Void)? = nil) {
        _session = State(initialValue: GameSession(configuration: configuration,
            worldCupContext: worldCupContext, onWorldCupComplete: onWorldCupComplete))
        self.onExit = onExit
    }

    var body: some View {
        ZStack {
            GameSurface(scene: session.scene).ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                VStack(spacing: 5) {
                    if let name = session.hud.selectedPlayerName {
                        Text(name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white).lineLimit(1)
                            .accessibilityLabel(session.isCareerMatch ? "\(name), \(session.hud.homeName)" : name)
                            .accessibilityIdentifier("match.selected-player")
                    }
                    HStack(spacing: 7) {
                        if let card = session.hud.card {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(card == "red" ? Color.red : Color.yellow)
                                .frame(width: 11, height: 15)
                                .accessibilityLabel(card == "red" ? "Red card" : "Yellow card")
                        }
                        Text(session.hud.status)
                            .font(.system(size: 11, weight: .black, design: .monospaced)).tracking(2)
                            .foregroundStyle(lime)
                            .accessibilityIdentifier("sandbox.status")
                    }
                    if let notice = session.hud.substitutionNotice {
                        Text(notice).font(.footnote).foregroundStyle(.yellow)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("match.substitution-notice")
                    }
                    Text(session.hud.detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: 390)
                .padding(.bottom, 170)
                .allowsHitTesting(false)
            }
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 8)

            if session.debugEnabled {
                VStack {
                    HStack {
                        Text(debugText)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, 126).padding(.leading, 18)
                .allowsHitTesting(false)
            }
            if session.userPaused && !session.showingSettings && !session.showingHelp && !matchEnded {
                VStack(spacing: 18) {
                    Image(systemName: "pause.circle").font(.system(size: 36, weight: .light))
                    Text("Take a breather").font(.title2.bold())
                    Button("Back to the pitch") { session.userPaused = false }
                        .buttonStyle(.borderedProminent).tint(lime).foregroundStyle(.black)
                        .accessibilityIdentifier("sandbox.resume")
                    if onExit != nil {
                        Button(returnLabel, action: requestExit).tint(.white)
                            .accessibilityIdentifier("match.choose-clubs")
                    }
                }
                .padding(30).frame(width: 310)
                .foregroundStyle(.white)
                .background(Color(red: 0.04, green: 0.12, blue: 0.12).opacity(0.96),
                            in: RoundedRectangle(cornerRadius: 24))
            }
            if session.hud.phase == .halfTime && !session.showingSettings && !session.showingHelp {
                Color.black.opacity(0.55).ignoresSafeArea().accessibilityHidden(true)
                VStack(spacing: 18) {
                    Text("Half-time").font(.title.bold())
                    Text("\(session.hud.scoreboardHomeName) \(session.hud.scoreboardHomeGoals) – \(session.hud.scoreboardAwayGoals) \(session.hud.scoreboardAwayName)")
                        .font(.headline).multilineTextAlignment(.center)
                    Text("Teams swap ends. You will attack the \(session.hud.attacksTopGoal ? "bottom" : "top") goal.")
                        .font(.subheadline).multilineTextAlignment(.center)
                        .accessibilityIdentifier("match.half-time-direction")
                    Button("Start second half") { session.resumeAfterHalfTime() }
                        .buttonStyle(.borderedProminent).tint(lime).foregroundStyle(.black)
                        .accessibilityIdentifier("match.second-half")
                }
                .padding(24).frame(maxWidth: 390)
                .foregroundStyle(.white)
                .background(Color(red: 0.04, green: 0.12, blue: 0.12), in: RoundedRectangle(cornerRadius: 24))
                .padding(20)
            }
            if session.penaltyShootout != nil && !session.showingSettings && !session.showingHelp {
                Color.black.opacity(0.62).ignoresSafeArea().accessibilityHidden(true)
                penaltyShootoutCard
            } else if matchEnded && !session.showingSettings && !session.showingHelp {
                Color.black.opacity(0.48).ignoresSafeArea()
                    .accessibilityHidden(true)
                matchResultCard
            }
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
        .sheet(isPresented: $session.showingSettings) { TuningView(session: session) }
        .sheet(isPresented: $session.showingHelp) { helpView }
        .sheet(isPresented: Binding(
            get: { session.hud.pendingInjuryID != nil && !session.showingSettings && !session.showingHelp },
            set: { _ in })) {
            injuryReplacementView.interactiveDismissDisabled()
        }
#if DEBUG
        .sheet(isPresented: $showingWorldCupDebugControls, onDismiss: closeWorldCupDebugControls) {
            worldCupDebugControls
        }
#endif
        .confirmationDialog("Leave match?", isPresented: $confirmingExit, titleVisibility: .visible) {
            Button("Leave match", role: .destructive) { onExit?() }
                .accessibilityIdentifier("career.leave-match")
            Button("Keep playing", role: .cancel) { session.userPaused = false }
        } message: {
            Text(session.isWorldCupMatch
                 ? "Your World Cup progress is saved. This unfinished fixture will restart from kickoff when you return."
                 : "This match is unfinished. Your season is saved, and this fixture will restart from kickoff when you return.")
        }
        .onChange(of: scenePhase) { _, phase in session.active = phase == .active }
        .onDisappear { session.active = false }
    }

    private var injuryReplacementView: some View {
        NavigationStack {
            List {
                Section {
                    Label("\(session.hud.injuredPlayer?.displayName ?? "Your player") cannot continue", systemImage: "cross.case.fill")
                        .font(.headline).accessibilityIdentifier("injury.player")
                    Text("Choose a replacement from your squad. The match is paused while you decide.")
                        .foregroundStyle(.secondary)
                }
                Section("Available replacements") {
                    ForEach(session.hud.injuryReplacements) { player in
                        Button {
                            session.substituteInjuredPlayer(with: player.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(player.name).font(.headline)
                                Text("\(player.role) · \(player.jerseyNumber.map { "No. \($0) · " } ?? "")Rating \(Int(player.effectiveRating))")
                                    .font(.subheadline).foregroundStyle(Color.secondary)
                            }.padding(.vertical, 5)
                        }
                        .accessibilityIdentifier("injury.replace.\(player.id)")
                    }
                    if session.hud.injuryReplacements.isEmpty {
                        Text("No eligible squad players remain. Your team will continue with one fewer player.")
                        Button("Continue match") { session.continueWithoutReplacement() }
                            .accessibilityIdentifier("injury.continue")
                    }
                }
            }
            .tint(.blue)
            .navigationTitle("Injury substitution")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "soccerball")
                        .font(.system(size: 22, weight: .medium)).foregroundStyle(lime)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TOP SCORES").font(.system(size: 15, weight: .black)).tracking(1)
                        Text(session.isWorldCupMatch ? "WORLD CUP" : session.isClubMatch ? "PREMIER LEAGUE" : session.mode == .match ? "QUICK MATCH" : "TRAINING GROUND")
                            .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.4)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 7) {
                    Text(session.mode == .match ? session.hud.scoreboardHomeAbbreviation : "N").foregroundStyle(.white.opacity(0.8))
                    Text("\(session.hud.scoreboardHomeGoals) : \(session.hud.scoreboardAwayGoals)")
                        .font(.system(size: 23, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(session.mode == .match ? session.hud.scoreboardAwayAbbreviation : "S").foregroundStyle(.white.opacity(0.8))
                }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(session.mode == .match
                    ? "\(session.hud.scoreboardHomeName) \(session.hud.scoreboardHomeGoals), \(session.hud.scoreboardAwayName) \(session.hud.scoreboardAwayGoals)"
                    : "North \(session.hud.northGoals), South \(session.hud.southGoals)")
                .accessibilityIdentifier("sandbox.score")
            }
            HStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(session.modeTitle.uppercased())
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(lime).lineLimit(1).minimumScaleFactor(0.7)
                        if session.mode == .match {
                            Text("\(session.hud.matchHalf == 1 ? "1H" : "2H") · \(session.hud.clockText)")
                                .fixedSize(horizontal: true, vertical: false)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white).monospacedDigit()
                                .accessibilityLabel("\(session.hud.periodLabel), time remaining \(session.hud.clockText)")
                                .accessibilityIdentifier("match.clock")
                        }
                    }
                    Text(session.mode != .solo ? "\(session.hud.scoreboardHomeAbbreviation) \(session.hud.scoreboardHomePlayers) · \(session.hud.scoreboardAwayAbbreviation) \(session.hud.scoreboardAwayPlayers)\(session.isCareerMatch ? " · YOU: \(session.hud.homeAbbreviation)" : "")  \(session.hud.attacksTopGoal ? "↑" : "↓")" : "FIND YOUR TOUCH")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .accessibilityIdentifier("match.team-counts")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("sandbox.mode")
                Spacer(minLength: 4)
                if onExit != nil && (!matchEnded || !session.isCompetitionMatch || competitionResultSaved) {
                    toolbarButton(returnLabel, symbol: "xmark", id: "sandbox.exit", action: requestExit)
                }
#if DEBUG
                if session.isWorldCupMatch && !competitionResultSaved {
                    toolbarButton("World Cup debug controls", symbol: "forward.end.fill",
                                  id: "worldcup.debug-match", action: openWorldCupDebugControls)
                }
#endif
                toolbarButton("How to play", symbol: "questionmark", id: "sandbox.help") { session.showingHelp = true }
                if !session.isCompetitionMatch {
                    toolbarButton(session.mode == .match ? "New match" : "Reset practice", symbol: "arrow.counterclockwise", id: "sandbox.reset") { session.reset() }
                }
                toolbarButton(session.userPaused ? "Resume" : "Pause", symbol: session.userPaused ? "play.fill" : "pause.fill", id: "sandbox.pause") {
                    session.userPaused.toggle()
                }
                toolbarButton("Tune gameplay", symbol: "slider.horizontal.3", id: "sandbox.settings") { session.showingSettings = true }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(red: 0.025, green: 0.095, blue: 0.09).opacity(0.90), in: RoundedRectangle(cornerRadius: 16))
    }

    private var matchEnded: Bool {
        guard session.mode == .match else { return false }
        switch session.hud.phase {
        case .fullTime, .practiceEnded: return true
        default: return false
        }
    }

    private func requestExit() {
        if session.isCompetitionMatch && !matchEnded {
            session.userPaused = true
            confirmingExit = true
        } else if !session.isCompetitionMatch || competitionResultSaved {
            onExit?()
        }
    }

    private var matchResultCard: some View {
        ScrollView {
          VStack(spacing: 18) {
            Text(resultHeading)
                .font(.caption.bold()).tracking(2).foregroundStyle(lime)
            Text(session.hud.matchResult)
                .font(.title.bold()).multilineTextAlignment(.center)
                .accessibilityIdentifier("match.result")
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 14) {
                    accessibleScoreRow(session.hud.scoreboardHomeName, goals: session.resultScore.home)
                    accessibleScoreRow(session.hud.scoreboardAwayName, goals: session.resultScore.away)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Final score: \(session.hud.scoreboardHomeName) \(session.resultScore.home), \(session.hud.scoreboardAwayName) \(session.resultScore.away)")
            } else {
              HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text(session.hud.scoreboardHomeName.uppercased()).font(.caption.bold()).foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    Text("\(session.resultScore.home)").font(.system(size: 44, weight: .bold, design: .rounded))
                }
                Text(":").font(.title).foregroundStyle(.white.opacity(0.5))
                VStack(spacing: 4) {
                    Text(session.hud.scoreboardAwayName.uppercased()).font(.caption.bold()).foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    Text("\(session.resultScore.away)").font(.system(size: 44, weight: .bold, design: .rounded))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Final score: \(session.hud.scoreboardHomeName) \(session.resultScore.home), \(session.hud.scoreboardAwayName) \(session.resultScore.away)")
            }
            if session.isCareerMatch {
                careerResultActions
            } else if session.isWorldCupMatch {
                worldCupResultActions
            } else {
              Button("Play again") {
                session.userPaused = false
                session.reset()
            }
            .buttonStyle(.borderedProminent).tint(lime).foregroundStyle(.black)
            .accessibilityIdentifier("match.play-again")
            if let onExit {
                Button("Choose clubs", action: onExit)
                    .buttonStyle(.bordered).tint(.white)
                    .accessibilityIdentifier("match.choose-clubs")
            } else {
                Button("Settings") { session.showingSettings = true }
                    .buttonStyle(.bordered).tint(.white)
            }
            }
          }
          .foregroundStyle(.white).padding(28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 650 : 350)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(red: 0.04, green: 0.12, blue: 0.12),
                    in: RoundedRectangle(cornerRadius: 24))
        .padding(20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("match.results")
    }

    private func accessibleScoreRow(_ name: String, goals: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(name).font(.headline).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("\(goals)").font(.system(size: 44, weight: .bold, design: .rounded)).fixedSize()
        }
    }

    @ViewBuilder private var careerResultActions: some View {
        if case .practiceEnded(let losingTeam) = session.hud.phase {
            Text("\(losingTeam == .blue ? session.hud.homeName : session.hud.awayName) forfeits. A 3–0 result is awarded to the opposition.")
                .font(.subheadline).multilineTextAlignment(.center)
        }
        if session.careerResultSaved {
            Label("Progress saved", systemImage: "checkmark.circle.fill")
                .font(.subheadline).foregroundStyle(lime)
                .accessibilityLabel("Result and matchweek saved")
                .accessibilityIdentifier("career.result-saved")
            Button("Continue season") { onExit?() }
                .buttonStyle(.borderedProminent).tint(lime).foregroundStyle(.black)
                .accessibilityIdentifier("career.continue")
        } else {
            Text(session.careerSaveError ?? "Saving your result…")
                .font(.subheadline).multilineTextAlignment(.center)
                .accessibilityIdentifier("career.save-error")
            Button("Retry save") { session.saveCareerResult() }
                .buttonStyle(.borderedProminent).tint(lime).foregroundStyle(.black)
                .accessibilityIdentifier("career.retry-save")
        }
    }

    @ViewBuilder private var worldCupResultActions: some View {
        if session.needsExtraTime {
            Text("The score is level after 90 minutes. Knockout matches continue with extra time.")
                .font(.subheadline).multilineTextAlignment(.center)
            Button("Play extra time") { session.startExtraTime() }
                .buttonStyle(.borderedProminent).tint(lime).foregroundStyle(.black)
                .accessibilityIdentifier("worldcup.extra-time")
        } else if session.worldCupResultSaved {
            Label("World Cup progress saved", systemImage: "checkmark.circle.fill")
                .font(.subheadline).foregroundStyle(lime)
                .accessibilityIdentifier("worldcup.result-saved")
            Button("Continue tournament") { onExit?() }
                .buttonStyle(.borderedProminent).tint(lime).foregroundStyle(.black)
                .accessibilityIdentifier("worldcup.continue")
        } else {
            Text(session.worldCupSaveError ?? "Saving your result…")
                .font(.subheadline).multilineTextAlignment(.center)
                .accessibilityIdentifier("worldcup.save-error")
            Button("Retry save") { session.saveWorldCupResult() }
                .buttonStyle(.borderedProminent).tint(lime).foregroundStyle(.black)
                .accessibilityIdentifier("worldcup.retry-save")
        }
    }

    private var penaltyShootoutCard: some View {
        Group {
            if let shootout = session.penaltyShootout {
                ScrollView {
                    VStack(spacing: 18) {
                        Text("PENALTY SHOOT-OUT").font(.caption.bold()).tracking(2).foregroundStyle(lime)
                        Text("Level after 120 minutes").font(.title2.bold())
                        HStack(spacing: 18) {
                            penaltyTeam(session.hud.homeName, score: shootout.userGoals,
                                        attempts: shootout.attempts.filter(\.byUser))
                            Text(":").font(.title).foregroundStyle(.white.opacity(0.5))
                            penaltyTeam(session.hud.awayName, score: shootout.opponentGoals,
                                        attempts: shootout.attempts.filter { !$0.byUser })
                        }
                        Text(shootout.message).font(.subheadline).multilineTextAlignment(.center)
                        if shootout.isFinished {
                            if session.worldCupResultSaved {
                                Label("World Cup progress saved", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(lime).accessibilityIdentifier("worldcup.result-saved")
                                Button("Continue tournament") { onExit?() }
                                    .buttonStyle(.borderedProminent).tint(lime).foregroundStyle(.black)
                                    .accessibilityIdentifier("worldcup.continue")
                            } else {
                                Text(session.worldCupSaveError ?? "Saving your result…")
                                Button("Retry save") { session.saveWorldCupResult() }
                                    .buttonStyle(.borderedProminent).tint(lime).foregroundStyle(.black)
                            }
                        } else {
                            Text(shootout.turn == .userShoots ? "PLACE YOUR KICK" : "CHOOSE YOUR DIVE")
                                .font(.caption.bold()).tracking(1.2).foregroundStyle(.white.opacity(0.72))
                            HStack(spacing: 10) {
                                ForEach(PenaltyDirection.allCases) { direction in
                                    Button { session.choosePenalty(direction) } label: {
                                        VStack(spacing: 7) {
                                            Image(systemName: direction.symbol).font(.title2.bold())
                                            Text(direction.title).font(.caption.bold())
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 62)
                                    }
                                    .buttonStyle(.bordered).tint(lime)
                                    .accessibilityIdentifier("worldcup.penalty.\(direction.rawValue)")
                                }
                            }
                        }
                    }
                    .foregroundStyle(.white).padding(26)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: 430)
                .background(Color(red: 0.04, green: 0.12, blue: 0.12), in: RoundedRectangle(cornerRadius: 24))
                .padding(20)
                .accessibilityIdentifier("worldcup.penalty-shootout")
            }
        }
    }

    private func penaltyTeam(_ name: String, score: Int, attempts: [PenaltyAttempt]) -> some View {
        VStack(spacing: 8) {
            Text(name.uppercased()).font(.caption.bold()).multilineTextAlignment(.center).lineLimit(2)
            Text("\(score)").font(.system(size: 42, weight: .bold, design: .rounded)).monospacedDigit()
            HStack(spacing: 4) {
                ForEach(attempts) { attempt in
                    Circle().fill(attempt.scored ? lime : Color.red.opacity(0.85)).frame(width: 8, height: 8)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var resultHeading: String {
        if session.needsExtraTime { return "LEVEL AFTER 90 MINUTES" }
        if session.tournamentPeriod == .extraTime { return "AFTER EXTRA TIME" }
        return session.hud.phase == .fullTime ? "FULL TIME" : "MATCH OVER"
    }

    private var returnLabel: String {
        session.isWorldCupMatch ? "Return to World Cup" : session.isCareerMatch ? "Return to season" : "Choose clubs"
    }

    private var competitionResultSaved: Bool {
        session.isCareerMatch ? session.careerResultSaved : session.isWorldCupMatch ? session.worldCupResultSaved : true
    }

#if DEBUG
    private func openWorldCupDebugControls() {
        wasPausedBeforeDebugControls = session.userPaused
        session.userPaused = true
        showingWorldCupDebugControls = true
    }

    private func closeWorldCupDebugControls() {
        session.userPaused = wasPausedBeforeDebugControls
    }

    private func runWorldCupDebugAction(_ action: WorldCupDebugMatchAction) {
        session.debugAdvanceWorldCupMatch(action)
        showingWorldCupDebugControls = false
    }

    private var worldCupDebugControls: some View {
        NavigationStack {
            List {
                Section {
                    debugMatchButton("End with a win", detail: "Record a 1–0 win and save the fixture.",
                                     symbol: "checkmark.circle.fill", color: lime, action: .win)
                    debugMatchButton("End with a draw", detail: session.worldCupContext?.isKnockout == true
                                     ? "Finish level and continue with knockout rules."
                                     : "Record a 0–0 draw and save the fixture.",
                                     symbol: "equal.circle.fill", color: .yellow, action: .draw)
                    debugMatchButton("End with a defeat", detail: "Record a 0–1 defeat and save the fixture.",
                                     symbol: "xmark.circle.fill", color: .red, action: .defeat)
                } header: {
                    Text("Instant result")
                } footer: {
                    Text("These use the normal World Cup result and save path. Other tournament fixtures are simulated as usual.")
                }

                if session.worldCupContext?.isKnockout == true {
                    Section("Knockout checkpoints") {
                        debugMatchButton("Jump straight to extra time", detail: "Set regulation to 0–0 and begin the 90–120′ period.",
                                         symbol: "clock.arrow.2.circlepath", color: .orange, action: .extraTime,
                                         disabled: session.tournamentPeriod == .extraTime)
                        debugMatchButton("Jump to penalty shoot-out", detail: "Set regulation and extra time level, then choose kicks and saves.",
                                         symbol: "soccerball", color: lime, action: .penaltyShootout)
                    }
                }
            }
            .navigationTitle("Debug match controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingWorldCupDebugControls = false }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("worldcup.debug-sheet")
    }

    private func debugMatchButton(_ title: String, detail: String, symbol: String, color: Color,
                                  action: WorldCupDebugMatchAction, disabled: Bool = false) -> some View {
        Button { runWorldCupDebugAction(action) } label: {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: symbol).font(.title3).foregroundStyle(color).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier("worldcup.debug-\(action.rawValue)")
    }
#endif

    private func toolbarButton(_ label: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }

    private var debugText: String {
        "\(session.hud.fps) FPS  ·  PLAYER \(session.hud.selectedPlayerID + 1)\n" +
        String(format: "Player %.1f m/s  Ball %.1f m/s\n", session.hud.playerSpeed, session.hud.ballSpeed) +
        "Ball \(session.hud.ballMode)  Action \(session.hud.action)\n" +
        String(format: "Charge %.0f%%  Curve %.2fs\n", session.hud.charge * 100, session.hud.curveTime) +
        "Kick ready: \(session.hud.canKick ? "yes" : "no")\n" +
        "Possession: \(session.hud.possession)  Target: \(session.hud.passTargetID.map { String($0 + 1) } ?? "space")\n" +
        "Tackles: \(session.hud.tackles)  Slides: \(session.hud.slides)  Headers: \(session.hud.headers)\n" +
        "Crosses: \(session.hud.crosses)\n" +
        String(format: "Height %.2fm  Chip %.2fs\n", session.hud.ballHeight, session.hud.chipWindow) +
        "Queue: \(session.hud.queuedAction ?? "none")  Fouls: \(session.hud.fouls)\n" +
        "Switches: \(session.hud.switches)"
    }

    private var helpView: some View {
        NavigationStack {
            List {
                Section("One stick. Two buttons.") {
                    Label("Touch anywhere on the left side of the pitch, then drag to run and aim. Lift and touch again to place the joystick under your thumb.", systemImage: "hand.draw")
                    Label("Press PASS for an immediate short ground pass towards the highlighted teammate. With no nearby option, play a short ball into space. Holding PASS never changes the kick.", systemImage: "arrow.up.right")
                    Label("Within 35 metres of the opposition goal, SHOOT always attempts a shot, even when a teammate is nearby or you are facing away. Aim to influence placement. Tap for a quick finish, or hold and release for more power.", systemImage: "scope")
                    Label("Watch the small meter beneath your player. Shots farther out need more power and have a narrower green release band. Too little power makes a weak attempt; too much adds height and reduces accuracy. Green indicates good power, not a guaranteed goal.", systemImage: "chart.bar")
                    Label("Outside shooting range, LONG BALL sends a lofted ball in your chosen direction. Hold longer for greater distance. When CROSS appears on the wing, release in green to find runners in the box. Inside shooting range the button always shoots.", systemImage: "arrow.turn.up.left")
                    Label("Off the ball, press BLOCK for a standing tackle or SLIDE for an immediate sliding tackle. A slide reaches farther but leaves you exposed while recovering. Release and press again for another challenge.", systemImage: "figure.soccer")
                    Label("When HEAD appears, press to head towards goal or clear it upfield. HEAD PASS requests a directional header pass. Time the press as the ball reaches you. For incoming ground balls, PASS or SHOOT can prepare your next touch.", systemImage: "soccerball")
                    Label("For a moment after shooting, steer sideways to bend the ball, or quickly pull opposite the kick to chip it. Your player coasts, then movement resumes.", systemImage: "arrow.turn.up.right")
                }
                Section(session.isClubMatch ? "Three-minute 11v11" : "Three-minute 5v5") {
                    Text("A coin toss decides your starting direction. Teams swap ends at half time. The kickoff message shows which goal you attack.")
                    Text(session.isClubMatch
                         ? "Ten outfield players and a goalkeeper play for each club. You control \(session.hud.homeName), attacking the \(session.hud.attacksTopGoal ? "top" : "bottom") goal. Teammates keep your selected formation and offer passing options. Player ratings affect pace, touch, passing, crossing, shooting, heading and defending."
                         : "Four outfield players and a goalkeeper play for each side. Blue attacks the \(session.hud.attacksTopGoal ? "top" : "bottom") goal. Outfield teammates keep a 2–2 shape, with a player closing down the ball and others covering or offering passes.")
                    Text(session.isCareerMatch
                         ? "Play two 90-second halves. Time lost to fouls, restarts and injuries appears as added time in each half. Dangerous attacks and attacking set pieces can finish before the whistle. Settings and pauses stop the clock. At full time, your result and the other matches in this matchweek save automatically. Tap Continue season to see the table. Leaving an unfinished match keeps the fixture unplayed."
                         : "Play two 90-second halves. Time lost to fouls, restarts and injuries appears as added time in each half. Dangerous attacks and attacking set pieces can finish before the whistle. Settings and pauses stop the clock. At full time, see the result and tap Play again for a fresh match.")
                    Text("Keepers have different shirts, gloves and a GK badge. They position themselves, dive and save automatically off the ball. When your keeper has the ball, the bright ring gives you control.")
                    Text("After a goal, both teams return to their own half for the conceding side’s kickoff. The last touch decides who takes a throw-in, corner or goal kick. Aim your restarts with the joystick. Use PASS for a short option or the shooting button for a shot or long delivery. The opposition restarts automatically.")
                }
                Section("Keeper and throw-ins") {
                    Text("With the ball in the keeper’s hands, aim at a teammate and press SHORT THROW. The keeper uses an underarm throw to a nearby player, an overarm throw farther away, and adds height when the route needs it. Cyan brackets show the intended teammate. Hold LONG THROW and release for a high, long overarm throw; the distance bar fills as you hold.")
                    Text("For a goal kick, aim at a teammate and press PASS to pass from the ground. The keeper adds height when needed to reach the target. Hold LONG BALL and release for a high, long kick. You control the intended receiver as soon as the ball is released.")
                    Text("While the keeper holds the ball, both teams spread back into shape and opponents withdraw from the box. One teammate offers a short throw; take a moment to find the outlet.")
                    Text("Pass back to your keeper to take control while the ball travels. A backpass stays at their feet: the keeper moves more slowly and can be tackled. Press PASS or hold LONG BALL to kick it clear.")
                    Text("For a throw-in, nearby teammates offer short options. Aim at the cyan brackets and press SHORT THROW for a short throw; hold LONG THROW and release to send it farther. The distance bar has no shot sweet spot or overhit penalty.")
                }
                Section("Playing as a team") {
                    Text(session.isClubMatch
                         ? "You control the \(session.hud.homeName) player with the bright ring. Your club attacks the \(session.hud.attacksTopGoal ? "top" : "bottom") goal. Teams swap ends at half time."
                         : "You control the blue player with the bright ring. Blue attacks the \(session.hud.attacksTopGoal ? "top" : "bottom") goal. Teams swap ends at half time.")
                    Text("Off the ball, move the stick in the direction you want to run. Control automatically goes to a nearby player whose run can reach the ball or close down its carrier. Watch the bright ring; no tap is needed to switch.")
                    Text("Selection considers where the ball and its carrier are heading, so a player in a better position can take priority over the closest player. Clear changes of direction select quickly; a committed challenge or prepared kick stays with its player.")
                    Text("After an assisted pass, the yellow ring pulses around the player you now control. They follow your joystick immediately, even if you keep holding the passing direction. Centre or release the stick to let them meet the incoming ball. You can also prepare their next kick before it arrives.")
                    Text("Keep the ball moving with quick passes. Teammates offer nearby passing lanes and time forward runs into space. The passer moves into support, making it easier to pass again without stopping to dribble.")
                    Text("Players run a little faster without the ball. To win possession, run into the ball from either side or meet the opponent head on. Button tackles are also available: BLOCK stays on your feet and SLIDE lunges towards the ball.")
                    Text("The opponent shields the ball from behind. Stay close and keep pressing to win it, or run around to approach from the side. Press BLOCK for a standing tackle or SLIDE for a committed sliding challenge.")
                    Text("When defending or chasing a loose ball, press SLIDE to slide along your running direction. Reach farther, but allow time to recover if you miss. An incoming pass instead lets you prepare a kick.")
                    Text("Ball first is a clean challenge. A late slide shows the collision, fall and ground reaction before the whistle. Most players get back up before the restart. Occasionally a player is injured and must leave: choose an available squad replacement for your team; the opposition substitutes automatically. Injuries last for this match, including extra time. Yellow cards and rare reds follow the whistle; two yellows also mean a sending-off.")
                    Text("At a free kick, one or two teammates offer a short pass and opponents stand at least ten yards back. Move the joystick to aim, then press PASS to the highlighted teammate or hold the shooting button and release for power.")
                    Text("A defending foul inside the penalty area awards a penalty. After the fall, whistle and recovery, take the kick from the penalty spot. Aim at goal and tap SHOOT, or hold SHOOT and release in the green band for more power. The goalkeeper tries to save it and play continues after the kick.")
                    Text("The restart taker must wait for another player to touch the ball before playing it again. Touching it twice gives the opposition an indirect free kick.")
                    Text("Cyan brackets preview your pass target; the yellow ring identifies the player you control. The camera follows both the receiver and ball during a pass. A numbered edge arrow points to a receiver who moves beyond the view. Passes stay loose and opponents can intercept them.")
                }
                Section("Timing runs and offside") {
                    Text("Cross from a wide position near the opposition box. Moving too early or too close to the goal line makes the delivery harder. Better midfielders and attackers cross more accurately; better strikers are stronger finishers with their heads. Position and timing still matter.")
                    Text("In matches, time the pass before your runner moves beyond the defensive line. In the opponents’ half, stay level with the second-last defender or behind the ball when a teammate plays it. You can then run beyond the line to receive.")
                    Text("An offside-positioned player who receives or plays that ball gives the opposition an indirect free kick. Being ahead alone does not stop play. The whistle and OFFSIDE message identify the decision; another player must touch the indirect kick before a goal can count.")
                    Text("There is no offside directly from a throw-in, corner or goal kick. Keeper throws during open play still use the offside check. Both teams follow these rules.")
                }
                Section("Keep it in play") {
                    Text("For an aerial ball, watch its shadow and move into position. Tap as a cross arrives to head towards goal; aim the joystick for other headers. A slightly early tap can queue the header briefly, but a tap close to contact gives your best chance. The player jumps and you feel a light contact only when the header connects.")
                    Text("Before an incoming ball reaches your feet, aim the next kick and press PASS to queue a pass, or hold SHOOT / LONG BALL and release to prepare a powerful kick. Your chosen direction and power are saved, so you can keep moving to meet the ball.")
                    Text("A queued pass keeps its chosen teammate and aim while you move to meet the ball. A short pass into open space stays on the ground. You must make contact before the queue expires.")
                    Text("Aim your queued pass into the pitch. Near a boundary, the player keeps a rescue touch in play; in ordinary off-ball play, press SLIDE to reach and clear the ball.")
                    Text("A queue belongs to that player and clears on a pause, foul or restart. It cannot pull a ball back after it has gone out.")
                }
                Section("Make it yours") {
                    Text("Get close to a loose ball to cushion it into your run. Frequent touches make dribbling easier, while sharp turns can still expose the ball.")
                    Text(session.isCareerMatch
                         ? "Bookings and sendings-off last for this match only. If either club loses all outfield players, the other club receives a 3–0 win. All players return for the next fixture."
                         : "Bookings and sendings-off last for the match. The reset arrow starts a fresh match with all players available.")
                    Text(session.isClubMatch
                         ? "Open Training from the Friendly tab for Pass & defend, the original 3v3 exercise with empty goals, or Solo practice for shooting and first-time touches without opponents."
                         : "Choose Pass & defend in settings for the original 3v3 exercise with empty goals and no clock. Choose Solo practice for shooting, chips, queued touches and sliding recoveries without opponents.")
                    Text("Open the sliders to adjust movement, dribbling, shot power and curve. Changes last for this app session.")
                }
            }
            .navigationTitle("How to play")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { session.showingHelp = false } } }
        }
    }
}

#Preview("5v5 match", traits: .portrait) {
    SandboxView()
}
