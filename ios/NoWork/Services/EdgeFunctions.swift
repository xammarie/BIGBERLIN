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

        // Retry transient gateway hiccups (502/503/504) — supabase fronts edge
        // functions through cloudflare and sometimes returns these on cold starts
        // or upstream timeouts even though the function itself is healthy.
        let retryableCodes: Set<Int> = [502, 503, 504]
        let backoffs: [UInt64] = [400_000_000, 1_200_000_000]
        var attempt = 0

        while true {
            do {
                return try await client.invoke(
                    name,
                    options: FunctionInvokeOptions(headers: headers, body: body)
                )
            } catch let err as FunctionsError {
                if case .httpError(let code, let data) = err {
                    if retryableCodes.contains(code), attempt < backoffs.count {
                        try? await Task.sleep(nanoseconds: backoffs[attempt])
                        attempt += 1
                        continue
                    }
                    if let str = String(data: data, encoding: .utf8) {
                        if let parsed = try? JSONDecoder().decode([String: String].self, from: data),
                           let msg = parsed["error"] ?? parsed["message"] {
                            throw RemoteError(code: code, message: msg)
                        }
                        throw RemoteError(code: code, message: str)
                    }
                }
                throw err
            }
        }
    }

    struct RemoteError: LocalizedError {
        let code: Int
        let message: String
        var errorDescription: String? {
            switch code {
            case 502, 503, 504:
                return "the AI is busy right now — try again in a sec"
            case 401:
                return "your session expired — please sign in again"
            case 413:
                return "image too large — try a smaller one"
            default:
                return "\(code): \(message)"
            }
        }
    }

    // MARK: - process-worksheet

    struct ProcessWorksheetResponse: Decodable {
        let status: String
        let session_id: String?
    }

    private struct ProcessWorksheetBody: Encodable {
        let session_id: String
        let model: String
    }

    func processWorksheet(
        sessionId: UUID,
        model: ModelMode = .fast
    ) async throws -> ProcessWorksheetResponse {
        try await invoke(
            "process-worksheet",
            body: ProcessWorksheetBody(
                session_id: sessionId.uuidString.lowercased(),
                model: model.rawValue
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
        let token: String?
        let websocket_url: String?
        let tts_url: String?
        let expires_at: String?
    }

    private struct EmptyBody: Encodable {}
    private struct VoiceSpeechBody: Encodable {
        let text: String
        let voice_id: String
    }

    func voiceToken() async throws -> VoiceToken {
        try await invoke("voice-token", body: EmptyBody())
    }

    func voiceSpeech(text: String, voiceId: String) async throws -> Data {
        var request = URLRequest(url: functionURL("voice-token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        if let token = supabase.session?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(
            VoiceSpeechBody(text: text, voice_id: voiceId)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }
        guard (200..<300).contains(http.statusCode) else {
            if let parsed = try? JSONDecoder().decode([String: String].self, from: data),
               let message = parsed["error"] ?? parsed["message"] {
                throw RemoteError(code: http.statusCode, message: message)
            }
            let message = String(data: data, encoding: .utf8) ?? "Voice request failed"
            throw RemoteError(code: http.statusCode, message: message)
        }
        return data
    }

    private func functionURL(_ name: String) -> URL {
        let url = Configuration.supabaseURL
        let scheme = url.scheme ?? "https"
        guard let host = url.host else { return url.appendingPathComponent(name) }
        if host.hasSuffix(".supabase.co") {
            let functionsHost = host.replacingOccurrences(
                of: ".supabase.co",
                with: ".functions.supabase.co"
            )
            return URL(string: "\(scheme)://\(functionsHost)/\(name)")!
        }
        return url.appendingPathComponent("functions/v1/\(name)")
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
