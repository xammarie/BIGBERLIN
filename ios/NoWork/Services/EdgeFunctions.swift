import Foundation
import Supabase

@MainActor
final class EdgeFunctions {
    static let shared = EdgeFunctions()
    private let supabase = SupabaseService.shared
    private init() {}

    private var client: FunctionsClient { supabase.client.functions }

    /// Wraps `client.invoke` so that 4xx/5xx responses surface the server's
    /// JSON `error` field instead of the opaque "non-2xx status code: NNN".
    /// Also explicitly attaches the current access token — supabase-swift's
    /// FunctionsClient doesn't always inject it for `invoke`, so the edge
    /// function would see only the anon key and reject with 401.
    private func invoke<T: Decodable>(
        _ name: String,
        body: some Encodable
    ) async throws -> T {
        var headers: [String: String] = [:]
        if let token = supabase.session?.accessToken {
            headers["Authorization"] = "Bearer \(token)"
        }
        do {
            return try await client.invoke(
                name,
                options: FunctionInvokeOptions(headers: headers, body: body)
            )
        } catch let err as FunctionsError {
            if case .httpError(let code, let data) = err,
               let str = String(data: data, encoding: .utf8) {
                if let parsed = try? JSONDecoder().decode([String: String].self, from: data),
                   let msg = parsed["error"] ?? parsed["message"] {
                    throw RemoteError(code: code, message: msg)
                }
                throw RemoteError(code: code, message: str)
            }
            throw err
        }
    }

    struct RemoteError: LocalizedError {
        let code: Int
        let message: String
        var errorDescription: String? { "\(code): \(message)" }
    }

    // MARK: - process-worksheet

    struct ProcessWorksheetResponse: Decodable {
        let status: String
        let session_id: String?
    }

    private struct ProcessWorksheetBody: Encodable {
        let session_id: String
    }

    func processWorksheet(sessionId: UUID) async throws -> ProcessWorksheetResponse {
        try await invoke(
            "process-worksheet",
            body: ProcessWorksheetBody(session_id: sessionId.uuidString.lowercased())
        )
    }

    // MARK: - chat

    struct ChatResponse: Decodable {
        let chat_id: String
        let reply: String
        let used_web: Bool
        let kb_used: Bool?
        let attachments_count: Int?
    }

    private struct ChatBody: Encodable {
        let message: String
        let use_web: Bool
        let chat_id: String?
        let session_id: String?
        let knowledge_base_folder_id: String?
        let attachment_paths: [String]?
        let model: String
    }

    func chat(
        message: String,
        chatId: UUID? = nil,
        useWeb: Bool = false,
        sessionId: UUID? = nil,
        knowledgeBaseFolderId: UUID? = nil,
        attachmentPaths: [String]? = nil,
        model: ModelMode = .fast
    ) async throws -> ChatResponse {
        let body = ChatBody(
            message: message,
            use_web: useWeb,
            chat_id: chatId?.uuidString.lowercased(),
            session_id: sessionId?.uuidString.lowercased(),
            knowledge_base_folder_id: knowledgeBaseFolderId?.uuidString.lowercased(),
            attachment_paths: attachmentPaths,
            model: model.rawValue
        )
        return try await invoke("chat", body: body)
    }

    // MARK: - research

    struct ResearchResult: Decodable {
        struct Item: Decodable {
            let title: String
            let url: String
            let content: String
        }
        let answer: String?
        let results: [Item]
    }

    private struct ResearchBody: Encodable {
        let query: String
        let depth: String
    }

    func research(query: String, depth: String = "basic") async throws -> ResearchResult {
        try await invoke("research", body: ResearchBody(query: query, depth: depth))
    }

    // MARK: - voice-token

    struct VoiceToken: Decodable {
        let mode: String
        let token: String
        let websocket_url: String?
        let expires_at: String?
    }

    private struct EmptyBody: Encodable {}

    func voiceToken() async throws -> VoiceToken {
        try await invoke("voice-token", body: EmptyBody())
    }

    // MARK: - generate-video

    struct VideoStartResponse: Decodable {
        let job_id: String?
        let status: String
        let prompt: String?
    }

    struct VideoJobStatus: Decodable {
        let jobId: String?
        let status: String
        let videoUrl: String?
        let video_url: String?
        let error: String?

        var resolvedVideoUrl: String? { videoUrl ?? video_url }
    }

    private struct StartVideoBody: Encodable {
        let topic: String
        let duration_seconds: Int
        let chat_id: String?
        let knowledge_base_folder_id: String?
        let use_web: Bool
    }

    private struct VideoStatusBody: Encodable {
        let job_id: String
    }

    func startVideo(
        topic: String,
        durationSeconds: Int = 8,
        chatId: UUID? = nil,
        knowledgeBaseFolderId: UUID? = nil,
        useWeb: Bool = false
    ) async throws -> VideoStartResponse {
        let boundedDuration = min(max(durationSeconds, 4), 12)
        return try await invoke("generate-video", body: StartVideoBody(
            topic: topic,
            duration_seconds: boundedDuration,
            chat_id: chatId?.uuidString.lowercased(),
            knowledge_base_folder_id: knowledgeBaseFolderId?.uuidString.lowercased(),
            use_web: useWeb
        ))
    }

    func videoStatus(jobId: String) async throws -> VideoJobStatus {
        try await invoke("generate-video", body: VideoStatusBody(job_id: jobId))
    }
}
