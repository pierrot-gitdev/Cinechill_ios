//
//  BlockedAccountsView.swift
//  Cinechill_iOS
//

import SwiftUI
import UIKit

/// Les comptes bloqués, avec de quoi les débloquer.
///
/// Même grille que `FollowListView` (avatar de 38, nom, pseudo, une action à
/// droite) : c'est une liste de personnes du Hall, rien ne justifiait un
/// second dessin. L'action, elle, ne se confirme pas : débloquer ne défait
/// rien, il faudra de toute façon se suivre à nouveau.
struct BlockedAccountsView: View {
    /// Chevron dans une pile de navigation, croix dans une feuille.
    var leading: PlanHeaderLeading = .back

    @EnvironmentObject private var socialStore: SocialStore

    @State private var profiles: [PublicProfile] = []
    @State private var isLoading = true
    /// Un échec de lecture, à distinguer d'une liste vraiment vide : sans
    /// réseau, « Aucun compte bloqué » serait faux.
    @State private var loadError: String?
    @State private var filter = ""
    @State private var errorMessage: String?

    private var filtered: [PublicProfile] {
        let needle = SocialStore.normalize(filter)
        guard !needle.isEmpty else { return profiles }
        return profiles.filter {
            SocialStore.normalize($0.displayName).contains(needle)
                || SocialStore.normalize($0.handle).contains(needle)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isLoading {
                    loading
                } else if let loadError {
                    HallEmptyState(
                        icon: .salle,
                        title: String(localized: "Liste indisponible", bundle: .app),
                        message: loadError,
                        actionTitle: String(localized: "Réessayer", bundle: .app),
                        action: { Task { await load() } }
                    )
                    .padding(.top, 44)
                } else if profiles.isEmpty {
                    HallEmptyState(
                        icon: .salle,
                        title: String(localized: "Aucun compte bloqué", bundle: .app),
                        message: String(localized: "Les profils que tu bloques s'affichent ici, avec de quoi les débloquer.", bundle: .app)
                    )
                    .padding(.top, 44)
                } else {
                    Text("Un profil bloqué ne peut plus te suivre ni t'envoyer de films. Le débloquer ne rétablit pas les abonnements.", bundle: .app)
                        .planFont(12)
                        .foregroundStyle(Ink.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Metrics.margin)
                        .padding(.top, 16)
                        .padding(.bottom, 10)

                    if profiles.count > 8 {
                        HallSearchField(placeholder: String(localized: "Filtrer", bundle: .app), text: $filter)
                            .padding(.horizontal, 18)
                            .padding(.top, 4)
                            .padding(.bottom, 12)
                    }

                    rows
                }
            }
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Ink.ground)
        .safeAreaInset(edge: .top) {
            PlanHeader(String(localized: "Comptes bloqués", bundle: .app), leading: leading) {
                if !profiles.isEmpty {
                    PlanHeaderCount(value: profiles.count.formatted(.number.locale(AppLanguage.current.locale)))
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .alert(
            errorMessage ?? "",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(String(localized: "OK", bundle: .app), role: .cancel) { errorMessage = nil }
        }
    }

    // MARK: - Contenu

    @ViewBuilder
    private var rows: some View {
        if filtered.isEmpty {
            Text("Aucun compte bloqué ne correspond.", bundle: .app)
                .planFont(13)
                .foregroundStyle(Ink.ink2)
                .padding(.horizontal, Metrics.margin)
                .padding(.top, 18)
        }
        ForEach(filtered) { profile in
            BlockedAccountRow(
                profile: profile,
                isBusy: socialStore.blocksInFlight.contains(profile.id)
            ) {
                Task { await unblock(profile) }
            }
            .padding(.horizontal, 18)
            .transition(.opacity)

            Divider().padding(.leading, 66)
        }
    }

    private var loading: some View {
        HStack {
            Spacer()
            CinechillSpinner(size: 26)
            Spacer()
        }
        .padding(.top, 60)
    }

    // MARK: - Chargement

    private func load() async {
        // Au retour sur l'écran, la liste déjà là reste affichée pendant la
        // relecture : pas de roue sur une liste qu'on vient de voir.
        if profiles.isEmpty { isLoading = true }
        loadError = nil
        defer { isLoading = false }
        do {
            profiles = try await socialStore.blockedAccounts()
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch is CancellationError {
            return
        } catch {
            profiles = []
            loadError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// La ligne part une fois le serveur d'accord, jamais avant.
    private func unblock(_ profile: PublicProfile) async {
        do {
            try await socialStore.unblock(uid: profile.id)
        } catch is CancellationError {
            return
        } catch {
            Haptics.warning()
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            return
        }
        withAnimation(Metrics.shift) {
            profiles.removeAll { $0.id == profile.id }
        }
    }
}

/// Une ligne de compte bloqué. Aux tailles d'accessibilité, « Débloquer »
/// passe sous le nom, comme « Suivre » dans `HallProfileRow`.
private struct BlockedAccountRow: View {
    let profile: PublicProfile
    let isBusy: Bool
    let onUnblock: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    private var isLargeType: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        HStack(alignment: isLargeType ? .top : .center, spacing: 10) {
            HallAvatar(
                seed: profile.id,
                initial: profile.initials,
                url: profile.avatarURL,
                size: 38
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .planFont(14, weight: .medium)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(isLargeType ? 3 : 1)
                // Un compte sans pseudo n'a pas de seconde ligne : « @ » seul
                // ressemblait à une donnée cassée.
                if !profile.handle.isEmpty {
                    Text(verbatim: profile.handleDisplay)
                        .planFont(11.5)
                        .foregroundStyle(Ink.ink2)
                        .lineLimit(1)
                }

                if isLargeType {
                    button.padding(.top, 6)
                }
            }

            Spacer(minLength: 6)

            if !isLargeType {
                button
            }
        }
        .padding(.vertical, 10)
    }

    /// Le contour de « Suivi » : une action de second rang, qui ne doit pas
    /// tirer l'œil sur une liste où chaque ligne la porte.
    private var button: some View {
        Button(action: onUnblock) {
            Group {
                if isBusy {
                    CinechillSpinner(size: 13)
                } else {
                    Text("Débloquer", bundle: .app)
                        .planFont(12.5)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(Ink.ink2)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(Ink.ruleSet, lineWidth: 1)
            )
            // 29 pt dessinés, 45 pt de cible : le débord ne bouge pas la ligne.
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .padding(.vertical, -8)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.94))
        .disabled(isBusy)
        .accessibilityLabel(String(localized: "Débloquer \(profile.displayName)", bundle: .app))
    }
}

// MARK: - Le contact

/// L'adresse où écrire, à poser dans les réglages. La règle 1.2 de l'App
/// Store demande un moyen de joindre l'équipe à toute app où des gens se
/// croisent.
///
/// L'adresse est affichée en entier et sélectionnable : sans app Mail
/// configurée, le bouton ne peut rien ouvrir, et il copie alors l'adresse.
struct ContactRow: View {
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    /// Pas une chaîne traduite : une `static let` ne pose ici aucun problème.
    private static let address = "pierrerobrt@gmail.com"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlanSectionLabel(
                title: String(localized: "Contact", bundle: .app),
                note: String(localized: "Une question, un problème avec un profil : on te répond à cette adresse.", bundle: .app)
            )
            .padding(.bottom, 14)

            Text(verbatim: Self.address)
                .planFont(15)
                .foregroundStyle(Ink.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .textSelection(.enabled)

            PlanSecondaryButton(
                title: copied
                    ? String(localized: "Adresse copiée", bundle: .app)
                    : String(localized: "Écrire un email", bundle: .app),
                height: Metrics.control
            ) {
                write()
            }
            .padding(.top, 14)
        }
    }

    private func write() {
        guard let url = URL(string: "mailto:\(Self.address)") else { return }
        openURL(url) { accepted in
            guard !accepted else { return }
            UIPasteboard.general.string = Self.address
            withAnimation(Metrics.shift) { copied = true }
        }
    }
}

// MARK: - Données de démonstration

#if DEBUG
extension DebugFixtures {
    /// `-debugData worst` : deux cents comptes, dont un nom de soixante
    /// caractères, un compte sans nom ni pseudo, des diacritiques, un emoji et
    /// une seule lettre. `-debugData empty` : aucun.
    ///
    /// Ici plutôt que dans `DebugFixtures.swift`, que d'autres chantiers
    /// éditent en même temps.
    static var blockedUsers: [PublicProfile]? {
        switch mode {
        case nil: nil
        case .empty: []
        case .worst: worstBlocked
        }
    }

    private static var worstBlocked: [PublicProfile] {
        let named: [(String, String?)] = [
            ("maximilien_alexandr", "Maximilien-Alexandre de La Tour d'Auvergne-Lauraguais"),
            ("", nil),
            ("thao.nguyen", "Nguyễn Thị Phương Thảo"),
            ("popcorn", "🍿🍿🍿"),
            ("a", "A"),
            ("cinephile.nocturne__", nil),
        ]
        let special = named.enumerated().map { index, entry in
            PublicProfile(
                id: "blocked-\(index)",
                handle: entry.0,
                displayName: PublicProfile.nameOrHandle(entry.1, entry.0),
                avatarURL: nil,
                badgeSignature: nil,
                followerCount: 0,
                followingCount: 0,
                galleryCount: 0
            )
        }
        let bulk = (special.count..<200).map { index in
            PublicProfile(
                id: "blocked-\(index)",
                handle: "profil\(index)",
                displayName: "Profil \(index)",
                avatarURL: nil,
                badgeSignature: nil,
                followerCount: 0,
                followingCount: 0,
                galleryCount: 0
            )
        }
        return special + bulk
    }
}
#endif
