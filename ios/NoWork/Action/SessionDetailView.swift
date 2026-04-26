import SwiftUI

struct SessionDetailView: View {
    let sessionId: UUID

    @StateObject private var vm: SessionDetailViewModel

    init(sessionId: UUID) {
        self.sessionId = sessionId
        _vm = StateObject(wrappedValue: SessionDetailViewModel(sessionId: sessionId))
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                statusBadge
                Spacer()
            }

            if vm.outputImages.isEmpty && vm.status != .complete {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(vm.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
                .glassEffect(in: .rect(cornerRadius: 28, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(vm.outputImages) { output in
                            OutputImageCard(output: output)
                        }
                    }
                }
            }

            if let error = vm.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .task { await vm.start() }
    }

    @ViewBuilder
    private var statusBadge: some View {
        Label(vm.status.rawValue.capitalized, systemImage: statusIcon)
            .font(.footnote)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(in: .capsule)
    }

    private var statusIcon: String {
        switch vm.status {
        case .pending: return "hourglass"
        case .processing: return "wand.and.stars"
        case .complete: return "checkmark.seal.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

struct WorksheetOutputImage: Identifiable {
    let id: UUID
    let image: UIImage
    let fileURL: URL
}

private struct OutputImageCard: View {
    let output: WorksheetOutputImage

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: output.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 320, maxHeight: 420)
                .clipShape(.rect(cornerRadius: 22, style: .continuous))

            ShareLink(
                item: output.fileURL,
                preview: SharePreview(
                    "Worksheet output",
                    image: Image(uiImage: output.image)
                )
            ) {
                Image(systemName: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 38, height: 38)
                    .foregroundStyle(Color.primary)
                    .background(Circle().fill(.regularMaterial))
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }
}

@MainActor
final class SessionDetailViewModel: ObservableObject {
    let sessionId: UUID
    @Published var status: SessionStatus = .pending
    @Published var outputImages: [WorksheetOutputImage] = []
    @Published var error: String?
    @Published var statusText: String = "uploading…"

    private let supabase = SupabaseService.shared
    private let storage = StorageService.shared
    private let edge = EdgeFunctions.shared
    private var pollTask: Task<Void, Never>?
    private var retryRequested = false

    private struct SessionInputRef: Decodable {
        let id: UUID
    }

    private struct CompleteSessionUpdate: Encodable {
        let status: String
        let completed_at: Date
    }

    init(sessionId: UUID) {
        self.sessionId = sessionId
    }

    func start() async {
        await refresh()
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await self.refresh()
                if self.status == .complete || self.status == .failed { break }
            }
        }
    }

    deinit {
        pollTask?.cancel()
    }

    private func refresh() async {
        do {
            let session: WorksheetSession = try await supabase.client
                .from("sessions")
                .select()
                .eq("id", value: sessionId.uuidString.lowercased())
                .single()
                .execute()
                .value

            let remoteStatus = session.status
            status = remoteStatus
            switch status {
            case .pending: statusText = "queued…"
            case .processing: statusText = "thinking + drawing…"
            case .complete: statusText = "done"
            case .failed: statusText = session.error ?? "something broke"
            }

            if status != .failed {
                let outputCount = try await refreshOutputs(remoteStatus: remoteStatus)
                if remoteStatus == .processing,
                   outputCount == 0,
                   !retryRequested,
                   Date().timeIntervalSince(session.createdAt) > 240 {
                    retryRequested = true
                    statusText = "retrying…"
                    _ = try? await edge.processWorksheet(sessionId: sessionId, model: .fast)
                }
            }
            if status == .failed {
                error = session.error
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refreshOutputs(remoteStatus: SessionStatus) async throws -> Int {
        let outputs: [SessionOutput] = try await supabase.client
            .from("session_outputs")
            .select()
            .eq("session_id", value: sessionId.uuidString.lowercased())
            .order("created_at", ascending: true)
            .execute()
            .value

        if !outputs.isEmpty,
           outputImages.isEmpty || outputImages.count != outputs.count {
            outputImages = try await loadOutputImages(outputs)
        }

        guard !outputs.isEmpty else { return 0 }

        let inputs: [SessionInputRef] = try await supabase.client
            .from("session_inputs")
            .select("id")
            .eq("session_id", value: sessionId.uuidString.lowercased())
            .execute()
            .value

        if !inputs.isEmpty && outputs.count >= inputs.count {
            status = .complete
            statusText = "done"
            error = nil
            if remoteStatus != .complete {
                await markSessionComplete()
            }
        }
        return outputs.count
    }

    private func loadOutputImages(_ outputs: [SessionOutput]) async throws -> [WorksheetOutputImage] {
        var loaded: [WorksheetOutputImage] = []
        for (index, output) in outputs.enumerated() {
            let data = try await storage.download(
                bucket: .worksheetsOutput,
                path: output.storagePath
            )
            if let image = UIImage(data: data) {
                let fileURL = try writeDownloadFile(
                    data: data,
                    output: output,
                    index: index
                )
                loaded.append(WorksheetOutputImage(
                    id: output.id,
                    image: image,
                    fileURL: fileURL
                ))
            }
        }
        return loaded
    }

    private func markSessionComplete() async {
        do {
            try await supabase.client
                .from("sessions")
                .update(CompleteSessionUpdate(
                    status: SessionStatus.complete.rawValue,
                    completed_at: Date()
                ))
                .eq("id", value: sessionId.uuidString.lowercased())
                .execute()
        } catch {
            // Non-fatal: UI can still show/download the completed outputs.
        }
    }

    private func writeDownloadFile(
        data: Data,
        output: SessionOutput,
        index: Int
    ) throws -> URL {
        let ext = outputFileExtension(for: output.storagePath)
        let filename = "nowork-\(sessionId.uuidString.lowercased())-\(index + 1).\(ext)"
        let url = try safeTemporaryDownloadURL(filename: filename)
        try data.write(to: url, options: [.atomic])
        return url
    }

    private func outputFileExtension(for storagePath: String) -> String {
        switch storagePath.lowercased().split(separator: ".").last.map(String.init) {
        case "jpg", "jpeg":
            return "jpg"
        case "webp":
            return "webp"
        default:
            return "png"
        }
    }

    private func safeTemporaryDownloadURL(filename: String) throws -> URL {
        guard filename.range(
            of: #"^[A-Za-z0-9._-]{1,140}$"#,
            options: .regularExpression
        ) != nil else {
            throw NSError(
                domain: "Downloads",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid download filename"]
            )
        }
        let directory = FileManager.default.temporaryDirectory.standardizedFileURL
        let url = directory
            .appendingPathComponent(filename, isDirectory: false)
            .standardizedFileURL
        let directoryPath = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        guard url.path.hasPrefix(directoryPath) else {
            throw NSError(
                domain: "Downloads",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid download path"]
            )
        }
        return url
    }
}
