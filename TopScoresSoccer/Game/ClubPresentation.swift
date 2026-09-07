import SwiftUI
import SpriteKit

struct ClubKit: Equatable, Sendable {
    let shirtHex: String
    let shortsHex: String
    let trimHex: String
    let socksHex: String
    let goalkeeperHex: String
}

/// Shared by the dressing-room preview and the pitch. Alternate kits are game designs.
struct MatchKits: Equatable, Sendable {
    let home: ClubKit
    let away: ClubKit
    let awayIsClash: Bool

    /// Return kits in simulation order (user, opponent), resolving clashes by actual venue.
    static func resolveForPlay(configuration: FriendlyMatchConfiguration, userIsAway: Bool) -> MatchKits {
        guard userIsAway else { return resolve(configuration: configuration) }
        let venue = FriendlyMatchConfiguration(home: configuration.away, away: configuration.home)
        let kits = resolve(configuration: venue)
        return MatchKits(home: kits.away, away: kits.home, awayIsClash: kits.awayIsClash)
    }

    static func resolve(configuration: FriendlyMatchConfiguration) -> MatchKits {
        let homeTeam = configuration.home.team
        let awayTeam = configuration.away.team
        let homeShirt = RGBHex(homeTeam.primaryHex).hex
        let originalAway = RGBHex(awayTeam.primaryHex).hex
        let clash = RGBHex(homeShirt).distance(to: RGBHex(originalAway)) < 0.42
        let alternatives = [awayTeam.secondaryHex, "#FAF7ED", "#152039", "#FFE15D", "#C48CFF"]
        let awayShirt = clash ? mostDistinct(alternatives, from: [homeShirt]) : originalAway
        let keeperOptions = ["#FFB52E", "#A579EF", "#66EBCE", "#FF83BE", "#F4F3ED", "#253049"]
        let homeKeeper = mostDistinct(keeperOptions, from: [homeShirt, awayShirt])
        let awayKeeper = mostDistinct(keeperOptions, from: [homeShirt, awayShirt, homeKeeper])
        func kit(_ team: ClubTeam, shirt: String, keeper: String) -> ClubKit {
            let secondary = RGBHex(team.secondaryHex).hex
            let trim = RGBHex(shirt).distance(to: RGBHex(secondary)) > 0.25
                ? secondary : RGBHex(shirt).inkHex
            return ClubKit(shirtHex: shirt, shortsHex: secondary, trimHex: trim,
                           socksHex: shirt, goalkeeperHex: keeper)
        }
        return MatchKits(home: kit(homeTeam, shirt: homeShirt, keeper: homeKeeper),
                         away: kit(awayTeam, shirt: awayShirt, keeper: awayKeeper), awayIsClash: clash)
    }

    private static func mostDistinct(_ options: [String], from others: [String]) -> String {
        options.max { lhs, rhs in
            let left = others.map { RGBHex(lhs).distance(to: RGBHex($0)) }.min() ?? 0
            let right = others.map { RGBHex(rhs).distance(to: RGBHex($0)) }.min() ?? 0
            return left < right
        }.map { RGBHex($0).hex } ?? "#FAF7ED"
    }
}

struct RGBHex: Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let hex: String

    init(_ value: String) {
        let clean = value.hasPrefix("#") ? String(value.dropFirst()) : value
        let number = clean.count == 6 ? UInt32(clean, radix: 16) : nil
        let rgb = number ?? 0x718C80
        red = Double((rgb >> 16) & 255) / 255
        green = Double((rgb >> 8) & 255) / 255
        blue = Double(rgb & 255) / 255
        hex = String(format: "#%06X", rgb)
    }

    var luminance: Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    var inkHex: String { luminance > 0.36 ? "#10241E" : "#FFFFFF" }
    func distance(to other: RGBHex) -> Double {
        let r = red - other.red, g = green - other.green, b = blue - other.blue
        return sqrt(0.30 * r * r + 0.59 * g * g + 0.11 * b * b)
    }
}

extension Color {
    init(hex: String) {
        let rgb = RGBHex(hex)
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension ClubTeam {
    var scoreboardAbbreviation: String {
        if id.count == 3, id.allSatisfy({ $0.isLetter }) { return id.uppercased() }
        let names = ["Manchester City": "MCI", "Manchester United": "MUN", "Nottingham Forest": "NFO",
                     "Crystal Palace": "CRY", "Brighton & Hove Albion": "BHA", "Aston Villa": "AVL",
                     "Tottenham Hotspur": "TOT", "Newcastle United": "NEW", "Leeds United": "LEE",
                     "Ipswich Town": "IPS", "Hull City": "HUL", "Coventry City": "COV"]
        return names[name] ?? names[displayName] ?? String(displayName.prefix(3)).uppercased()
    }
}

extension SKColor {
    convenience init(clubHex: String) {
        let rgb = RGBHex(clubHex)
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}
