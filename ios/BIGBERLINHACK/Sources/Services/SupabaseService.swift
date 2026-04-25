import Foundation
import Supabase

@MainActor
final class SupabaseService: ObservableObject {
    static let shared = SupabaseService()

    let client: SupabaseClient

    @Published var session: Auth.Session?
    @Published var isLoading: Bool = true

    private init() {
        client = SupabaseClient(
            supabaseURL: Configuration.supabaseURL,
            supabaseKey: Configuration.supabaseAnonKey,
            options: .init(
                auth: .init(
                    flowType: .pkce,
                    autoRefreshToken: true
                )
            )
        )

        Task { await listenForAuthChanges() }
    }

    var currentUserId: UUID? { session?.user.id }

    private func listenForAuthChanges() async {
        for await (event, session) in client.auth.authStateChanges {
            self.session = session
            self.isLoading = false
            _ = event
        }
    }

    // MARK: - Auth

    func signUp(email: String, password: String) async throws {
        try await client.auth.signUp(email: email, password: password)
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }
}
