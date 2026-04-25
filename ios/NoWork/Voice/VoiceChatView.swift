import SwiftUI
import AVFoundation

struct VoiceChatView: View {
    @StateObject private var vm = VoiceChatViewModel()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: vm.isListening ? "waveform.circle.fill" : "mic.circle")
                .font(.system(size: 96))
                .foregroundStyle(vm.isListening ? Color.accentColor : Color.secondary)
                .symbolEffect(.pulse, isActive: vm.isListening)

            Text(vm.statusText)
                .font(.headline)
            if !vm.transcript.isEmpty {
                ScrollView {
                    Text(vm.transcript)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .glassEffect(in: .rect(cornerRadius: 18))
                .padding()
            }

            Spacer()

            Button {
                vm.toggle()
            } label: {
                Text(vm.isListening ? "stop" : "talk to tutor")
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.glassProminent)
            .padding()
        }
        .navigationTitle("voice tutor")
        .task { await vm.prepare() }
    }
}

@MainActor
final class VoiceChatViewModel: ObservableObject {
    @Published var isListening = false
    @Published var transcript: String = ""
    @Published var statusText: String = "tap talk to start"

    private var token: EdgeFunctions.VoiceToken?

    func prepare() async {
        do {
            token = try await EdgeFunctions.shared.voiceToken()
            statusText = token?.mode == "ephemeral" ? "ready (ephemeral token)" : "ready"
        } catch {
            statusText = "couldn't connect: \(error.localizedDescription)"
        }
    }

    func toggle() {
        // Placeholder — real implementation opens WebSocket to gradium with token,
        // streams microphone audio, receives transcripts and audio replies.
        isListening.toggle()
        statusText = isListening
            ? "listening… (gradium WS integration is the on-site task — auth token brokered)"
            : "stopped"
    }
}
