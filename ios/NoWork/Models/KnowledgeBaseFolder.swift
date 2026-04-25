import Foundation

struct KnowledgeBaseFolder: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var name: String
    var isDefault: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case isDefault = "is_default"
        case createdAt = "created_at"
    }
}
