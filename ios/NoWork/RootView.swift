import SwiftUI

struct RootView: View {
    @EnvironmentObject var supabase: SupabaseService

    var body: some View {
        ZStack {
            if supabase.isLoading {
                ProgressView()
            } else if supabase.session != nil {
                ChatRoot()
            } else {
                AuthView()
            }
        }
        .animation(.snappy, value: supabase.session?.user.id)
        .animation(.snappy, value: supabase.isLoading)
    }
}
