import SwiftUI

@main
struct BIGBERLINHACKApp: App {
    @StateObject private var supabase = SupabaseService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(supabase)
        }
    }
}
