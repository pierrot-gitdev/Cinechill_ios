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
struct ClaimHandleSheet: View {
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(\.dismiss) private var dismiss

    @State private var handle = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var normalized: String {
        handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Mêmes bornes que `isValidHandle` côté serveur : refuser ici évite un
    /// aller-retour pour dire ce qu'on savait déjà.
    private var hasValidLength: Bool {
        (3...20).contains(normalized.count)
    }

    private var hasValidCharacters: Bool {
        guard !normalized.isEmpty else { return false }
        return normalized.allSatisfy { character in
            character.isNumber
                || character == "_"
                || character == "."
                || character == "-"
                || (character.isLetter && character.isLowercase)
        }
    }

    private var isValid: Bool { hasValidLength && hasValidCharacters }

    private var isFirstClaim: Bool { socialStore.myProfile == nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CinechillHallIconView(.salle)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(CinechillPalette.light)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(isFirstClaim ? "Votre pseudo" : "Changer de pseudo")
                            .font(.system(size: 21, weight: .heavy, design: .rounded))
                        Text(isFirstClaim
                            ? "C'est ce que vos amis taperont pour vous retrouver."
                            : "Attention : le pseudo ne peut être changé qu'une seule fois.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    field

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                            .transition(.opacity)
                    }

                    rules

                    Button {
                        Haptics.impact(.medium)
                        Task { await submit() }
                    } label: {
                        Group {
                            if isSubmitting {
                                CinechillSpinner(size: 18, tint: .onAccent)
                            } else {
                                Text(isFirstClaim ? "Choisir ce pseudo" : "Changer définitivement")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            isValid ? Color.indigo : Color.secondary.opacity(0.28),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                    }
                    .buttonStyle(PressableScaleStyle(scale: 0.98))
                    .disabled(!isValid || isSubmitting)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(Color(.systemBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            handle = socialStore.myProfile?.handle ?? ""
        }
    }

    private var field: some View {
        HStack(spacing: 2) {
            Text("@")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            TextField("pseudo", text: $handle)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onChange(of: handle) { _, _ in errorMessage = nil }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(
            Color(.tertiarySystemFill),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 5) {
            rule("3 à 20 caractères", isMet: hasValidLength)
            rule("Minuscules, chiffres, point, tiret ou tiret bas", isMet: hasValidCharacters)
        }
    }

    private func rule(_ text: String, isMet: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundStyle(isMet ? Color.green : Color.secondary.opacity(0.5))
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }

    private func submit() async {
        guard !isSubmitting, isValid else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await socialStore.claimHandle(normalized)
            Haptics.success()
            dismiss()
        } catch {
            withAnimation(.easeOut(duration: 0.2)) {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }
}
