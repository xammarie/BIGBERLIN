import SwiftUI

struct ChatView: View {
    @StateObject private var vm = ChatViewModel()
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(vm.messages) { msg in
                                MessageBubble(message: msg).id(msg.id)
                            }
                            if vm.isWorking {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text("thinking…")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                    .onChange(of: vm.messages.count) { _, _ in
                        if let last = vm.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                Divider()

                HStack(spacing: 8) {
                    Toggle(isOn: $vm.useWeb) {
                        Image(systemName: "globe")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.glass)

                    TextField("ask the tutor anything", text: $vm.input, axis: .vertical)
                        .focused($inputFocused)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .glassEffect(in: .capsule)
                        .lineLimit(1...4)

                    Button {
                        vm.send()
                        inputFocused = false
                    } label: {
                        Image(systemName: "arrow.up")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(vm.input.trimmingCharacters(in: .whitespaces).isEmpty || vm.isWorking)
                }
                .padding()
            }
            .navigationTitle("chat")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.content)
                .padding(12)
                .glassEffect(in: .rect(cornerRadius: 16))
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .padding(.horizontal)
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var input: String = ""
    @Published var useWeb: Bool = false
    @Published var isWorking: Bool = false
    @Published var error: String?

    private var chatId: UUID?
    private let edge = EdgeFunctions.shared

    func send() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        input = ""
        let userMsg = ChatMessage(role: .user, content: trimmed, timestamp: Date())
        messages.append(userMsg)

        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                let resp = try await edge.chat(
                    message: trimmed,
                    chatId: chatId,
                    useWeb: useWeb
                )
                if chatId == nil { chatId = UUID(uuidString: resp.chat_id) }
                messages.append(ChatMessage(role: .assistant, content: resp.reply, timestamp: Date()))
            } catch {
                messages.append(ChatMessage(role: .assistant, content: "error: \(error.localizedDescription)", timestamp: Date()))
            }
        }
    }
}
