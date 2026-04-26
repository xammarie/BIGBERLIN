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
        compression: CGFloat = 0.95
    ) async throws -> String {
        guard let userId = supabase.currentUserId else {
            throw NSError(domain: "Storage", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        let data = try Self.jpegDataForUpload(image: image, compression: compression)
        let filename = "\(UUID().uuidString).jpg"
        let path: String
        if let subpath {
            path = "\(userId.uuidString.lowercased())/\(try Self.safePathSegment(subpath))/\(filename)"
        } else {
            path = "\(userId.uuidString.lowercased())/\(filename)"
        }

        try await supabase.client.storage
            .from(bucket.rawValue)
            .upload(
                path,
                data: data,
                options: FileOptions(contentType: "image/jpeg", upsert: false)
            )

        return path
    }

    func download(bucket: StorageBucket, path: String) async throws -> Data {
        try validateOwnedPath(path)
        return try await supabase.client.storage.from(bucket.rawValue).download(path: path)
    }

    func signedURL(bucket: StorageBucket, path: String, expiresIn seconds: Int = 3600) async throws -> URL {
        try validateOwnedPath(path)
        let boundedSeconds = min(max(seconds, 60), 3600)
        return try await supabase.client.storage.from(bucket.rawValue)
            .createSignedURL(path: path, expiresIn: boundedSeconds)
    }

    private func validateOwnedPath(_ path: String) throws {
        guard let userId = supabase.currentUserId else {
            throw NSError(domain: "Storage", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        let prefix = "\(userId.uuidString.lowercased())/"
        guard path.hasPrefix(prefix),
              !path.contains(".."),
              !path.contains("//"),
              !path.hasPrefix("/") else {
            throw NSError(domain: "Storage", code: 403,
                          userInfo: [NSLocalizedDescriptionKey: "Storage path is not owned by the current user"])
        }
    }

    private static func safePathSegment(_ segment: String) throws -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard !segment.isEmpty,
              segment.count <= 80,
              segment.rangeOfCharacter(from: allowed.inverted) == nil else {
            throw NSError(domain: "Storage", code: 400,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid upload path"])
        }
        return segment
    }

    private static func jpegDataForUpload(image: UIImage, compression: CGFloat) throws -> Data {
        let resized = image.resizedForUpload(maxDimension: 2400)
        var quality = min(max(compression, 0.35), 0.95)
        guard var data = resized.jpegData(compressionQuality: quality) else {
            throw NSError(domain: "Storage", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])
        }
        while data.count > 7_500_000 && quality > 0.55 {
            quality -= 0.1
            guard let recompressed = resized.jpegData(compressionQuality: quality) else { break }
            data = recompressed
        }
        if data.count > 8_000_000 {
            throw NSError(domain: "Storage", code: 413,
                          userInfo: [NSLocalizedDescriptionKey: "Image is too large to upload"])
        }
        return data
    }
}

private extension UIImage {
    func resizedForUpload(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: target)).fill()
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
