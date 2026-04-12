import SwiftUI

struct HomeGenresListView: View {
    let categories: [HomeBrowseCategory]
    let homeModel: HomeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Tous les genres")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                ForEach(categories) { category in
                    NavigationLink(destination: GenrePopularListView(category: category, homeModel: homeModel)) {
                        HStack {
                            Text(category.title)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

