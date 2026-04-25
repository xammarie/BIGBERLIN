import SwiftUI
import PhotosUI
import UIKit

@MainActor
final class ActionRunViewModel: ObservableObject {
    let action: WorksheetAction

    @Published var photoSelection: [PhotosPickerItem] = [] {
        didSet { Task { await loadPhotos() } }
    }
    @Published var pickedImages: [UIImage] = []

    @Published var samples: [HandwritingSample] = []
    @Published var selectedSampleId: UUID?
    @Published var mode: HandwritingMode = .library
    @Published var isWorking: Bool = false
    @Published var errorMessage: String?
    @Published var session: WorksheetSession?

    private let supabase = SupabaseService.shared
    private let storage = StorageService.shared
    private let edge = EdgeFunctions.shared

    init(action: WorksheetAction) {
        self.action = action
        if !action.supportsAdaptiveMode { mode = .library }
    }

    var canRun: Bool {
        guard !pickedImages.isEmpty, !isWorking else { return false }
        if mode == .library, selectedSampleId == nil { return false }
        return true
    }

    func loadSamples() async {
        do {
            let result: [HandwritingSample] = try await supabase.client
                .from("handwriting_samples")
                .select()
                .order("is_default", ascending: false)
                .order("created_at", ascending: false)
                .execute()
                .value
            samples = result
            if selectedSampleId == nil {
                selectedSampleId = result.first(where: { $0.isDefault })?.id ?? result.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadPhotos() async {
        var result: [UIImage] = []
        for item in photoSelection {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                result.append(img)
            }
        }
        pickedImages = result
    }

    func run() {
        Task { await runAsync() }
    }

    private func runAsync() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            guard let userId = supabase.currentUserId else {
                throw NSError(domain: "Auth", code: 401)
            }

            // 1. Upload all images to worksheets-input
            var uploaded: [(path: String, order: Int)] = []
            for (i, img) in pickedImages.enumerated() {
                let sessionScope = "session-\(UUID().uuidString.prefix(8))"
                let path = try await storage.upload(
                    image: img,
                    bucket: .worksheetsInput,
                    subpath: sessionScope
                )
                uploaded.append((path, i))
            }

            // 2. Create session row
            struct NewSession: Encodable {
                let user_id: String
                let action: String
                let mode: String
                let handwriting_sample_id: String?
            }
            let newSession = NewSession(
                user_id: userId.uuidString.lowercased(),
                action: action.rawValue,
                mode: mode.rawValue,
                handwriting_sample_id: mode == .library ? selectedSampleId?.uuidString.lowercased() : nil
            )
            let createdSession: WorksheetSession = try await supabase.client
                .from("sessions")
                .insert(newSession)
                .select()
                .single()
                .execute()
                .value

            // 3. Insert input rows
            struct NewInput: Encodable {
                let session_id: String
                let storage_path: String
                let order: Int
            }
            let inputs = uploaded.map { up in
                NewInput(
                    session_id: createdSession.id.uuidString.lowercased(),
                    storage_path: up.path,
                    order: up.order
                )
            }
            try await supabase.client.from("session_inputs").insert(inputs).execute()

            // 4. Kick off processing
            _ = try await edge.processWorksheet(sessionId: createdSession.id)

            session = createdSession
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
