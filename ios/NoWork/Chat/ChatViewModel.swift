import SwiftUI
import PhotosUI
import UIKit

enum DisplayMessage: Identifiable, Hashable {
    case userText(id: UUID, text: String, attachmentPaths: [String])
    case assistantText(id: UUID, text: String)
    case worksheetSession(id: UUID, sessionId: UUID, action: WorksheetAction)
    case videoJob(id: UUID, jobId: String, prompt: String)

    var id: UUID {
        switch self {
        case .userText(let id, _, _),
             .assistantText(let id, _),
             .worksheetSession(let id, _, _),
             .videoJob(let id, _, _):
            return id
        }
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var chatId: UUID?
    @Published var messages: [DisplayMessage] = []
    @Published var input: String = ""
    @Published var pendingAction: WorksheetAction?
    @Published var photoSelection: [PhotosPickerItem] = [] {
        didSet { Task { await loadPickedPhotos() } }
    }
    @Published var pendingImages: [UIImage] = []
    @Published var selectedKBFolderId: UUID?
    @Published var useWeb: Bool = false
    @Published var isWorking: Bool = false
    @Published var error: String?

    @Published var handwritingSamples: [HandwritingSample] = []
    @Published var defaultHandwritingId: UUID?
    @Published var handwritingMode: HandwritingMode = .library

    private let supabase = SupabaseService.shared
    private let storage = StorageService.shared
    private let edge = EdgeFunctions.shared

    init(existingChatId: UUID? = nil) {
        self.chatId = existingChatId
        Task { await loadHandwriting() }
        if let id = existingChatId { Task { await loadChat(id) } }
    }

    private func loadHandwriting() async {
        do {
            let samples: [HandwritingSample] = try await supabase.client
                .from("handwriting_samples")
                .select()
                .order("is_default", ascending: false)
                .execute()
                .value
            handwritingSamples = samples
            defaultHandwritingId = samples.first(where: { $0.isDefault })?.id ?? samples.first?.id
        } catch {
            // non-fatal
        }
    }

    private func loadChat(_ id: UUID) async {
        do {
            struct ChatRow: Codable {
                let id: UUID
                let messages: [StoredMessage]?
            }
            struct StoredMessage: Codable {
                let role: String
                let content: String
                let attachment_paths: [String]?
            }

            let row: ChatRow = try await supabase.client
                .from("chats")
                .select("id, messages")
                .eq("id", value: id.uuidString.lowercased())
                .single()
                .execute()
                .value

            let mapped: [DisplayMessage] = (row.messages ?? []).map { m in
                if m.role == "user" {
                    return .userText(id: UUID(), text: m.content, attachmentPaths: m.attachment_paths ?? [])
                } else {
                    return .assistantText(id: UUID(), text: m.content)
                }
            }
            messages = mapped
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadPickedPhotos() async {
        var loaded: [UIImage] = []
        for item in photoSelection {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                loaded.append(img)
            }
        }
        pendingImages = loaded
    }

    func toggleAction(_ action: WorksheetAction) {
        pendingAction = (pendingAction == action) ? nil : action
        // adaptive doesn't make sense for explainer or schrift_replace — force library
        if pendingAction?.supportsAdaptiveMode == false {
            handwritingMode = .library
        }
    }

    func clearAttachments() {
        photoSelection = []
        pendingImages = []
    }

    func send() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = pendingAction
        let images = pendingImages
        let useWebNow = useWeb

        guard !trimmed.isEmpty || !images.isEmpty || action != nil else { return }

        // Validate action constraints
        if let act = action, act.requiresImages, images.isEmpty {
            error = "this action needs at least one worksheet image — attach one"
            return
        }

        // Snapshot inputs and clear UI immediately
        input = ""
        clearAttachments()
        pendingAction = nil
        error = nil

        Task {
            isWorking = true
            defer { isWorking = false }
            await dispatch(text: trimmed, action: action, images: images, useWeb: useWebNow)
        }
    }

    private func dispatch(text: String, action: WorksheetAction?, images: [UIImage], useWeb: Bool) async {
        do {
            // Upload any attached images first (used by both worksheet actions and chat vision)
            var uploadedPaths: [String] = []
            if !images.isEmpty {
                let scope = "chat-\(UUID().uuidString.prefix(6))"
                for img in images {
                    let path = try await storage.upload(image: img, bucket: .worksheetsInput, subpath: scope)
                    uploadedPaths.append(path)
                }
            }

            // Append user message immediately to UI
            let userMsg = DisplayMessage.userText(
                id: UUID(),
                text: text,
                attachmentPaths: uploadedPaths
            )
            messages.append(userMsg)

            switch action {
            case .some(.explainVideo):
                let resp = try await edge.startVideo(
                    topic: text.isEmpty ? "Explain the topic in this conversation" : text,
                    chatId: chatId,
                    knowledgeBaseFolderId: selectedKBFolderId,
                    useWeb: useWeb
                )
                if let jobId = resp.job_id {
                    messages.append(.videoJob(id: UUID(), jobId: jobId, prompt: resp.prompt ?? text))
                } else {
                    messages.append(.assistantText(id: UUID(), text: "video failed to start"))
                }

            case .some(let worksheetAction) where worksheetAction.requiresImages:
                guard let userId = supabase.currentUserId else { throw AppError.notAuthed }

                // Create session
                struct NewSession: Encodable {
                    let user_id: String
                    let action: String
                    let mode: String
                    let handwriting_sample_id: String?
                }
                let sample = handwritingMode == .library ? defaultHandwritingId : nil
                let new = NewSession(
                    user_id: userId.uuidString.lowercased(),
                    action: worksheetAction.rawValue,
                    mode: handwritingMode.rawValue,
                    handwriting_sample_id: sample?.uuidString.lowercased()
                )
                let session: WorksheetSession = try await supabase.client
                    .from("sessions").insert(new).select().single().execute().value

                // Insert input rows
                struct NewInput: Encodable {
                    let session_id: String
                    let storage_path: String
                    let order: Int
                }
                let inputs: [NewInput] = uploadedPaths.enumerated().map { i, path in
                    NewInput(
                        session_id: session.id.uuidString.lowercased(),
                        storage_path: path,
                        order: i
                    )
                }
                try await supabase.client.from("session_inputs").insert(inputs).execute()

                // Kick off pipeline
                _ = try await edge.processWorksheet(sessionId: session.id)

                messages.append(.worksheetSession(id: UUID(), sessionId: session.id, action: worksheetAction))

            default:
                // Plain chat
                let resp = try await edge.chat(
                    message: text,
                    chatId: chatId,
                    useWeb: useWeb,
                    knowledgeBaseFolderId: selectedKBFolderId,
                    attachmentPaths: uploadedPaths.isEmpty ? nil : uploadedPaths
                )
                if chatId == nil { chatId = UUID(uuidString: resp.chat_id) }
                messages.append(.assistantText(id: UUID(), text: resp.reply))
            }
        } catch {
            self.error = error.localizedDescription
            messages.append(.assistantText(id: UUID(), text: "error: \(error.localizedDescription)"))
        }
    }

    enum AppError: LocalizedError {
        case notAuthed
        var errorDescription: String? {
            switch self {
            case .notAuthed: return "not signed in"
            }
        }
    }
}
