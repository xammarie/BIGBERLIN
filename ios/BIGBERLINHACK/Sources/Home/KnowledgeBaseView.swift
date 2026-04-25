import SwiftUI
import PhotosUI

struct KnowledgeBaseView: View {
    @StateObject private var vm = KnowledgeBaseViewModel()
    @State private var photoSelection: [PhotosPickerItem] = []

    var body: some View {
        List {
            Section {
                if vm.items.isEmpty {
                    ContentUnavailableView(
                        "no files yet",
                        systemImage: "books.vertical",
                        description: Text("upload notes, prior worksheets, or files. the agent uses them as context if available — completely optional.")
                    )
                } else {
                    ForEach(vm.items) { item in
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(.tint)
                            Text(item.filename)
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
        }
        .navigationTitle("knowledge base")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PhotosPicker(selection: $photoSelection, maxSelectionCount: 5, matching: .images) {
                    Image(systemName: "plus")
                }
            }
        }
        .onChange(of: photoSelection) { _, newItems in
            Task {
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await vm.addImage(img)
                    }
                }
                photoSelection = []
            }
        }
        .task { await vm.load() }
    }
}

@MainActor
final class KnowledgeBaseViewModel: ObservableObject {
    @Published var items: [KnowledgeBaseItem] = []
    @Published var error: String?
    private let supabase = SupabaseService.shared
    private let storage = StorageService.shared

    func load() async {
        do {
            items = try await supabase.client
                .from("knowledge_base_items")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addImage(_ image: UIImage) async {
        do {
            let path = try await storage.upload(image: image, bucket: .kbFiles)
            guard let userId = supabase.currentUserId else { return }
            struct New: Encodable {
                let user_id: String
                let storage_path: String
                let filename: String
                let mime_type: String
            }
            let new = New(
                user_id: userId.uuidString.lowercased(),
                storage_path: path,
                filename: (path as NSString).lastPathComponent,
                mime_type: "image/jpeg"
            )
            try await supabase.client.from("knowledge_base_items").insert(new).execute()
            await load()
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
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
