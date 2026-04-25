import SwiftUI

struct KBFoldersView: View {
    @StateObject private var vm = KBFoldersViewModel()
    @State private var showCreate = false
    @State private var newFolderName = ""

    var body: some View {
        List {
            if vm.folders.isEmpty {
                ContentUnavailableView(
                    "no folders yet",
                    systemImage: "folder",
                    description: Text("organize your knowledge base into folders. when chatting you can pick which folder the agent uses as context.")
                )
            } else {
                ForEach(vm.folders) { folder in
                    NavigationLink {
                        KBFolderItemsView(folder: folder)
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text(folder.name)
                            if folder.isDefault {
                                Text("default")
                                    .font(.caption)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .glassEffect(in: .capsule)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await vm.delete(folder) }
                        } label: { Label("delete", systemImage: "trash") }
                        if !folder.isDefault {
                            Button {
                                Task { await vm.setDefault(folder) }
                            } label: { Label("default", systemImage: "star") }
                            .tint(.yellow)
                        }
                    }
                }
            }
        }
        .navigationTitle("knowledge base")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .alert("new folder", isPresented: $showCreate) {
            TextField("name", text: $newFolderName)
            Button("create") {
                Task {
                    await vm.create(name: newFolderName)
                    newFolderName = ""
                }
            }
            Button("cancel", role: .cancel) { newFolderName = "" }
        }
        .task { await vm.load() }
    }
}

@MainActor
final class KBFoldersViewModel: ObservableObject {
    @Published var folders: [KnowledgeBaseFolder] = []
    @Published var error: String?
    private let supabase = SupabaseService.shared

    func load() async {
        do {
            folders = try await supabase.client
                .from("knowledge_base_folders")
                .select()
                .order("is_default", ascending: false)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
        }
    }

    func create(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let userId = supabase.currentUserId else { return }
        do {
            struct New: Encodable {
                let user_id: String
                let name: String
                let is_default: Bool
            }
            let isFirst = folders.isEmpty
            let new = New(
                user_id: userId.uuidString.lowercased(),
                name: trimmed,
                is_default: isFirst
            )
            try await supabase.client.from("knowledge_base_folders").insert(new).execute()
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setDefault(_ folder: KnowledgeBaseFolder) async {
        do {
            try await supabase.client
                .from("knowledge_base_folders")
                .update(["is_default": false])
                .eq("user_id", value: folder.userId.uuidString.lowercased())
                .eq("is_default", value: true)
                .execute()
            try await supabase.client
                .from("knowledge_base_folders")
                .update(["is_default": true])
                .eq("id", value: folder.id.uuidString.lowercased())
                .execute()
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ folder: KnowledgeBaseFolder) async {
        do {
            try await supabase.client
                .from("knowledge_base_folders")
                .delete()
                .eq("id", value: folder.id.uuidString.lowercased())
                .execute()
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct KBFolderItemsView: View {
    let folder: KnowledgeBaseFolder
    @StateObject private var vm = KBFolderItemsViewModel()
    @State private var photoSelection: [PhotosPickerItem_Wrapper] = []

    var body: some View {
        List {
            if vm.items.isEmpty {
                ContentUnavailableView(
                    "no files in this folder",
                    systemImage: "doc",
                    description: Text("upload files via the + button.")
                )
            } else {
                ForEach(vm.items) { item in
                    HStack {
                        Image(systemName: "doc.fill").foregroundStyle(.tint)
                        Text(item.filename).lineLimit(1)
                        Spacer()
                        Text(item.createdAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await vm.delete(item) }
                        } label: { Label("delete", systemImage: "trash") }
                    }
                }
            }
        }
        .navigationTitle(folder.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AddFolderItemsView(folder: folder) {
                        Task { await vm.load(folderId: folder.id) }
                    }
                } label: { Image(systemName: "plus") }
            }
        }
        .task { await vm.load(folderId: folder.id) }
    }
}

// Workaround: PhotosPickerItem array isn't directly Equatable in older toolchains
struct PhotosPickerItem_Wrapper {}

@MainActor
final class KBFolderItemsViewModel: ObservableObject {
    @Published var items: [KnowledgeBaseItem] = []
    @Published var error: String?
    private let supabase = SupabaseService.shared

    func load(folderId: UUID) async {
        do {
            items = try await supabase.client
                .from("knowledge_base_items")
                .select()
                .eq("folder_id", value: folderId.uuidString.lowercased())
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ item: KnowledgeBaseItem) async {
        do {
            try await supabase.client.from("knowledge_base_items")
                .delete().eq("id", value: item.id.uuidString.lowercased()).execute()
            try? await supabase.client.storage.from(StorageBucket.kbFiles.rawValue)
                .remove(paths: [item.storagePath])
            if let folderId = item.folderId { await load(folderId: folderId) }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
