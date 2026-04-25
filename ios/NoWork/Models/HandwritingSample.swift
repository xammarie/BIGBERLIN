import Foundation

struct HandwritingSample: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var name: String
    let storagePath: String
    var isDefault: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case storagePath = "storage_path"
        case isDefault = "is_default"
        case createdAt = "created_at"
    }
}
