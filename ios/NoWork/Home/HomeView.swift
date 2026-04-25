import SwiftUI

struct HomeView: View {
    @State private var pickedAction: WorksheetAction?

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassEffectContainer(spacing: 16) {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("what shall we do")
                                .font(.title2.weight(.semibold))
                            Text("pick an action, then upload your worksheet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)

                        ForEach(WorksheetAction.allCases) { action in
                            Button {
                                pickedAction = action
                            } label: {
                                ActionCard(action: action)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("home")
            .sheet(item: $pickedAction) { action in
                ActionRunView(action: action)
            }
        }
    }
}

struct ActionCard: View {
    let action: WorksheetAction

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: action.systemImage)
                .font(.title2)
                .frame(width: 52, height: 52)
                .glassEffect(in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(action.displayName)
                    .font(.headline)
                Text(action.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.trailing, 6)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .glassEffect(in: .capsule)
    }
}
