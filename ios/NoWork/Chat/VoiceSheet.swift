import SwiftUI
import AVFoundation

struct VoiceSheet: View {
    @ObservedObject var vm: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isListening = false
    @State private var status: String = "tap to talk"
    @State private var token: EdgeFunctions.VoiceToken?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: isListening ? "waveform.circle.fill" : "mic.circle")
                .font(.system(size: 110, weight: .light))
                .foregroundStyle(isListening ? Color.accentColor : Color.secondary)
                .symbolEffect(.pulse, isActive: isListening)
            Text(status)
                .font(.headline)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                isListening.toggle()
                status = isListening
                    ? "listening (gradium WS connect = on-site task)"
                    : "stopped"
            } label: {
                Text(isListening ? "stop" : "start talking")
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.glassProminent)
            .clipShape(.capsule)
            Button("close") { dismiss() }
                .padding(.bottom)
        }
        .padding()
        .task {
            do {
                token = try await EdgeFunctions.shared.voiceToken()
                status = "ready (\(token?.mode ?? "?")) — tap to talk"
            } catch {
                status = "couldn't get token: \(error.localizedDescription)"
            }
        }
    }
}

struct KBFolderPickerSheet: View {
    @Binding var selectedId: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var folders: [KnowledgeBaseFolder] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selectedId = nil
                    dismiss()
                } label: {
                    HStack {
                        Label("no folder (use chat only)", systemImage: "tray")
                        Spacer()
                        if selectedId == nil { Image(systemName: "checkmark") }
                    }
                }
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else {
                    ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                        Button {
                            selectedId = folder.id
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill")
                                    .font(.title3)
                                    .foregroundStyle(KnowledgeBaseFolder.color(at: index).gradient)
                                    .frame(width: 28)
                                Text(folder.name)
                                Spacer()
                                if folder.isDefault {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                }
                                if selectedId == folder.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("knowledge base")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") { dismiss() }
                }
            }
        }
        .task { await loadFolders() }
    }

    private func loadFolders() async {
        defer { isLoading = false }
        do {
            folders = try await SupabaseService.shared.client
                .from("knowledge_base_folders")
                .select()
                .order("is_default", ascending: false)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch { /* ignore */ }
    }
}
