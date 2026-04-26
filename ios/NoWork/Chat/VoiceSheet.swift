import SwiftUI
import AVFoundation

struct VoiceSheet: View {
    @ObservedObject var vm: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var voice = VoiceTranscriber()
    @State private var lastReply: String?
    @State private var sending: Bool = false
    @State private var pulse: Bool = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)

            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 180, height: 180)
                Circle()
                    .stroke(Color.accentColor.opacity(voice.isRunning ? 0.9 : 0.25),
                            lineWidth: voice.isRunning ? 4 : 2)
                    .frame(width: 180, height: 180)
                    .scaleEffect(pulse ? 1.08 : 1.0)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                               value: pulse)
                Image(systemName: voice.isRunning ? "waveform" : "mic.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(voice.isRunning ? Color.accentColor : Color.primary)
                    .symbolEffect(.variableColor.iterative.reversing,
                                  isActive: voice.isRunning)
            }

            Text(voice.status)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !voice.transcript.isEmpty {
                        Text(voice.transcript)
                            .font(.title3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("your speech will appear here")
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let reply = lastReply, !reply.isEmpty {
                        Divider()
                        Text(reply)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let err = voice.error {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 8)

            VStack(spacing: 12) {
                Button {
                    Task { await toggleListening() }
                } label: {
                    Label(voice.isRunning ? "stop" : "start talking",
                          systemImage: voice.isRunning ? "stop.fill" : "mic.fill")
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.glassProminent)
                .clipShape(.capsule)
                .disabled(sending)

                Button {
                    Task { await sendTranscript() }
                } label: {
                    if sending {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 48)
                    } else {
                        Label("send to chat", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                }
                .buttonStyle(.glass)
                .clipShape(.capsule)
                .disabled(sending || voice.isRunning || voice.transcript.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("close") { dismiss() }
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
        .task {
            await voice.prepare()
        }
        .onChange(of: voice.isRunning) { _, running in
            pulse = running
        }
        .interactiveDismissDisabled(voice.isRunning || sending)
    }

    private func toggleListening() async {
        if voice.isRunning {
            await voice.stop()
        } else {
            lastReply = nil
            await voice.start()
        }
    }

    private func sendTranscript() async {
        if voice.isRunning { await voice.stop() }
        let text = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        defer { sending = false }

        // Push the transcript through the normal chat pipeline so it shows up
        // in chat history alongside the assistant reply.
        vm.input = text
        vm.send()

        // Wait for `isWorking` to flip back to false, then grab the latest
        // assistant message and speak it.
        while vm.isWorking {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let reply = vm.messages.reversed().compactMap { msg -> String? in
            if case .assistantText(_, let text) = msg { return text }
            return nil
        }.first
        lastReply = reply
        if let reply, !reply.isEmpty {
            await voice.speak(reply)
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
