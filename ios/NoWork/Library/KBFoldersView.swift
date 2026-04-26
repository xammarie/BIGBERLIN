import SwiftUI

struct KBFoldersView: View {
    @StateObject private var vm = KBFoldersViewModel()
    @State private var showCreate = false
    @State private var newFolderName = ""

    private let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18),
    ]

    var body: some View {
        Group {
            if vm.folders.isEmpty {
                ContentUnavailableView(
                    "no folders yet",
                    systemImage: "folder",
                    description: Text("organize your knowledge base into folders. when chatting, pick which folder the agent uses as context.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .center, spacing: 22) {
                        ForEach(Array(vm.folders.enumerated()), id: \.element.id) { index, folder in
                            let color = KnowledgeBaseFolder.color(at: index)
                            NavigationLink {
                                KBFolderItemsView(folder: folder, color: color)
                            } label: {
                                FolderTile(folder: folder, color: color)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if !folder.isDefault {
                                    Button {
                                        Task { await vm.setDefault(folder) }
                                    } label: { Label("set default", systemImage: "star") }
                                }
                                Button(role: .destructive) {
                                    Task { await vm.delete(folder) }
                                } label: { Label("delete", systemImage: "trash") }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            if let error = vm.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
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

struct FolderTile: View {
    let folder: KnowledgeBaseFolder
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            FolderGlyph(color: color, isDefault: folder.isDefault)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.05, contentMode: .fit)

            Text(folder.name)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

/// SF Symbol-based folder glyph. Uses the native filled folder shape so it
/// reads as a folder, not a widget. Tinted per-folder for visual variety.
struct FolderGlyph: View {
    let color: Color
    var isDefault: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "folder.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(color.gradient)
                .shadow(color: color.opacity(0.25), radius: 6, x: 0, y: 4)

            if isDefault {
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Circle().fill(Color.yellow))
                    .offset(x: 4, y: -2)
            }
        }
    }
}

extension KnowledgeBaseFolder {
    /// Cycle through the palette by position so adjacent folders never collide.
    /// No DB column needed.
    static func color(at index: Int) -> Color {
        palette[((index % palette.count) + palette.count) % palette.count]
    }

    private static let palette: [Color] = [
        Color(red: 0.20, green: 0.55, blue: 0.95),  // blue
        Color(red: 0.95, green: 0.65, blue: 0.20),  // amber
        Color(red: 0.85, green: 0.30, blue: 0.55),  // pink
        Color(red: 0.30, green: 0.75, blue: 0.55),  // mint
        Color(red: 0.60, green: 0.40, blue: 0.90),  // purple
        Color(red: 0.95, green: 0.45, blue: 0.35),  // coral
        Color(red: 0.20, green: 0.75, blue: 0.85),  // teal
    ]
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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80, let userId = supabase.currentUserId else {
            error = "folder name must be 1-80 characters"
            return
        }
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
    var color: Color = .accentColor
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
                        Image(systemName: "doc.fill").foregroundStyle(color)
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
