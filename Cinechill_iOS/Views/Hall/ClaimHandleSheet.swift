//
//  ClaimHandleSheet.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le choix du pseudo — la brique dont tout le reste dépend.
///
/// Sans pseudo, on n'est ni trouvable, ni suivable, ni destinataire d'une
/// recommandation : c'est la seule information du Hall qu'on ne peut pas
/// déduire du compte Firebase, et elle doit être unique.
///
/// La contrainte du changement unique est annoncée **avant** la validation,
/// pas découverte après : une règle qu'on n'apprend qu'en la heurtant est une
/// mauvaise règle.
///
/// L'écran ne dessine plus rien en propre. C'est très exactement le champ pseudo
/// de l'inscription — `PlanField`, sa note de service, son point de lumière,
/// ses trois replis quand le pseudo est pris — et il en emprunte aussi les
/// bornes, via `PlanHandle`, qui sont celles du serveur. L'ancienne version
/// avait sa propre validation, plus permissive d'un caractère : elle laissait
/// donc partir des pseudos que le serveur refusait.
struct ClaimHandleSheet: View {
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case handle }

    @State private var handle = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var isTaken = false
    @FocusState private var focus: Field?

    private var isValid: Bool { PlanHandle.isValid(handle) && !isTaken }
    private var isFirstClaim: Bool { socialStore.myProfile == nil }

    /// La saisie passe par une liaison intermédiaire : la normalisation se fait
    /// sous les doigts, jamais en reproche — une majuscule ou un accent est une
    /// faute de conception si on la signale, pas une faute de l'utilisateur.
    private var entry: Binding<String> {
        Binding(
            get: { handle },
            set: { typed in
                isTaken = false
                errorMessage = nil
                handle = PlanHandle.normalize(typed)
            }
        )
    }

    var body: some View {
        ZStack {
            Ink.ground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                PlanHeader(
                    isFirstClaim ? "Votre pseudo" : "Changer de pseudo",
                    leading: .close
                )

                VStack(alignment: .leading, spacing: 0) {
                    Text(isFirstClaim
                         ? "C'est ce que vos amis taperont pour vous retrouver."
                         : "Il ne pourra plus être changé après celui-ci.")
                        .font(.system(size: 14.5))
                        .foregroundStyle(isFirstClaim ? Ink.ink2 : Ink.warn)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 300, alignment: .leading)
                        .padding(.top, 28)

                    PlanField(
                        label: "Pseudo", text: entry, field: Field.handle, focus: $focus,
                        placeholder: "pierre.robert",
                        prefix: "@",
                        contentType: .username,
                        submitLabel: .go,
                        accessory: isValid ? .light : .none,
                        error: isTaken ? "Ce pseudo est déjà pris." : errorMessage,
                        note: isTaken ? nil : PlanHandle.rule,
                        isDisabled: isSubmitting,
                        onSubmit: { Task { await submit() } }
                    )
                    .padding(.top, 40)

                    if isTaken {
                        alternatives
                    }

                    Spacer(minLength: 24)

                    PlanButton(
                        title: isFirstClaim ? "Choisir ce pseudo" : "Changer définitivement",
                        loadingTitle: "Enregistrement…",
                        isLoading: isSubmitting,
                        isEnabled: isValid
                    ) {
                        Haptics.impact(.medium)
                        Task { await submit() }
                    }
                    .padding(.bottom, 28)
                }
                .padding(.horizontal, Metrics.margin)
            }
            .animation(Metrics.shift, value: isTaken)
        }
        .presentationDetents([.medium])
        .onAppear {
            handle = socialStore.myProfile?.handle ?? ""
            focus = .handle
        }
    }

    /// Trois replis, touchables. On ne met jamais quelqu'un devant un mur sans
    /// lui tendre une porte.
    private var alternatives: some View {
        HStack(spacing: 7) {
            ForEach(PlanHandle.alternatives(for: handle), id: \.self) { candidate in
                Button {
                    handle = candidate
                    isTaken = false
                    Haptics.selection()
                } label: {
                    Text("@\(candidate)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Ink.ink)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                                .stroke(Ink.ruleSet, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
    }

    private func submit() async {
        guard !isSubmitting, isValid else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        focus = nil
        do {
            try await socialStore.claimHandle(handle)
            Haptics.success()
            dismiss()
        } catch {
            Haptics.warning()
            withAnimation(Metrics.shift) {
                // Le cas de loin le plus fréquent est le pseudo déjà pris : il a
                // droit à ses replis plutôt qu'à un message et un cul-de-sac.
                if isAlreadyTaken(error) {
                    isTaken = true
                } else {
                    errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
    }

    private func isAlreadyTaken(_ error: Error) -> Bool {
        (error as? SocialError) == .handleTaken
    }
}
