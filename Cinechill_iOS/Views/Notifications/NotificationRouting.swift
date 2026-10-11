//
//  NotificationRouting.swift
//  Cinechill_iOS
//

import SwiftUI

extension EnvironmentValues {
    /// L'onglet qui porte cette vue est-il celui qu'on voit ? Les cinq onglets
    /// restent montés : sans ce signal, les cinq en-têtes ouvriraient leur
    /// panneau à la même demande.
    @Entry var isSelectedTab: Bool = true
}

/// Ce qu'une notification ouvre par-dessus les onglets.
enum NotificationSheet: Identifiable, Equatable {
    case item(MediaItem, asksVerdict: Bool)
    case profile(uid: String)
    case followers

    var id: String {
        switch self {
        case .item(let item, let asksVerdict): "item-\(item.id)-\(asksVerdict)"
        case .profile(let uid): "profile-\(uid)"
        case .followers: "followers"
        }
    }
}

/// Le contenu de la feuille, dans sa propre pile de navigation : une fiche
/// ouverte d'ici peut mener à une saga, un profil à sa liste d'abonnés.
struct NotificationSheetContent: View {
    let sheet: NotificationSheet

    var body: some View {
        NavigationStack {
            switch sheet {
            case .item(let item, let asksVerdict):
                if item.mediaType == .movie {
                    FilmDetailView(item: item, asksVerdict: asksVerdict)
                } else {
                    ItemDetailView(item: item)
                }
            case .profile(let uid):
                NotificationProfileView(uid: uid)
            case .followers:
                FollowListView(mode: .followers)
            }
        }
        .background(Ink.ground.ignoresSafeArea())
    }
}
