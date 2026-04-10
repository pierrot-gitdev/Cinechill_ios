//
//  PaginationBar.swift
//  Cinechill_iOS
//

import SwiftUI

struct PaginationBar: View {
    let currentPage: Int
    let totalPages: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button("Précédent", action: onPrevious)
                .disabled(currentPage <= 1)

            Spacer()

            Text("Page \(currentPage) / \(totalPages)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Suivant", action: onNext)
                .disabled(currentPage >= totalPages)
        }
        .padding(.vertical, 8)
    }
}
