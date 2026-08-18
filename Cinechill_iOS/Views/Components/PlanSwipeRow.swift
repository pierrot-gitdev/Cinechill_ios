//
//  PlanSwipeRow.swift
//  Cinechill_iOS
//

import SwiftUI
import UIKit

/// Ce qu'un glissement horizontal révèle au bout d'une ligne.
struct PlanRowAction {
    let label: String
    let tint: Color
    /// Point plein pour ce qui s'acquiert, creux pour ce qui se retire : le
    /// remplissage porte la différence, comme partout ailleurs.
    var isFilled: Bool = true
    let perform: () -> Void
}

// MARK: - Le panoramique qui sait se taire

/// Le panoramique horizontal de la ligne, **capable de refuser de commencer**.
///
/// C'est toute l'affaire, et c'est ce qu'un `DragGesture` ne sait pas faire.
/// Dès qu'il reconnaît, il entre en concurrence avec le panoramique de la
/// `ScrollView` qui entoure la ligne : en `.gesture` il le bat et le défilement
/// meurt, en `.simultaneousGesture` les deux se disputent le doigt. SwiftUI n'a
/// rien pour dire « ce geste ne m'intéresse que s'il est horizontal, sinon
/// laisse passer ». `gestureRecognizerShouldBegin` le dit en une ligne, et un
/// doigt qui part à la verticale ne le fait jamais commencer.
///
/// Il est posé en **surcouche**, et non en fond. Un recognizer ne reçoit que
/// les touches dont la vue atteinte est la sienne ou l'une de ses descendantes :
/// derrière le contenu il n'en recevait aucune, et le glissement ne partait
/// plus du tout. La surcouche prend donc aussi le tap, puisqu'elle est
/// désormais ce que le doigt rencontre en premier.
private struct HorizontalPan: UIViewRepresentable {
    var isEnabled: Bool = true
    /// Rapport minimal entre les deux axes pour que le geste commence.
    var dominance: CGFloat = 1.6
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void
    var onTap: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        view.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        uiView.isUserInteractionEnabled = isEnabled
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HorizontalPan

        init(_ parent: HorizontalPan) { self.parent = parent }

        @objc func handlePan(_ pan: UIPanGestureRecognizer) {
            let travel = pan.translation(in: pan.view).x
            switch pan.state {
            case .changed:
                parent.onChanged(travel)
            case .ended, .cancelled, .failed:
                parent.onEnded(travel)
            default:
                break
            }
        }

        @objc func handleTap() {
            parent.onTap?()
        }

        /// Le seul endroit qui compte : à la verticale, on ne commence pas, et
        /// la liste défile comme si ce recognizer n'existait pas.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let speed = pan.velocity(in: pan.view)
            return abs(speed.x) > abs(speed.y) * parent.dominance
        }

        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

// MARK: - La ligne

/// Une ligne qu'on tire horizontalement pour déclencher une action.
///
/// `List` a bien `swipeActions`, mais la watchlist est un `ScrollView` doublé
/// d'un `LazyVStack` : le modificateur n'existe pas en dehors d'une `List`, et
/// repasser l'écran en `List` coûterait de reprendre ses séparateurs, ses
/// marges et son fond, et donnerait aux actions le dessin du système que la
/// direction artistique a chassé partout ailleurs.
///
/// Rien n'est joué d'avance : l'action est envoyée, la ligne revient à sa
/// place, et elle disparaît quand le magasin l'a répercuté. L'application ne
/// fait pas de mises à jour optimistes, et une ligne qui s'envolerait avant la
/// confirmation devrait revenir en cas d'échec.
struct PlanSwipeRow<Content: View>: View {
    /// Révélée en tirant vers la gauche.
    var trailing: PlanRowAction?
    /// Révélée en tirant vers la droite.
    var leading: PlanRowAction?
    /// Ce que déclenche un tap franc sur la ligne. Il passe par la surcouche,
    /// qui est ce que le doigt rencontre en premier.
    var onTap: (() -> Void)?
    /// À couper quand la ligne porte ses propres boutons : la surcouche les
    /// recouvrirait.
    var isEnabled: Bool = true
    @ViewBuilder var content: () -> Content

    /// Course au-delà de laquelle l'action est acquise si le doigt se lève.
    private static var threshold: CGFloat { 88 }
    /// Au-delà du seuil la ligne résiste : elle suit encore, mais de moins en
    /// moins, et bute. C'est ce qui fait sentir qu'il n'y a rien de plus loin.
    private static var maxTravel: CGFloat { 132 }

    @State private var offset: CGFloat = 0
    @State private var isArmed = false

    var body: some View {
        ZStack {
            marker
            content()
                .background(Ink.ground)
                .offset(x: offset)
        }
        .overlay(
            HorizontalPan(
                isEnabled: isEnabled,
                onChanged: follow(_:),
                onEnded: release(_:),
                onTap: onTap
            )
        )
    }

    // MARK: - Le repère

    @ViewBuilder
    private var marker: some View {
        if let action = revealed {
            HStack(spacing: 9) {
                if action.isFilled {
                    PlanLight(tint: action.tint)
                } else {
                    PlanLightOutline(tint: action.tint)
                }
                Text(action.label)
                    .planLabel()
            }
            .foregroundStyle(action.tint)
            // Le repère se lit avant le seuil, sinon le geste se fait à
            // l'aveugle. Il s'enclenche ensuite d'un cran, comme la boussole du
            // deck : c'est un déclic, pas une apparition.
            .opacity(min(1, abs(offset) / (Self.threshold * 0.55)))
            .scaleEffect(isArmed ? 1 : 0.94)
            .animation(SwipeMotion.lock, value: isArmed)
            // Moins que la marge d'écran : au seuil, la course libère 88 points
            // et le repère doit y tenir en entier, sinon il s'arme à moitié
            // caché sous la ligne.
            .padding(.horizontal, 15)
            .frame(maxWidth: .infinity, alignment: offset < 0 ? .trailing : .leading)
        }
    }

    private var revealed: PlanRowAction? {
        if offset < 0 { return trailing }
        if offset > 0 { return leading }
        return nil
    }

    // MARK: - Le geste

    private func follow(_ travel: CGFloat) {
        // Un côté sans action ne bouge pas : la ligne ne promet rien qu'elle ne
        // tiendra.
        guard (travel < 0 && trailing != nil) || (travel > 0 && leading != nil) else {
            offset = 0
            return
        }
        offset = resisted(travel)

        let armed = abs(offset) >= Self.threshold
        if armed != isArmed {
            isArmed = armed
            if armed { Haptics.impact(.light) }
        }
    }

    private func release(_ travel: CGFloat) {
        let action = revealed
        let commits = isArmed
        isArmed = false
        withAnimation(SwipeMotion.recenter) { offset = 0 }

        if commits, let action {
            Haptics.success()
            action.perform()
        }
    }

    private func resisted(_ raw: CGFloat) -> CGFloat {
        let magnitude = abs(raw)
        guard magnitude > Self.threshold else { return raw }
        let damped = Self.threshold + (magnitude - Self.threshold) * 0.35
        return min(damped, Self.maxTravel) * (raw < 0 ? -1 : 1)
    }
}

#Preview("Une ligne tirée") {
    ZStack {
        Ink.ground.ignoresSafeArea()
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<12, id: \.self) { index in
                    PlanSwipeRow(
                        trailing: PlanRowAction(label: "Vu", tint: Ink.ink) {},
                        leading: PlanRowAction(label: "Retirer", tint: Ink.warn, isFilled: false) {}
                    ) {
                        HStack {
                            Text(verbatim: "Film \(index + 1)")
                                .font(.system(size: 13.5))
                                .foregroundStyle(Ink.ink)
                            Spacer()
                        }
                        .padding(.horizontal, Metrics.margin)
                        .padding(.vertical, 16)
                    }
                    PlanEdge()
                }
            }
        }
    }
}
