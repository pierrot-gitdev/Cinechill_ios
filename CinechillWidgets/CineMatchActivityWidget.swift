//
//  CineMatchActivityWidget.swift
//  CinechillWidgets
//

import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

/// L'activité « en cours » d'un film lancé depuis CinéMatch : écran verrouillé
/// et Dynamic Island. Direction retenue le 2 oct. 2026, « 1C » : la signature
/// de l'app en tête, le plan de la salle en filigrane, l'affiche et le titre.
///
/// Ni progression, ni heure de fin : on ne sait pas où la personne en est, et
/// une pause suffirait à rendre l'une ou l'autre fausse.
struct CineMatchActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CineMatchActivityAttributes.self) { context in
            ActivityLockScreenView(context: context)
                .activityBackgroundTint(CinechillPalette.night)
                .activitySystemActionForegroundColor(ActivityInk.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivitySignature()
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityStatus(context: context)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityFilmRow(
                        attributes: context.attributes,
                        posterFileName: context.state.posterFileName,
                        posterWidth: 48,
                        titleSize: 20
                    )
                    .padding(.horizontal, 6)
                    .padding(.top, 8)
                }
            } compactLeading: {
                CinechillMarkOutline()
                    .foregroundStyle(ActivityInk.ink)
                    .frame(width: 22, height: 22)
                    .accessibilityLabel(Text(verbatim: "Cinechill"))
            } compactTrailing: {
                ActivityPoster(fileName: context.state.posterFileName)
                    .frame(width: 23, height: 23)
            } minimal: {
                CinechillMarkOutline()
                    .foregroundStyle(ActivityInk.ink)
                    .frame(width: 22, height: 22)
                    .accessibilityLabel(Text(verbatim: "Cinechill"))
            }
        }
    }
}

// MARK: - L'écran verrouillé

private struct ActivityLockScreenView: View {
    let context: ActivityViewContext<CineMatchActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ActivitySignature()
                Spacer(minLength: 8)
                ActivityStatus(context: context)
            }
            ActivityFilmRow(
                attributes: context.attributes,
                posterFileName: context.state.posterFileName,
                posterWidth: 60,
                titleSize: 22
            )
        }
        .padding(16)
        .background(alignment: .topTrailing) {
            // Le plan de la salle du logo, coupé par le bord : l'identité tient
            // au dessin de l'app, pas à un symbole ajouté.
            CinechillPlanOutline()
                .foregroundStyle(ActivityInk.ink.opacity(0.16))
                .frame(width: 190, height: 190)
                .offset(x: 30, y: -24)
                .accessibilityHidden(true)
        }
        .clipped()
    }
}

// MARK: - Les pièces

/// Le bandeau de l'écran de connexion, à l'identique : le C et le nom.
private struct ActivitySignature: View {
    var body: some View {
        HStack(spacing: 8) {
            CinechillMarkOutline()
                .frame(width: 18, height: 18)
            Text(verbatim: "Cinechill")
                .activityLabel()
        }
        .foregroundStyle(ActivityInk.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Cinechill"))
    }
}

/// « En cours », puis « Ce soir » une fois la durée du film passée : au-delà,
/// on ne peut plus affirmer qu'il tourne.
private struct ActivityStatus: View {
    let context: ActivityViewContext<CineMatchActivityAttributes>

    var body: some View {
        Text(verbatim: context.isStale ? context.attributes.staleLabel : context.attributes.playingLabel)
            .activityLabel()
            .foregroundStyle(ActivityInk.ink2)
    }
}

private struct ActivityFilmRow: View {
    let attributes: CineMatchActivityAttributes
    let posterFileName: String?
    let posterWidth: CGFloat
    let titleSize: CGFloat

    var body: some View {
        HStack(spacing: 14) {
            ActivityPoster(fileName: posterFileName)
                .frame(width: posterWidth, height: posterWidth * 1.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: attributes.title)
                    .font(.system(size: titleSize, weight: .regular, design: .serif))
                    .foregroundStyle(ActivityInk.paper)
                    .lineLimit(2)
                if !attributes.details.isEmpty {
                    Text(verbatim: attributes.details)
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(ActivityInk.ink3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// L'affiche déposée par l'app dans le conteneur partagé. Tant qu'elle n'est
/// pas arrivée, sa place est tenue, pour que rien ne bouge à son arrivée.
private struct ActivityPoster: View {
    let fileName: String?

    var body: some View {
        // Une surface souple d'abord, l'image en calque : c'est le cadre de
        // l'appelant qui fixe la taille, et le rognage s'y tient. Une image en
        // `scaledToFill` posée seule débordait de son cadre (23 × 34,5 dans
        // l'îlot compact).
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    CinechillPalette.nightFloat
                }
            }
        // `Metrics.radius`, le seul rayon de l'app, que l'extension ne voit pas.
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .accessibilityHidden(true)
    }

    private var image: UIImage? {
        guard let fileName, let url = CineMatchActivityStore.posterURL(named: fileName) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

// MARK: - Les encres

/// Les encres de l'app (`Ink`, dans `CinechillDesign.swift`), recopiées :
/// ce fichier-là tire tout le design system et n'entre pas dans l'extension.
/// À tenir ensemble.
private enum ActivityInk {
    static let paper = Color(hex: 0xF3F0E8)
    static let ink = Color(hex: 0xDCD8CD)
    static let ink2 = Color(hex: 0xBCB7A4)
    static let ink3 = Color(hex: 0x8A8678)
}

private extension View {
    /// `planLabel()` de l'app, recopié pour la même raison.
    func activityLabel() -> some View {
        font(.system(size: 10, weight: .semibold))
            .tracking(1.8)
            .textCase(.uppercase)
    }
}
