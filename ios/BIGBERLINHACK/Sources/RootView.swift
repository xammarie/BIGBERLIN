import SwiftUI

struct RootView: View {
    @EnvironmentObject var supabase: SupabaseService

    var body: some View {
        ZStack {
            if supabase.isLoading {
                ProgressView()
            } else if supabase.session != nil {
                MainTabView()
            } else {
                AuthView()
            }
        }
        .animation(.snappy, value: supabase.session?.user.id)
        .animation(.snappy, value: supabase.isLoading)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeView()
            }
            Tab("Chat", systemImage: "bubble.left.and.bubble.right") {
                ChatView()
            }
            Tab("Library", systemImage: "books.vertical") {
                LibraryView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
