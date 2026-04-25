import SwiftUI

struct AsyncStorageImage: View {
    let bucket: StorageBucket
    let path: String
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.tertiary)
            } else {
                ProgressView()
            }
        }
        .task(id: path) {
            do {
                let data = try await StorageService.shared.download(bucket: bucket, path: path)
                image = UIImage(data: data)
            } catch {
                failed = true
            }
        }
    }
}
