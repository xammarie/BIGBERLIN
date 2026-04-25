import Foundation

struct ChatMessage: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    let role: Role
    let content: String
    let timestamp: Date
    var attachmentPaths: [String]?

    enum Role: String, Codable {
        case user
        case assistant
    }

    private enum CodingKeys: String, CodingKey {
        case role, content, timestamp
        case attachmentPaths = "attachment_paths"
    }
}

struct Chat: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let sessionId: UUID?
    let knowledgeBaseFolderId: UUID?
    var title: String?
    let messages: [ChatMessage]
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case sessionId = "session_id"
        case knowledgeBaseFolderId = "knowledge_base_folder_id"
        case title
        case messages
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ChatSummary: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case updatedAt = "updated_at"
    }
}
