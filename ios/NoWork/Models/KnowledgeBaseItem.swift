import Foundation

struct KnowledgeBaseItem: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let folderId: UUID?
    let storagePath: String
    let filename: String
    let mimeType: String?
    let metadata: [String: String]?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case folderId = "folder_id"
        case storagePath = "storage_path"
        case filename
        case mimeType = "mime_type"
        case metadata
        case createdAt = "created_at"
    }
}
