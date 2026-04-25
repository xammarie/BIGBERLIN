import SwiftUI
import PencilKit
import PhotosUI

struct AddHandwritingView: View {
    var onSaved: (HandwritingSample) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var canvasView = PKCanvasView()
    @State private var name: String = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoImage: UIImage?
    @State private var mode: SourceMode = .draw
    @State private var isSaving = false
    @State private var error: String?

    enum SourceMode: String, CaseIterable, Identifiable {
        case draw = "draw"
        case photo = "photo"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("name (e.g. \"my regular\")", text: $name)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .glassEffect(in: .capsule)
                    .padding(.horizontal)

                Picker("source", selection: $mode) {
                    ForEach(SourceMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Group {
                    switch mode {
                    case .draw:
                        DrawingCanvas(canvas: $canvasView)
                            .background(.white)
                            .clipShape(.rect(cornerRadius: 22, style: .continuous))
                            .padding(.horizontal)
                    case .photo:
                        VStack {
                            if let img = photoImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(.rect(cornerRadius: 22, style: .continuous))
                            } else {
                                PhotosPicker(selection: $photoItem, matching: .images) {
                                    Label("pick photo of your handwriting", systemImage: "photo")
                                        .frame(maxWidth: .infinity, minHeight: 160)
                                        .glassEffect(in: .rect(cornerRadius: 22, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .onChange(of: photoItem) { _, newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self),
                                   let img = UIImage(data: data) {
                                    photoImage = img
                                }
                            }
                        }
                    }
                }

                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }

                Spacer()
            }
            .padding(.vertical)
            .navigationTitle("add handwriting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let image: UIImage
            switch mode {
            case .draw:
                image = canvasView.drawing.image(
                    from: CGRect(origin: .zero, size: CGSize(width: 1024, height: 256)),
                    scale: 2.0
                )
            case .photo:
                guard let p = photoImage else {
                    throw NSError(domain: "AddHandwriting", code: 0, userInfo: [NSLocalizedDescriptionKey: "pick a photo"])
                }
                image = p
            }

            let path = try await StorageService.shared.upload(image: image, bucket: .handwriting)

            guard let userId = SupabaseService.shared.currentUserId else {
                throw NSError(domain: "Auth", code: 401)
            }

            struct New: Encodable {
                let user_id: String
                let name: String
                let storage_path: String
                let is_default: Bool
            }

            let isFirst: Bool = (try await SupabaseService.shared.client
                .from("handwriting_samples")
                .select("id", head: false, count: .exact)
                .execute()
                .count ?? 0) == 0

            let new = New(
                user_id: userId.uuidString.lowercased(),
                name: name.trimmingCharacters(in: .whitespaces),
                storage_path: path,
                is_default: isFirst
            )

            let inserted: HandwritingSample = try await SupabaseService.shared.client
                .from("handwriting_samples")
                .insert(new)
                .select()
                .single()
                .execute()
                .value

            onSaved(inserted)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct DrawingCanvas: UIViewRepresentable {
    @Binding var canvas: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .white
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}
