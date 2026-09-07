import SwiftUI

@main
struct TopScoresSoccerApp: App {
    var body: some Scene {
        WindowGroup {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--world-cup-celebration") {
                DebugCelebrationLaunchView()
            } else if opensTrainingOrLegacyTest {
                SandboxView()
            } else {
                FootballHomeView()
            }
#else
            if opensTrainingOrLegacyTest {
                SandboxView()
            } else {
                FootballHomeView()
            }
#endif
        }
    }

    private var opensTrainingOrLegacyTest: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--solo") || arguments.contains("--passing")
            || (arguments.contains("--uitesting") && !arguments.contains("--premier-league")
                && !arguments.contains("--career") && !arguments.contains("--career-ui-testing")
                && !arguments.contains("--world-cup") && !arguments.contains("--world-cup-ui-testing"))
    }
}

struct FootballHomeView: View {
    @State private var selectedMode: Int = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--world-cup") || arguments.contains("--world-cup-ui-testing") { return 2 }
        if arguments.contains("--career") || arguments.contains("--career-ui-testing") { return 1 }
        return 0
    }()

    var body: some View {
        TabView(selection: $selectedMode) {
            FriendlySetupView()
                .tabItem { Label("Friendly", systemImage: "soccerball").accessibilityIdentifier("app.friendly") }
                .tag(0)
                .accessibilityIdentifier("app.friendly")
            CareerView()
                .tabItem { Label("Career", systemImage: "trophy").accessibilityIdentifier("app.career") }
                .tag(1)
                .accessibilityIdentifier("app.career")
            WorldCupView()
                .tabItem { Label("World Cup", systemImage: "globe.europe.africa.fill").accessibilityIdentifier("app.worldcup") }
                .tag(2)
                .accessibilityIdentifier("app.worldcup")
        }
        .tint(FriendlyStyle.lime)
        .preferredColorScheme(.dark)
    }
}

#if DEBUG
private struct DebugCelebrationLaunchView: View {
    @State private var finished = false
    var body: some View {
        if finished { FootballHomeView() }
        else { WorldCupCelebrationView(teamName: "England") { finished = true } }
    }
}
#endif
