import Foundation

enum SessionStatus: String, Codable {
    case pending
    case processing
    case complete
    case failed
}

struct WorksheetSession: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let action: WorksheetAction
    let status: SessionStatus
    let mode: HandwritingMode
    let handwritingSampleId: UUID?
    let error: String?
    let createdAt: Date
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case action
        case status
        case mode
        case handwritingSampleId = "handwriting_sample_id"
        case error
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }
}

struct SessionInput: Codable, Identifiable, Hashable {
    let id: UUID
    let sessionId: UUID
    let storagePath: String
    let order: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case storagePath = "storage_path"
        case order
        case createdAt = "created_at"
    }
}

struct SessionOutput: Codable, Identifiable, Hashable {
    let id: UUID
    let sessionId: UUID
    let sourceInputId: UUID?
    let storagePath: String
    let promptUsed: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case sourceInputId = "source_input_id"
        case storagePath = "storage_path"
        case promptUsed = "prompt_used"
        case createdAt = "created_at"
    }
}
