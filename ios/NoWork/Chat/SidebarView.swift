import SwiftUI

struct SidebarView: View {
    /// Called when user picks a chat (UUID) or wants to start a new one (nil for new).
    /// Settings/Library stay in this sheet via NavigationStack push.
    let onPickChat: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = SidebarViewModel()
    @EnvironmentObject var supabase: SupabaseService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onPickChat(nil)
                    } label: {
                        Label("new chat", systemImage: "plus.circle")
                    }
                }

                Section("recent chats") {
                    if vm.chats.isEmpty {
                        Text("nothing yet")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    } else {
                        ForEach(vm.chats) { chat in
                            Button {
                                onPickChat(chat.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chat.title ?? "(untitled)")
                                        .lineLimit(1)
                                    Text(chat.updatedAt, style: .relative)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await vm.deleteChat(chat) }
                                } label: { Label("delete", systemImage: "trash") }
                            }
                        }
                    }
                }

                Section("library") {
                    NavigationLink {
                        HandwritingLibraryView()
                    } label: {
                        Label("handwriting samples", systemImage: "pencil.and.scribble")
                    }
                    NavigationLink {
                        KBFoldersView()
                    } label: {
                        Label("knowledge base folders", systemImage: "books.vertical")
                    }
                }

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
            }
            .navigationTitle("NoWork")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("close") { dismiss() }
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
    }
}

@MainActor
final class SidebarViewModel: ObservableObject {
    @Published var chats: [ChatSummary] = []
    @Published var error: String?
    private let supabase = SupabaseService.shared

    func load() async {
        do {
            chats = try await supabase.client
                .from("chats")
                .select("id, title, updated_at")
                .order("updated_at", ascending: false)
                .limit(50)
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteChat(_ chat: ChatSummary) async {
        do {
            try await supabase.client
                .from("chats")
                .delete()
                .eq("id", value: chat.id.uuidString.lowercased())
                .execute()
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
