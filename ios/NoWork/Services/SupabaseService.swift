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
            supabaseKey: Configuration.supabaseAnonKey
        )

        Task { await bootstrap() }
    }

    var currentUserId: UUID? { session?.user.id }

    private func bootstrap() async {
        // Try to read an existing local session before subscribing so the UI
        // doesn't hang on the loading spinner if no auth state event fires.
        if let existing = try? await client.auth.session {
            self.session = existing
        }
        self.isLoading = false

        for await (_, session) in client.auth.authStateChanges {
            self.session = session
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
