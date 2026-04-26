import SwiftUI
import PhotosUI

struct AddFolderItemsView: View {
    let folder: KnowledgeBaseFolder
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: [PhotosPickerItem] = []
    @State private var isUploading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            PhotosPicker(selection: $picked, maxSelectionCount: 10, matching: .images) {
                Label("pick images", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .glassEffect(in: .rect(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding()

            if isUploading {
                ProgressView("uploading…")
            }

            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }

            Spacer()
        }
        .navigationTitle("add to \(folder.name)")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: picked) { _, newItems in
            Task { await upload(items: newItems) }
        }
    }

    private func upload(items: [PhotosPickerItem]) async {
        guard !isUploading else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            for item in items.prefix(10) {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let img = UIImage(data: data) else { continue }
                let path = try await StorageService.shared.upload(image: img, bucket: .kbFiles)
                guard let userId = SupabaseService.shared.currentUserId else { continue }
                struct New: Encodable {
                    let user_id: String
                    let folder_id: String
                    let storage_path: String
                    let filename: String
                    let mime_type: String
                }
                let new = New(
                    user_id: userId.uuidString.lowercased(),
                    folder_id: folder.id.uuidString.lowercased(),
                    storage_path: path,
                    filename: (path as NSString).lastPathComponent,
                    mime_type: "image/jpeg"
                )
                try await SupabaseService.shared.client
                    .from("knowledge_base_items")
                    .insert(new)
                    .execute()
            }
            picked = []
            onAdded()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
