import Foundation

struct ChatMessage: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    let role: Role
    let content: String
    let timestamp: Date

    enum Role: String, Codable {
        case user
        case assistant
    }

    private enum CodingKeys: String, CodingKey {
        case role, content, timestamp
    }
}

struct Chat: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let sessionId: UUID?
    let messages: [ChatMessage]
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case sessionId = "session_id"
        case messages
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
