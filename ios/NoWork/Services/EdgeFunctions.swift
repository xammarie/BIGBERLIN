import Foundation
import Supabase

@MainActor
final class EdgeFunctions {
    static let shared = EdgeFunctions()
    private let supabase = SupabaseService.shared
    private init() {}

    private var client: FunctionsClient { supabase.client.functions }

    // MARK: - process-worksheet

    struct ProcessWorksheetResponse: Decodable {
        let status: String
        let session_id: String?
    }

    private struct ProcessWorksheetBody: Encodable {
        let session_id: String
    }

    func processWorksheet(sessionId: UUID) async throws -> ProcessWorksheetResponse {
        try await client.invoke(
            "process-worksheet",
            options: FunctionInvokeOptions(
                body: ProcessWorksheetBody(session_id: sessionId.uuidString.lowercased())
            )
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
    }

    func chat(
        message: String,
        chatId: UUID? = nil,
        useWeb: Bool = false,
        sessionId: UUID? = nil,
        knowledgeBaseFolderId: UUID? = nil,
        attachmentPaths: [String]? = nil
    ) async throws -> ChatResponse {
        let body = ChatBody(
            message: message,
            use_web: useWeb,
            chat_id: chatId?.uuidString.lowercased(),
            session_id: sessionId?.uuidString.lowercased(),
            knowledge_base_folder_id: knowledgeBaseFolderId?.uuidString.lowercased(),
            attachment_paths: attachmentPaths
        )
        return try await client.invoke(
            "chat",
            options: FunctionInvokeOptions(body: body)
        )
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
        try await client.invoke(
            "research",
            options: FunctionInvokeOptions(body: ResearchBody(query: query, depth: depth))
        )
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
        try await client.invoke(
            "voice-token",
            options: FunctionInvokeOptions(body: EmptyBody())
        )
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
        try await client.invoke(
            "generate-video",
            options: FunctionInvokeOptions(body: StartVideoBody(
                topic: topic,
                duration_seconds: durationSeconds,
                chat_id: chatId?.uuidString.lowercased(),
                knowledge_base_folder_id: knowledgeBaseFolderId?.uuidString.lowercased(),
                use_web: useWeb
            ))
        )
    }

    func videoStatus(jobId: String) async throws -> VideoJobStatus {
        try await client.invoke(
            "generate-video",
            options: FunctionInvokeOptions(body: VideoStatusBody(job_id: jobId))
        )
    }
}
