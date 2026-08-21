//
//  LovePickerView.swift
//  Cinechill_iOS
//

import SwiftUI

/// La planche des coups de cœur — le rattrapage de l'artéfact du Cœur.
///
/// Le second cran du deck pose les cœurs au fil de l'eau, mais il ne sert que
/// les films que Découvrir présente. Cette planche garantit qu'on peut finir :
/// la galerie en grille, du plus récent au plus ancien, un appui pose ou retire
/// le cœur, le compteur monte en direct. Pas de bouton valider — chaque appui
/// écrit.
///
/// **Une affiche sans cœur n'est pas grisée.** L'absence de cœur ne veut pas
/// dire « je n'ai pas aimé », elle veut dire « je ne l'ai pas dit » — le même
/// principe que le balayage gauche du deck, et la raison pour laquelle rien ici
/// ne ressemble à un tri en deux camps.
struct LovePickerView: View {
    /// Le seuil de l'artéfact, tel que le serveur le mesure.
    let target: Int
    let onClose: () -> Void

    @EnvironmentObject private var libraryStore: LibraryStore

    private var lovedCount: Int { libraryStore.lovedCount }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                    spacing: 10
                ) {
                    ForEach(libraryStore.galleryItems) { entry in
                        tile(entry)
                    }
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }

            floor
        }
        .background(Ink.ground)
    }

    // MARK: - L'en-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image("ArtefactCoeur")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)
                    .shadow(color: Color(hex: 0xFF6B7E).opacity(0.35), radius: 8)

                VStack(alignment: .leading, spacing: 5) {
                    Text("L'artéfact du Cœur", bundle: .app)
                        .planLabel()
                        .foregroundStyle(Color(hex: 0xC25562))
                    Text("Lesquels t'ont marqué ?", bundle: .app)
                        .planTitle(26)
                        .foregroundStyle(Ink.ink)
                }

                Spacer(minLength: 0)

                Button {
                    onClose()
                } label: {
                    CloseGlyph()
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle().inset(by: -8))
                }
                .buttonStyle(PressableScaleStyle(scale: 0.9))
                .accessibilityLabel(String(localized: "Fermer", bundle: .app))
            }

            Text("Un appui suffit. Ce que tu laisses de côté ne compte pas contre toi, on ne saura simplement rien de plus.", bundle: .app)
                .font(.system(size: 13))
                .foregroundStyle(Ink.ink2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            HStack(spacing: 12) {
                gaugeRule
                Text(String(localized: "\(min(lovedCount, target)) sur \(target)", bundle: .app))
                    .planLabel()
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink3)
                    .contentTransition(.numericText())
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 22)
        .animation(Metrics.shift, value: lovedCount)
    }

    /// La jauge tracée, en cramoisi : la couleur de données du Cœur.
    private var gaugeRule: some View {
        let fraction = target > 0 ? min(1, Double(lovedCount) / Double(target)) : 0
        let tint = Color(hex: 0xC25562)

        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Ink.rule).frame(height: 1)
                Rectangle()
                    .fill(tint)
                    .frame(width: max(1, proxy.size.width * fraction), height: 1)
                if fraction > 0, fraction < 1 {
                    Rectangle()
                        .fill(tint)
                        .frame(width: 1, height: 5)
                        .offset(x: max(0, proxy.size.width * fraction - 0.5))
                }
            }
            .frame(height: 5)
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    // MARK: - La grille

    private func tile(_ entry: GalleryEntry) -> some View {
        let loved = libraryStore.isLoved(entry.mediaItem)
        let isPending = libraryStore.pendingLoveByItemID[entry.id] != nil

        return Button {
            Haptics.impact(.light, intensity: loved ? 0.5 : 0.8)
            libraryStore.setLove(entry.mediaItem, loved: !loved)
        } label: {
            PosterFrame(posterPath: entry.posterPath, title: entry.title)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                        .strokeBorder(
                            loved ? Color(hex: 0xC25562) : Ink.rule,
                            lineWidth: 1
                        )
                )
                .overlay(alignment: .bottomTrailing) {
                    if loved {
                        Image("ArtefactCoeur")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .shadow(color: Ink.ground.opacity(0.8), radius: 3)
                            .padding(4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                // L'attente reste lisible tuile par tuile, sans rien promettre.
                .opacity(isPending ? 0.7 : 1)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.93))
        .animation(Metrics.shift, value: loved)
        .accessibilityLabel(entry.title)
        .accessibilityValue(
            loved
                ? String(localized: "coup de cœur", bundle: .app)
                : String(localized: "rien déclaré", bundle: .app)
        )
        .accessibilityHint(String(localized: "Toucher pour changer", bundle: .app))
    }

    // MARK: - Le plancher

    private var floor: some View {
        VStack(spacing: 0) {
            PlanEdge()

            Group {
                if lovedCount >= target {
                    Text("L'artéfact du Cœur est allumé.", bundle: .app)
                        .foregroundStyle(Color(hex: 0xF0B3BC))
                } else {
                    Text("Encore \(target - lovedCount) et l'artéfact s'allume.", bundle: .app)
                        .foregroundStyle(Ink.ink3)
                }
            }
            .font(.system(size: 12.5))
            .monospacedDigit()
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
        .background(Ink.ground)
        .animation(Metrics.shift, value: lovedCount)
    }
}

/// La croix de fermeture, dans l'écriture « La Gravure » : cercle tracé, croix
/// de 1,5 aux extrémités rondes — le symbole système n'aurait ni la graisse ni
/// les terminaisons du reste de l'écran.
private struct CloseGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Ink.ruleSet, lineWidth: 1)
            CloseCross()
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .foregroundStyle(Ink.ink2)
                .padding(9)
        }
        .accessibilityHidden(true)
    }
}

private struct CloseCross: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

#Preview("Les coups de cœur") {
    LovePickerView(target: 12, onClose: {})
        .environmentObject(LibraryStore())
}
