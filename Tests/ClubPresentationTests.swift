import XCTest
import SpriteKit
@testable import TopScoresSoccer

@MainActor
final class ClubPresentationTests: XCTestCase {
    func testRedClubClashChangesAwayKitAndSeparatesKeepers() throws {
        let catalogue = try PremierLeagueCatalogue.bundled()
        let home = try XCTUnwrap(catalogue.teams.first { $0.name == "Liverpool FC" })
        let away = try XCTUnwrap(catalogue.teams.first { $0.name == "Arsenal" })
        let configuration = FriendlyMatchConfiguration(home: .autoSelect(team: home), away: .autoSelect(team: away))
        let kits = MatchKits.resolve(configuration: configuration)
        XCTAssertTrue(kits.awayIsClash)
        XCTAssertEqual(kits.home.shirtHex, home.primaryHex)
        XCTAssertGreaterThan(RGBHex(kits.home.shirtHex).distance(to: RGBHex(kits.away.shirtHex)), 0.42)
        XCTAssertEqual(Set([kits.home.shirtHex, kits.away.shirtHex, kits.home.goalkeeperHex, kits.away.goalkeeperHex]).count, 4)
    }

    func testProfilesControlSkinShirtNumberAndCachedArtworkIdentity() throws {
        let teams = try PremierLeagueCatalogue.bundled().teams
        let configuration = FriendlyMatchConfiguration(home: .autoSelect(team: teams[0]), away: .autoSelect(team: teams[1]))
        var simulation = FootballSimulation(configuration: configuration)
        let renderer = PitchRenderer()
        let kits = MatchKits.resolve(configuration: configuration)
        renderer.matchKits = kits
        render(simulation, with: renderer)
        let player = try XCTUnwrap(renderer.root.childNode(withName: "//player-1"))
        let profile = try XCTUnwrap(simulation.roster[1].clubPlayer)
        let shirt = try XCTUnwrap(player.childNode(withName: "figure/shirt") as? SKShapeNode)
        let skin = try XCTUnwrap(player.childNode(withName: "figure/skin") as? SKShapeNode)
        let number = try XCTUnwrap(player.childNode(withName: "figure/shirt-number") as? SKLabelNode)
        assertColour(shirt.fillColor, equals: kits.home.shirtHex)
        assertColour(skin.fillColor, equals: profile.appearance.skinHex)
        XCTAssertEqual(number.text, profile.jerseyNumber.map(String.init) ?? "–")
        XCTAssertGreaterThan(Set(simulation.roster.compactMap { $0.clubPlayer?.appearance.skinHex }).count, 2)
        simulation.roster[1].clubPlayer?.appearance.skinHex = "#573928"
        render(simulation, with: renderer)
        let changed = try XCTUnwrap(renderer.root.childNode(withName: "//player-1"))
        XCTAssertFalse(player === changed)
        let changedSkin = try XCTUnwrap(changed.childNode(withName: "figure/skin") as? SKShapeNode)
        assertColour(changedSkin.fillColor, equals: "#573928")
        XCTAssertEqual(renderer.root.children.flatMap { $0.children }.filter { $0.name?.hasPrefix("player-shadow-") == true }.count, 22)
    }

    func testClubSceneReportsIdentityAndPreservesItAfterReset() throws {
        let teams = try PremierLeagueCatalogue.bundled().teams
        let configuration = FriendlyMatchConfiguration(home: .autoSelect(team: teams[0]), away: .autoSelect(team: teams[1]))
        let scene = GameScene(configuration: configuration)
        var last = SandboxHUD()
        scene.onHUDUpdate = { last = $0 }
        scene.refreshHUD()
        XCTAssertEqual(last.homeName, teams[0].displayName)
        XCTAssertEqual(last.awayName, teams[1].displayName)
        XCTAssertEqual(last.bluePlayers + last.redPlayers, 22)
        XCTAssertNotNil(last.selectedPlayerName)
        XCTAssertTrue(last.status.contains(teams[0].displayName.uppercased()))
        scene.resetSandbox()
        XCTAssertEqual(last.homeName, teams[0].displayName)
        XCTAssertEqual(scene.simulation.roster.count, 22)
    }

    private func render(_ simulation: FootballSimulation, with renderer: PitchRenderer) {
        renderer.render(footballers: simulation.footballers, selectedPlayerID: simulation.selectedPlayerID,
                        passTargetID: nil, ball: simulation.ball, hasControl: false, chargeFraction: 0,
                        aftertouchRemaining: 0, aftertouchVector: .zero, debug: false, deltaTime: 0)
    }

    private func assertColour(_ actual: SKColor, equals hex: String, file: StaticString = #filePath, line: UInt = #line) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(actual.getRed(&r, green: &g, blue: &b, alpha: &a), file: file, line: line)
        let expected = RGBHex(hex)
        XCTAssertEqual(Double(r), expected.red, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(Double(g), expected.green, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(Double(b), expected.blue, accuracy: 0.0001, file: file, line: line)
    }
}
