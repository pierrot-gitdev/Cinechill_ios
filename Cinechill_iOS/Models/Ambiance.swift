//
//  Ambiance.swift
//  Cinechill_iOS
//

import Foundation

/// Où chaque ambiance se situe dans l'espace du goût, et ce qu'on en dit.
///
/// Cette table existait déjà, mais à l'envers : elle servait à retrouver
/// l'ambiance *la plus proche* d'un point posé sur un cadran valence × activation.
/// Le cadran demandait de situer son propre état sur deux dimensions abstraites —
/// un geste que personne ne fait spontanément, et dont on ne voyait pas le rapport
/// avec un film. L'ambiance recherchée, elle, se demande directement. La table est
/// donc devenue le point de départ au lieu d'être l'arrivée d'un calcul, et les
/// coefficients n'ont pas bougé : ce qui était juste le reste.
nonisolated extension Mood {
    /// La position de l'ambiance sur les cinq axes qu'elle détermine réellement.
    ///
    /// Les trois autres — découverte, complexité, durée — n'en découlent pas :
    /// une comédie peut être limpide ou retorse, connue ou confidentielle. Le
    /// cadran prétendait pourtant les déduire, avec des précisions faibles mais
    /// non nulles ; il déposait donc du bruit sur des axes qu'il ne mesurait pas.
    /// On ne dit plus rien sur ces trois-là, et les questions adaptatives s'en
    /// chargent — c'est exactement leur rôle.
    var axisAnchor: (charge: Double, rythme: Double, ton: Double, ancrage: Double, echelle: Double) {
        switch self {
        case .lightFun: (charge: -0.7, rythme: 0.1, ton: 0.8, ancrage: 0.1, echelle: -0.2)
        case .intense: (charge: 0.4, rythme: 0.9, ton: -0.3, ancrage: 0.2, echelle: 0.5)
        case .emotional: (charge: 0.8, rythme: -0.4, ton: 0.4, ancrage: -0.6, echelle: -0.6)
        case .scary: (charge: 0.6, rythme: 0.6, ton: -0.7, ancrage: 0.3, echelle: -0.2)
        case .escapist: (charge: -0.3, rythme: 0.6, ton: 0.2, ancrage: 0.9, echelle: 0.9)
        case .thoughtful: (charge: 0.3, rythme: -0.7, ton: -0.2, ancrage: 0.1, echelle: -0.3)
        }
    }

    /// Ce qu'on va chercher, dit en une ligne juste après le choix. C'est la
    /// première fois du parcours que l'application répond quelque chose.
    var reading: String {
        switch self {
        case .lightFun: "On cherchera un film léger, qui fait passer un bon moment."
        case .intense: "On cherchera un film tendu, avec du rythme."
        case .emotional: "On cherchera un film qui touche."
        case .scary: "On cherchera un film qui fait peur."
        case .escapist: "On cherchera un film spectaculaire, qui fait voyager."
        case .thoughtful: "On cherchera un film qui donne à réfléchir."
        }
    }
}
