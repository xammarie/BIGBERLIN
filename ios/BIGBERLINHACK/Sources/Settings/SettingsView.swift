import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var supabase: SupabaseService

    var body: some View {
        NavigationStack {
            List {
                Section("account") {
                    if let email = supabase.session?.user.email {
                        LabeledContent("email", value: email)
                    }
                    Button(role: .destructive) {
                        Task { try? await supabase.signOut() }
                    } label: {
                        Label("sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
                Section("about") {
                    LabeledContent("app", value: "homework copilot")
                    LabeledContent("event", value: "BIGBERLINHACK 2026")
                }
            }
            .navigationTitle("settings")
        }
    }
}
