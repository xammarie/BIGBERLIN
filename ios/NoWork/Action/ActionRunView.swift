import SwiftUI
import PhotosUI

struct ActionRunView: View {
    let action: WorksheetAction

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: ActionRunViewModel

    init(action: WorksheetAction) {
        self.action = action
        _vm = StateObject(wrappedValue: ActionRunViewModel(action: action))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Worksheet picker
                    GlassEffectContainer(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("worksheets")
                                .font(.headline)
                            Text("upload one or more images")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            if vm.pickedImages.isEmpty {
                                PhotosPicker(
                                    selection: $vm.photoSelection,
                                    maxSelectionCount: 8,
                                    matching: .images
                                ) {
                                    Label("pick images", systemImage: "photo.on.rectangle")
                                        .frame(maxWidth: .infinity, minHeight: 80)
                                        .glassEffect(in: .rect(cornerRadius: 24, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(Array(vm.pickedImages.enumerated()), id: \.offset) { _, img in
                                            Image(uiImage: img)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 100, height: 130)
                                                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                                        }
                                        PhotosPicker(
                                            selection: $vm.photoSelection,
                                            maxSelectionCount: 8,
                                            matching: .images
                                        ) {
                                            Image(systemName: "plus")
                                                .frame(width: 100, height: 130)
                                                .glassEffect(in: .rect(cornerRadius: 18, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding()
                        .glassEffect(in: .rect(cornerRadius: 28, style: .continuous))
                    }

                    // Mode + handwriting sample
                    GlassEffectContainer(spacing: 12) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("handwriting style")
                                .font(.headline)

                            Picker("mode", selection: $vm.mode) {
                                Text("my style").tag(HandwritingMode.library)
                                if action.supportsAdaptiveMode {
                                    Text("adaptive").tag(HandwritingMode.adaptive)
                                }
                            }
                            .pickerStyle(.segmented)

                            if vm.mode == .library {
                                if vm.samples.isEmpty {
                                    Text("you have no handwriting samples yet — add one in Library")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Picker("sample", selection: $vm.selectedSampleId) {
                                        ForEach(vm.samples) { s in
                                            Text(s.name + (s.isDefault ? "  ·  default" : "")).tag(Optional(s.id))
                                        }
                                    }
                                }
                            } else {
                                Text("the editor will match the handwriting already on the page")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .glassEffect(in: .rect(cornerRadius: 28, style: .continuous))
                    }

                    // Run button
                    Button(action: vm.run) {
                        HStack {
                            if vm.isWorking { ProgressView().controlSize(.small) }
                            Text(vm.isWorking ? "processing…" : "run \(action.displayName.lowercased())")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.glassProminent)
                    .clipShape(.capsule)
                    .disabled(!vm.canRun)

                    if let error = vm.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }

                    if let session = vm.session {
                        SessionDetailView(sessionId: session.id)
                            .frame(maxHeight: .infinity)
                    }
                }
                .padding()
            }
            .navigationTitle(action.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("close") { dismiss() }
                }
            }
            .task { await vm.loadSamples() }
        }
    }
}
