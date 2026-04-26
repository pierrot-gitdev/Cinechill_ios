import SwiftUI

struct BrowseCardView: View {
    let title: String
    let posterURL: URL?

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
                .padding(12)
                .padding(.trailing, 44)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .overlay(alignment: .bottomTrailing) {
            if let posterURL {
                AsyncImage(url: posterURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.gray.opacity(0.2))
                    }
                }
                .frame(width: 52, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .rotationEffect(.degrees(10), anchor: .bottomTrailing)
                .padding(.trailing, 6)
                .padding(.bottom, -6)
            }
        }
        .frame(width: 160, height: 80, alignment: .topLeading)
        .clipped()
    }
}
