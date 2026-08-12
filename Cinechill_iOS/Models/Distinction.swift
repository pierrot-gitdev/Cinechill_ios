//
//  Distinction.swift
//  Cinechill_iOS
//

import SwiftUI

/// La distinction portée par le profil, lue sur la taille de la galerie.
///
/// L'échelle ne monte pas en taille mais en **permanence**, qui est ce qui
/// hiérarchise réellement une récompense : le laurier est végétal et fane, le
/// ruban est du tissu qu'on range, la médaille est frappée dans le métal et se
/// garde, la statuette se pose et s'expose, l'étoile est scellée au sol et
/// devient publique. Chaque degré rend la distinction plus difficile à défaire,
/// exactement comme une galerie qui grossit devient plus difficile à
/// reconstituer. Le dernier degré est le seul décerné pour un ensemble et non
/// pour une pièce, ce qui correspond à ce que la galerie enregistre : une vie
/// de spectateur.
///
/// Les seuils sont inchangés depuis les anciens paliers : quelques sessions
/// suffisent à passer 300, d'où un dernier degré volontairement lointain.
///
/// - Important: les noms des grandes récompenses du cinéma sont des marques
///   déposées et leurs statuettes sont protégées. Seule la *grammaire* des
///   distinctions est reprise ici, qui n'appartient à personne ; les cinq
///   objets sont dessinés pour Cinechill dans `DistinctionEmblem`.
nonisolated enum Distinction: Int, CaseIterable, Sendable {
    case selection
    case mention
    case prix
    case grandPrix
    case hommage

    static func distinction(for count: Int) -> Distinction {
        switch count {
        case ..<50: .selection
        case ..<150: .mention
        case ..<400: .prix
        case ..<900: .grandPrix
        default: .hommage
        }
    }

    /// Le nom porte son article : il est repris tel quel dans les phrases
    /// (« Le Prix dans 43 films »), sans qu'aucun appelant n'ait à le recaser.
    var label: String {
        switch self {
        case .selection: String(localized: "La Sélection", bundle: .app)
        case .mention: String(localized: "La Mention", bundle: .app)
        case .prix: String(localized: "Le Prix", bundle: .app)
        case .grandPrix: String(localized: "Le Grand Prix", bundle: .app)
        case .hommage: String(localized: "L'Hommage", bundle: .app)
        }
    }

    /// La formule de la cérémonie. Cinq verbes, et personne n'a besoin qu'on
    /// lui explique lequel est le plus haut. Tournées sans accord de genre :
    /// « retenu » aurait obligé à choisir pour l'utilisateur.
    var citation: String {
        switch self {
        case .selection: String(localized: "Tu entres dans la sélection", bundle: .app)
        case .mention: String(localized: "Le jury te remarque", bundle: .app)
        case .prix: String(localized: "Le jury te décerne", bundle: .app)
        case .grandPrix: String(localized: "Le jury te consacre", bundle: .app)
        case .hommage: String(localized: "Le jury te rend hommage", bundle: .app)
        }
    }

    /// La matière de l'objet, dite en toutes lettres à la cérémonie. C'est elle
    /// qui porte l'idée de permanence, donc l'échelle.
    var matiere: String {
        switch self {
        case .selection: String(localized: "Laurier végétal", bundle: .app)
        case .mention: String(localized: "Ruban de soie", bundle: .app)
        case .prix: String(localized: "Bronze frappé", bundle: .app)
        case .grandPrix: String(localized: "Statuette de vermeil", bundle: .app)
        case .hommage: String(localized: "Étoile scellée", bundle: .app)
        }
    }

    /// La teinte identifie la **matière**, jamais le rang : celui-ci est porté
    /// par la forme de l'emblème et par le nombre de feuilles acquises. L'écran
    /// reste donc lisible en niveaux de gris, comme partout ailleurs.
    var accent: Color {
        switch self {
        case .selection: Color(hex: 0x8C9199)   // étain
        case .mention: Color(hex: 0xA8434E)     // soie cramoisie
        case .prix: Color(hex: 0xB07A45)        // bronze frappé
        case .grandPrix: Color(hex: 0xD8B25C)   // vermeil
        case .hommage: Color(hex: 0xEFE3C4)     // or pâle
        }
    }

    var lowerBound: Int {
        switch self {
        case .selection: 0
        case .mention: 50
        case .prix: 150
        case .grandPrix: 400
        case .hommage: 900
        }
    }

    /// Nombre de films de la distinction suivante, ou `nil` au sommet.
    var nextThreshold: Int? {
        switch self {
        case .selection: 50
        case .mention: 150
        case .prix: 400
        case .grandPrix: 900
        case .hommage: nil
        }
    }

    var next: Distinction? { Distinction(rawValue: rawValue + 1) }

    func progress(count: Int) -> Double {
        guard let next = nextThreshold else { return 1 }
        let span = Double(next - lowerBound)
        guard span > 0 else { return 1 }
        return min(1, max(0, Double(count - lowerBound) / span))
    }

    func remainingText(count: Int) -> String? {
        guard let next = nextThreshold, let following = self.next else { return nil }
        let missing = max(0, next - count)
        return missing == 1
            ? String(localized: "\(following.label) dans \(missing) film", bundle: .app)
            : String(localized: "\(following.label) dans \(missing) films", bundle: .app)
    }

    // MARK: - La couronne

    /// Vingt feuilles par branche, quarante en tout, à chaque degré.
    ///
    /// Le compte est constant mais l'écart entre deux seuils grandit : une
    /// feuille vaut 1,25 film à la Sélection et 12,5 au Grand Prix. La couronne
    /// pousse vite au début, puis se mérite — c'est ce qui remplace la jauge,
    /// et c'est là que se joue la progression.
    static let leavesPerBranch = 20

    /// Feuilles acquises **par branche**, de 0 à `leavesPerBranch`. Au sommet la
    /// couronne est pleine : il n'y a plus rien à garnir.
    func acquiredLeaves(count: Int) -> Int {
        guard nextThreshold != nil else { return Self.leavesPerBranch }
        return Int((progress(count: count) * Double(Self.leavesPerBranch)).rounded())
    }
}

/// Le millésime d'une citation, dans l'écriture des plaques de cérémonie et
/// des génériques de fin.
///
/// Le mois reste en chiffres arabes : une date entièrement romaine ne se lit
/// pas d'un coup d'œil, et le palmarès est une liste qu'on parcourt.
nonisolated enum Millesime {
    static func roman(_ year: Int) -> String {
        let table: [(Int, String)] = [
            (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
            (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
            (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")
        ]
        var rest = max(0, year)
        var out = ""
        for (value, glyph) in table {
            while rest >= value {
                out += glyph
                rest -= value
            }
        }
        return out
    }

    /// « 04 · MMXXVI ». Calendrier et fuseau courants : la date d'obtention est
    /// celle que l'utilisateur a vécue, pas celle du serveur.
    static func citation(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        let month = String(format: "%02d", parts.month ?? 1)
        return "\(month) · \(roman(parts.year ?? 0))"
    }
}

nonisolated extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
