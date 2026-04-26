import SwiftUI
import PhotosUI

struct PromptBar: View {
    @ObservedObject var vm: ChatViewModel
    @FocusState.Binding var inputFocused: Bool
    @State private var showVoice = false
    @State private var showKBPicker = false

    var body: some View {
        VStack(spacing: 12) {
            // Attached image previews — sit on top of the bar, outside its frame.
            if !vm.pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(vm.pendingImages.enumerated()), id: \.offset) { _, img in
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                        }
                        Button {
                            vm.clearAttachments()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.footnote)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(.regularMaterial))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 4)
                }
            }

            VStack(spacing: 0) {
                // Text input row
                TextField(placeholder, text: $vm.input, axis: .vertical)
                    .focused($inputFocused)
                    .lineLimit(1...5)
                    .font(.body)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 6)

                // Tools row
                HStack(spacing: 6) {
                    PhotosPicker(
                        selection: $vm.photoSelection,
                        maxSelectionCount: 8,
                        matching: .images
                    ) {
                        ToolIcon(systemName: "plus")
                    }

                    Button { vm.useWeb.toggle() } label: {
                        ToolIcon(systemName: "globe", active: vm.useWeb)
                    }

                    Button { showKBPicker = true } label: {
                        ToolIcon(
                            systemName: "books.vertical",
                            active: vm.selectedKBFolderId != nil
                        )
                    }

                    Menu {
                        ForEach(ModelMode.allCases, id: \.self) { mode in
                            Button {
                                vm.modelMode = mode
                            } label: {
                                Label(mode.displayName, systemImage: mode.systemImage)
                            }
                        }
                    } label: {
                        ToolIcon(
                            systemName: vm.modelMode.systemImage,
                            active: vm.modelMode == .smart
                        )
                    }

                    Spacer()

                    Button { showVoice = true } label: {
                        ToolIcon(systemName: "mic")
                    }

                    Button {
                        vm.send()
                        inputFocused = false
                    } label: {
                        Image(systemName: vm.isWorking ? "ellipsis" : "arrow.up")
                            .font(.headline)
                            .foregroundStyle(canSend ? Color.white : Color.primary.opacity(0.6))
                            .frame(width: 38, height: 38)
                            .background {
                                if canSend {
                                    Circle().fill(Color.accentColor)
                                }
                            }
                            .glassEffect(in: .circle)
                    }
                    .disabled(!canSend)
                    .animation(.snappy(duration: 0.18), value: canSend)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .glassEffect(in: .rect(cornerRadius: 28, style: .continuous))
        }
        .sheet(isPresented: $showVoice) {
            VoiceSheet(vm: vm)
        }
        .sheet(isPresented: $showKBPicker) {
            KBFolderPickerSheet(selectedId: $vm.selectedKBFolderId)
        }
    }

    private var canSend: Bool {
        !vm.isWorking && (
            !vm.input.trimmingCharacters(in: .whitespaces).isEmpty
            || !vm.pendingImages.isEmpty
            || vm.pendingAction != nil
        )
    }

    private var placeholder: String {
        if let action = vm.pendingAction {
            return "\(action.displayName.lowercased()) — add details or just send"
        }
        return "Ask, search or make anything…"
    }
}

struct ToolIcon: View {
    let systemName: String
    var active: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .font(.subheadline)
            .frame(width: 36, height: 36)
            .foregroundStyle(active ? Color.white : Color.primary.opacity(0.75))
            .background {
                if active {
                    Circle().fill(Color.accentColor)
                }
            }
    }
}
