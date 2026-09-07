import Foundation

struct NationalTeamSnapshot: Sendable {
    let id: String
    let teams: [ClubTeam]
    let groups: [[String]]
}

enum NationalTeamCatalogue {
    static let snapshotID = "world-cup-2026-v1"

    static func flag(for teamID: String) -> String {
        if teamID == "eng" { return subdivisionFlag("gbeng") }
        if teamID == "sco" { return subdivisionFlag("gbsct") }
        guard let region = regionCodes[teamID] else { return "🌐" }
        return String(region.uppercased().unicodeScalars.compactMap { scalar in
            UnicodeScalar(127_397 + scalar.value).map(String.init)
        }.joined())
    }

    static func snapshot() -> NationalTeamSnapshot {
        let groups = seeds.map { group in group.map(\.code) }
        return NationalTeamSnapshot(id: snapshotID, teams: seeds.flatMap { $0 }.map(makeTeam), groups: groups)
    }

    private struct Seed: Sendable {
        let code: String
        let name: String
        let abbreviation: String
        let primary: String
        let secondary: String
        let rating: Double
    }

    private static let regionCodes: [String: String] = [
        "mex": "MX", "rsa": "ZA", "kor": "KR", "cze": "CZ",
        "can": "CA", "bih": "BA", "qat": "QA", "sui": "CH",
        "bra": "BR", "mar": "MA", "hai": "HT",
        "usa": "US", "par": "PY", "aus": "AU", "tur": "TR",
        "ger": "DE", "cuw": "CW", "civ": "CI", "ecu": "EC",
        "ned": "NL", "jpn": "JP", "swe": "SE", "tun": "TN",
        "bel": "BE", "nzl": "NZ", "egy": "EG", "irn": "IR",
        "esp": "ES", "uru": "UY", "cpv": "CV", "ksa": "SA",
        "fra": "FR", "sen": "SN", "irq": "IQ", "nor": "NO",
        "arg": "AR", "alg": "DZ", "aut": "AT", "jor": "JO",
        "por": "PT", "col": "CO", "uzb": "UZ", "cod": "CD",
        "cro": "HR", "gha": "GH", "pan": "PA",
    ]

    private static func subdivisionFlag(_ code: String) -> String {
        var result = String(UnicodeScalar(0x1F3F4)!)
        for scalar in code.unicodeScalars {
            if let tag = UnicodeScalar(0xE0000 + scalar.value) { result.unicodeScalars.append(tag) }
        }
        result.unicodeScalars.append(UnicodeScalar(0xE007F)!)
        return result
    }

    // Final 2026 group allocation. Results are deliberately not bundled: every save is a fresh tournament.
    private static let seeds: [[Seed]] = [
        [
            .init(code: "mex", name: "Mexico", abbreviation: "MEX", primary: "#167B4B", secondary: "#F7F4E8", rating: 79),
            .init(code: "rsa", name: "South Africa", abbreviation: "RSA", primary: "#F4C542", secondary: "#167B4B", rating: 72),
            .init(code: "kor", name: "Korea Republic", abbreviation: "KOR", primary: "#E32636", secondary: "#F5F5F5", rating: 77),
            .init(code: "cze", name: "Czechia", abbreviation: "CZE", primary: "#D71920", secondary: "#FFFFFF", rating: 78),
        ],
        [
            .init(code: "can", name: "Canada", abbreviation: "CAN", primary: "#D71920", secondary: "#FFFFFF", rating: 78),
            .init(code: "bih", name: "Bosnia and Herzegovina", abbreviation: "BIH", primary: "#154C9B", secondary: "#F7C948", rating: 75),
            .init(code: "qat", name: "Qatar", abbreviation: "QAT", primary: "#8A1538", secondary: "#FFFFFF", rating: 73),
            .init(code: "sui", name: "Switzerland", abbreviation: "SUI", primary: "#D71920", secondary: "#FFFFFF", rating: 82),
        ],
        [
            .init(code: "bra", name: "Brazil", abbreviation: "BRA", primary: "#F7D117", secondary: "#1D5AA6", rating: 89),
            .init(code: "mar", name: "Morocco", abbreviation: "MAR", primary: "#C1272D", secondary: "#0B8F55", rating: 84),
            .init(code: "hai", name: "Haiti", abbreviation: "HAI", primary: "#174A9C", secondary: "#D62D36", rating: 70),
            .init(code: "sco", name: "Scotland", abbreviation: "SCO", primary: "#172A54", secondary: "#FFFFFF", rating: 79),
        ],
        [
            .init(code: "usa", name: "USA", abbreviation: "USA", primary: "#FFFFFF", secondary: "#183A73", rating: 82),
            .init(code: "par", name: "Paraguay", abbreviation: "PAR", primary: "#D62D36", secondary: "#FFFFFF", rating: 77),
            .init(code: "aus", name: "Australia", abbreviation: "AUS", primary: "#F2C500", secondary: "#0B6B45", rating: 78),
            .init(code: "tur", name: "Türkiye", abbreviation: "TUR", primary: "#D71920", secondary: "#FFFFFF", rating: 81),
        ],
        [
            .init(code: "ger", name: "Germany", abbreviation: "GER", primary: "#F2F2F2", secondary: "#191919", rating: 87),
            .init(code: "cuw", name: "Curaçao", abbreviation: "CUW", primary: "#1769AA", secondary: "#F4D03F", rating: 70),
            .init(code: "civ", name: "Côte d’Ivoire", abbreviation: "CIV", primary: "#F77F00", secondary: "#FFFFFF", rating: 81),
            .init(code: "ecu", name: "Ecuador", abbreviation: "ECU", primary: "#F4D117", secondary: "#173F8A", rating: 81),
        ],
        [
            .init(code: "ned", name: "Netherlands", abbreviation: "NED", primary: "#F36C21", secondary: "#1D3557", rating: 87),
            .init(code: "jpn", name: "Japan", abbreviation: "JPN", primary: "#1B3A8A", secondary: "#FFFFFF", rating: 82),
            .init(code: "swe", name: "Sweden", abbreviation: "SWE", primary: "#F4D117", secondary: "#1769AA", rating: 80),
            .init(code: "tun", name: "Tunisia", abbreviation: "TUN", primary: "#D71920", secondary: "#FFFFFF", rating: 76),
        ],
        [
            .init(code: "bel", name: "Belgium", abbreviation: "BEL", primary: "#C8102E", secondary: "#161616", rating: 86),
            .init(code: "nzl", name: "New Zealand", abbreviation: "NZL", primary: "#F5F5F5", secondary: "#171717", rating: 72),
            .init(code: "egy", name: "Egypt", abbreviation: "EGY", primary: "#C8102E", secondary: "#FFFFFF", rating: 79),
            .init(code: "irn", name: "IR Iran", abbreviation: "IRN", primary: "#FFFFFF", secondary: "#D71920", rating: 79),
        ],
        [
            .init(code: "esp", name: "Spain", abbreviation: "ESP", primary: "#C60B1E", secondary: "#F1BF00", rating: 90),
            .init(code: "uru", name: "Uruguay", abbreviation: "URU", primary: "#6CC4E8", secondary: "#171F69", rating: 85),
            .init(code: "cpv", name: "Cabo Verde", abbreviation: "CPV", primary: "#244AA5", secondary: "#FFFFFF", rating: 73),
            .init(code: "ksa", name: "Saudi Arabia", abbreviation: "KSA", primary: "#168A55", secondary: "#FFFFFF", rating: 76),
        ],
        [
            .init(code: "fra", name: "France", abbreviation: "FRA", primary: "#183A73", secondary: "#FFFFFF", rating: 90),
            .init(code: "sen", name: "Senegal", abbreviation: "SEN", primary: "#FFFFFF", secondary: "#1C8A4A", rating: 82),
            .init(code: "irq", name: "Iraq", abbreviation: "IRQ", primary: "#168A55", secondary: "#FFFFFF", rating: 74),
            .init(code: "nor", name: "Norway", abbreviation: "NOR", primary: "#C8102E", secondary: "#17365D", rating: 83),
        ],
        [
            .init(code: "arg", name: "Argentina", abbreviation: "ARG", primary: "#75AADB", secondary: "#FFFFFF", rating: 90),
            .init(code: "alg", name: "Algeria", abbreviation: "ALG", primary: "#FFFFFF", secondary: "#138A52", rating: 79),
            .init(code: "aut", name: "Austria", abbreviation: "AUT", primary: "#D71920", secondary: "#FFFFFF", rating: 82),
            .init(code: "jor", name: "Jordan", abbreviation: "JOR", primary: "#FFFFFF", secondary: "#C8102E", rating: 73),
        ],
        [
            .init(code: "por", name: "Portugal", abbreviation: "POR", primary: "#B5122B", secondary: "#176B45", rating: 88),
            .init(code: "col", name: "Colombia", abbreviation: "COL", primary: "#F4D117", secondary: "#173F8A", rating: 84),
            .init(code: "uzb", name: "Uzbekistan", abbreviation: "UZB", primary: "#FFFFFF", secondary: "#1769AA", rating: 75),
            .init(code: "cod", name: "Congo DR", abbreviation: "COD", primary: "#1769AA", secondary: "#D71920", rating: 77),
        ],
        [
            .init(code: "eng", name: "England", abbreviation: "ENG", primary: "#F5F5F5", secondary: "#172A54", rating: 89),
            .init(code: "cro", name: "Croatia", abbreviation: "CRO", primary: "#FFFFFF", secondary: "#D71920", rating: 84),
            .init(code: "gha", name: "Ghana", abbreviation: "GHA", primary: "#FFFFFF", secondary: "#161616", rating: 78),
            .init(code: "pan", name: "Panama", abbreviation: "PAN", primary: "#D71920", secondary: "#FFFFFF", rating: 74),
        ],
    ]

    private static func makeTeam(_ seed: Seed) -> ClubTeam {
        let positions = ["G", "D", "D", "D", "D", "D", "M", "M", "M", "M", "M", "M", "G", "F", "F", "F", "F", "F"]
        let players = positions.enumerated().map { index, position in
            let number = index + 1
            let roleName = position == "G" ? "Goalkeeper" : position == "D" ? "Defender" : position == "M" ? "Midfielder" : "Forward"
            let playerID = "nation:\(seed.code):\(number)"
            let variation = Double((number * 7 + seed.code.count * 3) % 7 - 3)
            return ClubPlayer(id: playerID, name: "\(seed.name) \(roleName) \(number)",
                              shortName: "\(roleName) \(number)", position: position,
                              jerseyNumber: number, rating: nil, isGenerated: true,
                              appearance: .generated(for: playerID), estimatedRating: seed.rating + variation)
        }
        return ClubTeam(id: seed.code, name: seed.name, shortName: seed.name,
                        primaryHex: seed.primary, secondaryHex: seed.secondary, players: players)
    }
}
