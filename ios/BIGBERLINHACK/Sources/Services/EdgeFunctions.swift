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

    func processWorksheet(sessionId: UUID) async throws -> ProcessWorksheetResponse {
        try await client.invoke(
            "process-worksheet",
            options: FunctionInvokeOptions(
                body: ["session_id": sessionId.uuidString.lowercased()]
            )
        )
    }

    // MARK: - chat

    struct ChatResponse: Decodable {
        let chat_id: String
        let reply: String
        let used_web: Bool
    }

    func chat(message: String, chatId: UUID? = nil, useWeb: Bool = false, sessionId: UUID? = nil) async throws -> ChatResponse {
        var body: [String: Any] = ["message": message, "use_web": useWeb]
        if let chatId { body["chat_id"] = chatId.uuidString.lowercased() }
        if let sessionId { body["session_id"] = sessionId.uuidString.lowercased() }
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

    func research(query: String, depth: String = "basic") async throws -> ResearchResult {
        try await client.invoke(
            "research",
            options: FunctionInvokeOptions(body: ["query": query, "depth": depth])
        )
    }

    // MARK: - voice-token

    struct VoiceToken: Decodable {
        let mode: String
        let token: String
        let websocket_url: String?
        let expires_at: String?
    }

    func voiceToken() async throws -> VoiceToken {
        try await client.invoke(
            "voice-token",
            options: FunctionInvokeOptions(body: [String: String]())
        )
    }

    // MARK: - generate-video

    struct VideoJob: Decodable {
        let job_id: String?
        let jobId: String?
        let status: String
        let video_url: String?
        let videoUrl: String?
        let error: String?

        var resolvedJobId: String? { job_id ?? jobId }
        var resolvedVideoUrl: String? { video_url ?? videoUrl }
    }

    func startVideo(topic: String, durationSeconds: Int = 8) async throws -> VideoJob {
        try await client.invoke(
            "generate-video",
            options: FunctionInvokeOptions(body: [
                "topic": topic,
                "duration_seconds": durationSeconds,
            ])
        )
    }

    func videoStatus(jobId: String) async throws -> VideoJob {
        try await client.invoke(
            "generate-video",
            options: FunctionInvokeOptions(body: ["job_id": jobId])
        )
    }
}
