import SwiftUI
import PhotosUI

struct LibraryView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        HandwritingLibraryView()
                    } label: {
                        Label("handwriting samples", systemImage: "pencil.and.scribble")
                    }
                    NavigationLink {
                        KnowledgeBaseView()
                    } label: {
                        Label("knowledge base", systemImage: "books.vertical")
                    }
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label("past sessions", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
            .navigationTitle("library")
        }
    }
}

struct HandwritingLibraryView: View {
    @StateObject private var vm = HandwritingLibraryViewModel()
    @State private var showAdd = false

    var body: some View {
        List {
            if vm.samples.isEmpty {
                ContentUnavailableView(
                    "no samples yet",
                    systemImage: "pencil.and.scribble",
                    description: Text("add a sample of your handwriting so the agent can write in your style.")
                )
            } else {
                ForEach(vm.samples) { sample in
                    HStack {
                        AsyncStorageImage(bucket: .handwriting, path: sample.storagePath)
                            .frame(width: 80, height: 50)
                            .clipShape(.rect(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading) {
                            Text(sample.name)
                            if sample.isDefault {
                                Text("default").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if !sample.isDefault {
                            Button("set default") {
                                Task { await vm.setDefault(sample) }
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await vm.delete(sample) }
                        } label: { Label("delete", systemImage: "trash") }
                    }
                }
            }
        }
        .navigationTitle("handwriting")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddHandwritingView { newSample in
                vm.samples.append(newSample)
            }
        }
        .task { await vm.load() }
    }
}

@MainActor
final class HandwritingLibraryViewModel: ObservableObject {
    @Published var samples: [HandwritingSample] = []
    @Published var error: String?

    private let supabase = SupabaseService.shared

    func load() async {
        do {
            samples = try await supabase.client
                .from("handwriting_samples")
                .select()
                .order("is_default", ascending: false)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setDefault(_ sample: HandwritingSample) async {
        do {
            // Clear existing default
            try await supabase.client
                .from("handwriting_samples")
                .update(["is_default": false])
                .eq("user_id", value: sample.userId.uuidString.lowercased())
                .eq("is_default", value: true)
                .execute()
            // Set new default
            try await supabase.client
                .from("handwriting_samples")
                .update(["is_default": true])
                .eq("id", value: sample.id.uuidString.lowercased())
                .execute()
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ sample: HandwritingSample) async {
        do {
            try await supabase.client
                .from("handwriting_samples")
                .delete()
                .eq("id", value: sample.id.uuidString.lowercased())
                .execute()
            try? await supabase.client.storage
                .from(StorageBucket.handwriting.rawValue)
                .remove(paths: [sample.storagePath])
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
