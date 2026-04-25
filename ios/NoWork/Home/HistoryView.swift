import SwiftUI

struct HistoryView: View {
    @StateObject private var vm = HistoryViewModel()

    var body: some View {
        List {
            ForEach(vm.sessions) { session in
                NavigationLink {
                    PastSessionView(session: session)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: WorksheetAction(rawValue: session.action.rawValue)?.systemImage ?? "doc")
                            Text(session.action.displayName).font(.headline)
                            Spacer()
                            Text(session.createdAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(session.status.rawValue.capitalized) · \(session.mode.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("history")
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }
}

struct PastSessionView: View {
    let session: WorksheetSession
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SessionDetailView(sessionId: session.id)
                    .padding()
            }
        }
        .navigationTitle(session.action.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var sessions: [WorksheetSession] = []
    @Published var error: String?
    private let supabase = SupabaseService.shared

    func load() async {
        do {
            sessions = try await supabase.client
                .from("sessions")
                .select()
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
        }
    }
}
