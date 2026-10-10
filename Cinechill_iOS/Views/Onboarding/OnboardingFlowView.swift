//
//  OnboardingFlowView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le conteneur de l'onboarding : une page à la fois, la barre de progression
/// en haut, le bouton en bas.
///
/// Le bouton ne bouge jamais d'une page à l'autre, et c'est voulu : on avance
/// sans chercher où appuyer, comme dans Duolingo. Seule la page change, et
/// elle glisse dans le sens où l'on va.
struct OnboardingFlowView: View {
    let tour: OnboardingTour
    /// « À toi de jouer » : `MainTabView` ouvre Découvrir et retire le parcours.
    let onFinish: () -> Void

    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Ink.ground.ignoresSafeArea()

            if let step = tour.step {
                page(step)
                    .id(step)
                    .transition(pageTransition)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
    }

    @ViewBuilder
    private func page(_ step: OnboardingTour.Step) -> some View {
        switch step {
        case .welcome: OnboardingWelcomePage()
        case .cinematch: OnboardingCineMatchPage()
        case .tastes: OnboardingTastesPage()
        case .platforms: OnboardingPlatformsPage()
        case .gestures: OnboardingGesturesPage()
        }
    }

    // MARK: - Le mouvement

    /// La page qui arrive glisse d'un court pas, du côté où l'on va. Un pas
    /// et non la largeur de l'écran : on change de page, on ne change pas
    /// d'endroit.
    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let step: CGFloat = tour.movedForward ? 48 : -48
        return .asymmetric(
            insertion: .offset(x: step).combined(with: .opacity),
            removal: .offset(x: -step).combined(with: .opacity)
        )
    }

    private var pageAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .timingCurve(0.23, 1, 0.32, 1, duration: 0.36)
    }

    private func advance() {
        Haptics.selection()
        withAnimation(pageAnimation) { tour.next() }
    }

    private func goBack() {
        Haptics.selection()
        withAnimation(pageAnimation) { tour.back() }
    }

    // MARK: - La barre du haut

    @ViewBuilder
    private var topBar: some View {
        // L'accueil n'en a pas : le mur d'affiches monte jusqu'en haut.
        if let step = tour.step, step != .welcome {
            HStack(spacing: 6) {
                Button(action: goBack) {
                    OnboardingChevron()
                        .stroke(Ink.ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .frame(width: 10, height: 17)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableScaleStyle(scale: 0.9))
                .accessibilityLabel(String(localized: "Retour", bundle: .app))

                OnboardingProgressBar(progress: step.progress)
                    .accessibilityElement()
                    .accessibilityLabel(String(localized: "Progression", bundle: .app))
                    .accessibilityValue(String(localized: "Étape \(step.rawValue) sur \(OnboardingTour.Step.allCases.count - 1)", bundle: .app))
            }
            .padding(.leading, 6)
            .padding(.trailing, Metrics.margin)
            .frame(height: 44)
            .background(Ink.ground)
        }
    }

    // MARK: - Le bouton

    private var footer: some View {
        let step = tour.step ?? .welcome
        let isPlatforms = step == .platforms
        let hasPlatforms = !libraryStore.preferredPlatformIDs.isEmpty

        return VStack(spacing: 2) {
            PlanButton(title: ctaTitle(step), isEnabled: !isPlatforms || hasPlatforms) {
                if step == .gestures {
                    Haptics.success()
                    onFinish()
                } else {
                    advance()
                }
            }

            // Toujours à sa place sur l'écran des plateformes, éteint dès
            // qu'une plateforme est cochée : le bas ne bouge pas pendant qu'on
            // choisit.
            if isPlatforms {
                Button {
                    libraryStore.setPreferredPlatforms([])
                    advance()
                } label: {
                    Text("Je n'ai aucune plateforme", bundle: .app)
                        .planFont(13.5, weight: .medium)
                        .foregroundStyle(Ink.ink2)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hasPlatforms ? 0 : 1)
                .disabled(hasPlatforms)
                .accessibilityHidden(hasPlatforms)
                .animation(Metrics.shift, value: hasPlatforms)
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 12)
        .padding(.bottom, isPlatforms ? 0 : 8)
        .background(Ink.ground)
    }

    private func ctaTitle(_ step: OnboardingTour.Step) -> String {
        switch step {
        case .welcome: String(localized: "C'est parti", bundle: .app)
        case .gestures: String(localized: "À toi de jouer", bundle: .app)
        default: String(localized: "Continuer", bundle: .app)
        }
    }
}

// MARK: - Les pièces communes

/// La barre de progression : un trait épais, un seul rayon, qui se remplit à
/// chaque page.
struct OnboardingProgressBar: View {
    let progress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.ruleSet)
                Capsule()
                    .fill(Ink.ink)
                    .frame(width: max(0, proxy.size.width * progress))
            }
        }
        .frame(height: 4)
        .animation(reduceMotion ? nil : .timingCurve(0.32, 0.72, 0, 1, duration: 0.5), value: progress)
    }
}

/// Le chevron du retour.
struct OnboardingChevron: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

/// Le haut d'une page : un sur-titre, un titre, et un texte s'il y en a un.
struct OnboardingHeading: View {
    let eyebrow: String
    let title: String
    var text: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow)
                .planLabel()
                .foregroundStyle(Ink.ink2)

            Text(title)
                .planTitle(28)
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)

            if let text {
                Text(text)
                    .planFont(15)
                    .foregroundStyle(Ink.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// L'arrivée d'un bloc : il monte d'un pas et apparaît. Une seule fois, à
/// l'ouverture de la page.
struct OnboardingRise: ViewModifier {
    let isOn: Bool
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isOn ? 1 : 0)
            .offset(y: isOn || reduceMotion ? 0 : 10)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.5).delay(delay), value: isOn)
    }
}

extension View {
    func onboardingRise(_ isOn: Bool, delay: Double = 0) -> some View {
        modifier(OnboardingRise(isOn: isOn, delay: delay))
    }
}
