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
    @Published var modelMode: ModelMode = .fast
    @Published var isWorking: Bool = false
    @Published var error: String?

    @Published var handwritingSamples: [HandwritingSample] = []
    @Published var defaultHandwritingId: UUID?
    @Published var handwritingMode: HandwritingMode = .library

    private let supabase = SupabaseService.shared
    private let storage = StorageService.shared
    private let edge = EdgeFunctions.shared
    private var photoLoadTask: Task<Void, Never>?

    init(existingChatId: UUID? = nil) {
        self.chatId = existingChatId
        Task { await loadHandwriting() }
        if let id = existingChatId { Task { await loadChat(id) } }
    }

    deinit {
        photoLoadTask?.cancel()
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

    func loadChat(_ id: UUID) async {
        do {
            struct ChatRow: Codable {
                let id: UUID
                let messages: [StoredMessage]?
            }
            let row: ChatRow = try await supabase.client
                .from("chats")
                .select("id, messages")
                .eq("id", value: id.uuidString.lowercased())
                .single()
                .execute()
                .value
            chatId = id
            messages = (row.messages ?? []).map(Self.displayFromStored)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Wire-format for chats.messages JSONB. Compatible with the chat edge function
    /// (which only reads role/content/timestamp/attachment_paths) but extended with
    /// optional fields so worksheet sessions and video jobs round-trip through history.
    struct StoredMessage: Codable {
        let role: String
        let content: String
        let timestamp: Date
        var attachment_paths: [String]?
        var session_id: String?
        var action: String?
        var video_job_id: String?
        var prompt: String?
    }

    private static func storedFromDisplay(_ m: DisplayMessage) -> StoredMessage {
        let now = Date()
        switch m {
        case .userText(_, let text, let paths):
            return StoredMessage(
                role: "user", content: text, timestamp: now,
                attachment_paths: paths.isEmpty ? nil : paths
            )
        case .assistantText(_, let text):
            return StoredMessage(role: "assistant", content: text, timestamp: now)
        case .worksheetSession(_, let sessionId, let action):
            return StoredMessage(
                role: "assistant",
                content: action.displayName,
                timestamp: now,
                session_id: sessionId.uuidString.lowercased(),
                action: action.rawValue
            )
        case .videoJob(_, let jobId, let prompt):
            return StoredMessage(
                role: "assistant",
                content: "Explainer video",
                timestamp: now,
                video_job_id: jobId,
                prompt: prompt
            )
        }
    }

    private static func displayFromStored(_ s: StoredMessage) -> DisplayMessage {
        if let sid = s.session_id, let actionRaw = s.action,
           let action = WorksheetAction(rawValue: actionRaw),
           let sessionUUID = UUID(uuidString: sid) {
            return .worksheetSession(id: UUID(), sessionId: sessionUUID, action: action)
        }
        if let jobId = s.video_job_id {
            return .videoJob(id: UUID(), jobId: jobId, prompt: s.prompt ?? s.content)
        }
        if s.role == "user" {
            return .userText(id: UUID(), text: s.content, attachmentPaths: s.attachment_paths ?? [])
        }
        return .assistantText(id: UUID(), text: s.content)
    }

    /// Insert (if no chatId yet) or update the chats row to mirror `messages`.
    /// Best-effort — failures here don't block the UI flow.
    private func persistChat() async {
        guard let userId = supabase.currentUserId else { return }
        let stored = messages.suffix(80).map(Self.storedFromDisplay)
        do {
            if let id = chatId {
                struct UpdateBody: Encodable {
                    let messages: [StoredMessage]
                }
                try await supabase.client
                    .from("chats")
                    .update(UpdateBody(messages: stored))
                    .eq("id", value: id.uuidString.lowercased())
                    .execute()
            } else {
                let newId = UUID()
                struct InsertBody: Encodable {
                    let id: String
                    let user_id: String
                    let title: String?
                    let messages: [StoredMessage]
                }
                try await supabase.client
                    .from("chats")
                    .insert(InsertBody(
                        id: newId.uuidString.lowercased(),
                        user_id: userId.uuidString.lowercased(),
                        title: deriveTitle(),
                        messages: stored
                    ))
                    .execute()
                chatId = newId
            }
        } catch {
            // non-fatal
        }
    }

    private func deriveTitle() -> String? {
        for m in messages {
            switch m {
            case .userText(_, let text, _) where !text.isEmpty:
                return String(text.prefix(60))
            case .worksheetSession(_, _, let action):
                return action.displayName
            case .videoJob(_, _, let prompt):
                let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return "Video: \(trimmed.prefix(40))" }
                return "Explainer video"
            default:
                continue
            }
        }
        return nil
    }

    private func loadPickedPhotos() async {
        let items = photoSelection
        photoLoadTask?.cancel()
        photoLoadTask = Task { await loadPickedPhotos(items) }
    }

    private func loadPickedPhotos(_ items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        for item in items.prefix(8) {
            if Task.isCancelled { return }
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                loaded.append(img)
            }
        }
        guard !Task.isCancelled else { return }
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
        guard !isWorking else { return }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = pendingAction
        let images = pendingImages
        let useWebNow = useWeb
        let modelNow = modelMode

        guard !trimmed.isEmpty || !images.isEmpty || action != nil else { return }
        guard trimmed.count <= 4_000 else {
            error = "message is too long — keep it under 4000 characters"
            return
        }

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
        isWorking = true

        Task {
            defer { isWorking = false }
            await dispatch(text: trimmed, action: action, images: images, useWeb: useWebNow, model: modelNow)
        }
    }

    private func dispatch(text: String, action: WorksheetAction?, images: [UIImage], useWeb: Bool, model: ModelMode) async {
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
                await persistChat()

            case .some(let worksheetAction) where worksheetAction.requiresImages:
                guard let userId = supabase.currentUserId else { throw AppError.notAuthed }

                // Re-fetch samples right before insert so we never reference a deleted row.
                await loadHandwriting()

                // Decide mode + sample based on action needs and what the user actually has.
                let needsSample = worksheetAction.rendersNewHandwriting
                let hasSample = defaultHandwritingId != nil

                if worksheetAction == .schriftReplace && !hasSample {
                    throw AppError.missingHandwritingSample
                }

                let effectiveMode: HandwritingMode
                let effectiveSampleId: UUID?
                if needsSample && hasSample {
                    effectiveMode = .library
                    effectiveSampleId = defaultHandwritingId
                } else {
                    // No sample needed (correct/annotate) or none uploaded yet → adaptive, no sample.
                    effectiveMode = .adaptive
                    effectiveSampleId = nil
                }

                struct NewSession: Encodable {
                    let user_id: String
                    let action: String
                    let mode: String
                    let handwriting_sample_id: String?
                }
                let new = NewSession(
                    user_id: userId.uuidString.lowercased(),
                    action: worksheetAction.rawValue,
                    mode: effectiveMode.rawValue,
                    handwriting_sample_id: effectiveSampleId?.uuidString.lowercased()
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
                await persistChat()

            default:
                // Plain chat — edge function persists the chats row itself.
                let resp = try await edge.chat(
                    message: text,
                    chatId: chatId,
                    useWeb: useWeb,
                    knowledgeBaseFolderId: selectedKBFolderId,
                    attachmentPaths: uploadedPaths.isEmpty ? nil : uploadedPaths,
                    model: model
                )
                if chatId == nil { chatId = UUID(uuidString: resp.chat_id) }
                messages.append(.assistantText(id: UUID(), text: resp.reply))
            }
        } catch {
            self.error = error.localizedDescription
            messages.append(.assistantText(id: UUID(), text: "error: \(error.localizedDescription)"))
            await persistChat()
        }
    }

    enum AppError: LocalizedError {
        case notAuthed
        case missingHandwritingSample
        var errorDescription: String? {
            switch self {
            case .notAuthed: return "not signed in"
            case .missingHandwritingSample:
                return "replace-handwriting needs a saved sample. open the sidebar → handwriting library and add one."
            }
        }
    }
}
