//
//  Distinction.swift
//  Cinechill_iOS
//

import SwiftUI

/// La distinction portée par le profil, lue sur la taille de la galerie.
///
/// L'échelle monte par **l'autorité qui décerne**. Un jury de festival remarque
/// un film ; le même jury distingue un interprète ; l'académie française
/// récompense ; Cannes consacre ; Hollywood couronne. Chaque degré élargit le
/// cercle de ceux qui ont eu à se prononcer, ce qui est exactement ce qui rend
/// une récompense plus difficile à obtenir que la précédente.
///
/// Les seuils sont inchangés depuis les anciens paliers : quelques sessions
/// suffisent à passer 300, d'où un dernier degré volontairement lointain.
///
/// - Note: « César », « Palme d'or » et « Oscar » sont des marques déposées.
///   Leur emploi ici est une décision produit prise le 13 août 2026, en
///   connaissance de cause : ce sont les seuls noms qui portent une hiérarchie
///   que personne n'a besoin d'apprendre. Les emblèmes de `DistinctionEmblem`
///   sont en revanche des dessins originaux, et non des reproductions des
///   statuettes, qui sont elles aussi protégées.
nonisolated enum Distinction: Int, CaseIterable, Sendable {
    case mention
    case interpretation
    case cesar
    case palme
    case oscar

    static func distinction(for count: Int) -> Distinction {
        switch count {
        case ..<50: .mention
        case ..<150: .interpretation
        case ..<400: .cesar
        case ..<900: .palme
        default: .oscar
        }
    }

    /// Le nom porte son article : il est repris tel quel dans les phrases
    /// (« Le César dans 43 films »), sans qu'aucun appelant n'ait à le recaser.
    var label: String {
        switch self {
        case .mention: String(localized: "La Mention spéciale", bundle: .app)
        case .interpretation: String(localized: "Le Prix d'interprétation", bundle: .app)
        case .cesar: String(localized: "Le César", bundle: .app)
        case .palme: String(localized: "La Palme d'or", bundle: .app)
        case .oscar: String(localized: "L'Oscar", bundle: .app)
        }
    }

    /// La formule de la cérémonie, qui nomme l'autorité. Cinq degrés
    /// d'audience, et personne n'a besoin qu'on lui explique lequel est le plus
    /// haut. Tournées sans accord de genre : « retenu » aurait obligé à choisir
    /// pour l'utilisateur.
    var citation: String {
        switch self {
        case .mention: String(localized: "Le jury te remarque", bundle: .app)
        case .interpretation: String(localized: "Le jury te distingue", bundle: .app)
        case .cesar: String(localized: "L'académie te récompense", bundle: .app)
        case .palme: String(localized: "Cannes te consacre", bundle: .app)
        case .oscar: String(localized: "Hollywood te couronne", bundle: .app)
        }
    }

    /// La matière de l'objet, dite en toutes lettres à la cérémonie. Elle donne
    /// à chaque degré une identité qu'un nom seul ne porte pas.
    var matiere: String {
        switch self {
        case .mention: String(localized: "Ruban de soie", bundle: .app)
        case .interpretation: String(localized: "Masque de scène", bundle: .app)
        case .cesar: String(localized: "Compression de bronze", bundle: .app)
        case .palme: String(localized: "Or sur cristal", bundle: .app)
        case .oscar: String(localized: "Métal plaqué or", bundle: .app)
        }
    }

    /// La teinte identifie la **matière**, jamais le rang : celui-ci est porté
    /// par la forme de l'emblème et par le nombre de feuilles acquises. L'écran
    /// reste donc lisible en niveaux de gris, comme partout ailleurs.
    var accent: Color {
        switch self {
        case .mention: Color(hex: 0xA8434E)        // soie cramoisie
        case .interpretation: Color(hex: 0x8C9199) // étain du masque
        case .cesar: Color(hex: 0xB07A45)          // bronze compressé
        case .palme: Color(hex: 0xD8B25C)          // or massif
        case .oscar: Color(hex: 0xEFE3C4)          // or pâle
        }
    }

    var lowerBound: Int {
        switch self {
        case .mention: 0
        case .interpretation: 50
        case .cesar: 150
        case .palme: 400
        case .oscar: 900
        }
    }

    /// Nombre de films de la distinction suivante, ou `nil` au sommet.
    var nextThreshold: Int? {
        switch self {
        case .mention: 50
        case .interpretation: 150
        case .cesar: 400
        case .palme: 900
        case .oscar: nil
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
    /// feuille vaut 1,25 film à la Mention et 12,5 à la Palme. La couronne
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

/// Le millésime d'une cérémonie, dans l'écriture des plaques et des génériques
/// de fin.
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
