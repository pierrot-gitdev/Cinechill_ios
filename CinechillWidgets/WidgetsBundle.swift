//
//  WidgetsBundle.swift
//  CinechillWidgets
//

import SwiftUI
import WidgetKit

/// Le point d'entrée de l'extension. Elle ne porte pour l'instant que
/// l'activité en direct de CinéMatch ; un widget d'écran d'accueil viendrait
/// s'ajouter ici.
@main
struct CinechillWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CineMatchActivityWidget()
    }
}
