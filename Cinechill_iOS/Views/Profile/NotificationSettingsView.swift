//
//  NotificationSettingsView.swift
//  Cinechill_iOS
//

import SwiftUI
import UIKit

/// Réglages › Notifications.
///
/// Quatre interrupteurs, chacun avec la ligne qui dit quand il sonne. Au-dessus,
/// seulement si c'est le cas, ce qu'iOS empêche : des notifications coupées dans
/// les réglages de l'iPhone, ou reçues sans bruit (l'autorisation provisoire de
/// la fin de l'onboarding). Les interrupteurs restent actifs dans les deux cas :
/// ce sont des choix, qu'iOS appliquera le jour où il laissera passer.
///
/// « Recommandations et abonnés » vit sur le serveur, qui envoie ces
/// notifications-là ; les trois autres vivent sur l'appareil, qui les programme.
struct NotificationSettingsView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var permission = NotificationPermission.shared
    @State private var social = true
    @State private var afterFilm = NotificationPreference.afterFilm.isOn
    @State private var reminders = NotificationPreference.reminders.isOn
    @State private var tonight = NotificationPreference.tonight.isOn
    @State private var isAsking = false

    var body: some View {
        ZStack {
            Ink.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                PlanHeader(String(localized: "Notifications", bundle: .app))

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        systemState

                        row(
                            String(localized: "Recommandations et abonnés", bundle: .app),
                            note: String(localized: "Un film qu'on te recommande, ta recommandation ajoutée ou regardée, un nouvel abonné.", bundle: .app),
                            isOn: Binding(
                                get: { social },
                                set: { value in
                                    social = value
                                    libraryStore.setSocialNotifications(value)
                                }
                            )
                        )
                        row(
                            String(localized: "Ton avis sur un film", bundle: .app),
                            note: String(localized: "Le lendemain d'un « Je le regarde », à 19 h, on te demande si le film t'a plu.", bundle: .app),
                            isOn: $afterFilm
                        )
                        row(
                            String(localized: "En attendant CinéMatch", bundle: .app),
                            note: String(localized: "Si tu n'ouvres pas l'app pendant trois jours, on te dit ce qu'il te reste pour ouvrir CinéMatch.", bundle: .app),
                            isOn: $reminders
                        )
                        row(
                            String(localized: "Une idée pour ce soir", bundle: .app),
                            note: String(localized: "Le lundi et le mercredi à 20 h, une fois CinéMatch ouvert.", bundle: .app),
                            isOn: $tonight,
                            isLast: true
                        )
                    }
                    .padding(.horizontal, Metrics.margin)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await permission.refresh()
            if let stored = await libraryStore.socialNotificationsEnabled() {
                social = stored
            }
        }
        // Revenu des réglages de l'iPhone : l'état a pu changer là-bas.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await permission.refresh() }
        }
        .onChange(of: afterFilm) { _, value in
            NotificationPreference.afterFilm.set(value)
            if !value { LocalReminders.cancelVerdict() }
        }
        .onChange(of: reminders) { _, value in
            NotificationPreference.reminders.set(value)
            if !value { LocalReminders.cancelNudges() }
        }
        .onChange(of: tonight) { _, value in
            NotificationPreference.tonight.set(value)
            // La Porte connue de l'appareil : « Ce soir ? » ne part que si
            // CinéMatch est ouvert, et se reprogramme à chaque départ de l'app.
            let doorOpen = DoorState.cached?.unlocked == true
            Task { await LocalReminders.scheduleTonight(doorOpen: doorOpen) }
        }
    }

    // MARK: - Ce qu'iOS permet

    @ViewBuilder
    private var systemState: some View {
        switch permission.status {
        case .denied:
            notice(
                String(localized: "Tes notifications sont coupées dans les réglages de l'iPhone. Tes choix ci-dessous s'appliqueront dès que tu les réactiveras.", bundle: .app),
                action: String(localized: "Ouvrir les réglages", bundle: .app)
            ) {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            }
        case .provisional:
            notice(
                String(localized: "Tes notifications arrivent sans son ni bannière, seulement dans le centre de notifications.", bundle: .app),
                action: String(localized: "Activer le son et les bannières", bundle: .app),
                perform: askForFull
            )
        case .notDetermined:
            notice(
                String(localized: "Tu n'as pas encore autorisé les notifications.", bundle: .app),
                action: String(localized: "Autoriser les notifications", bundle: .app),
                perform: askForFull
            )
        default:
            EmptyView()
        }
    }

    private func askForFull() {
        Task {
            isAsking = true
            await permission.requestFull()
            isAsking = false
        }
    }

    /// Une remarque, comme sur la fiche film : le point, une ligne, et
    /// l'action qui y répond.
    private func notice(_ text: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                PlanLight(tint: Ink.warn)
                Text(text)
                    .planFont(13.5)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            PlanSecondaryButton(title: action, isEnabled: !isAsking, height: Metrics.control, action: perform)
        }
        .padding(.top, 22)
        .padding(.bottom, 4)
    }

    // MARK: - Un interrupteur

    private func row(_ title: String, note: String, isOn: Binding<Bool>, isLast: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .planFont(15, weight: .medium)
                        .foregroundStyle(Ink.ink)
                    Text(note)
                        .planFont(12)
                        .foregroundStyle(Ink.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Ink.light)
            .padding(.top, 22)

            if !isLast {
                PlanEdge().padding(.top, 22)
            }
        }
    }
}
