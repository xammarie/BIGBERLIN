import Foundation
import Supabase
import UIKit

enum StorageBucket: String {
    case handwriting
    case worksheetsInput = "worksheets-input"
    case worksheetsOutput = "worksheets-output"
    case kbFiles = "kb-files"
}

@MainActor
final class StorageService {
    static let shared = StorageService()
    private let supabase = SupabaseService.shared

    private init() {}

    /// Returns the storage path used (e.g. "{userId}/{filename}")
    @discardableResult
    func upload(
        image: UIImage,
        bucket: StorageBucket,
        subpath: String? = nil,
        compression: CGFloat = 0.9
    ) async throws -> String {
        guard let userId = supabase.currentUserId else {
            throw NSError(domain: "Storage", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        guard let data = image.jpegData(compressionQuality: compression) else {
            throw NSError(domain: "Storage", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])
        }
        let filename = "\(UUID().uuidString).jpg"
        let path: String
        if let subpath {
            path = "\(userId.uuidString.lowercased())/\(subpath)/\(filename)"
        } else {
            path = "\(userId.uuidString.lowercased())/\(filename)"
        }

        try await supabase.client.storage
            .from(bucket.rawValue)
            .upload(
                path: path,
                file: data,
                options: FileOptions(contentType: "image/jpeg", upsert: false)
            )

        return path
    }

    func download(bucket: StorageBucket, path: String) async throws -> Data {
        try await supabase.client.storage.from(bucket.rawValue).download(path: path)
    }

    func signedURL(bucket: StorageBucket, path: String, expiresIn seconds: Int = 3600) async throws -> URL {
        try await supabase.client.storage.from(bucket.rawValue)
            .createSignedURL(path: path, expiresIn: seconds)
    }
}
