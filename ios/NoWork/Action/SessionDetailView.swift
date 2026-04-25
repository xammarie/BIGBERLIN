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
                        ForEach(Array(vm.outputImages.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 320, maxHeight: 420)
                                .clipShape(.rect(cornerRadius: 22, style: .continuous))
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

@MainActor
final class SessionDetailViewModel: ObservableObject {
    let sessionId: UUID
    @Published var status: SessionStatus = .pending
    @Published var outputImages: [UIImage] = []
    @Published var error: String?
    @Published var statusText: String = "uploading…"

    private let supabase = SupabaseService.shared
    private let storage = StorageService.shared
    private var pollTask: Task<Void, Never>?

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

            status = session.status
            switch status {
            case .pending: statusText = "queued…"
            case .processing: statusText = "thinking + drawing…"
            case .complete: statusText = "done"
            case .failed: statusText = session.error ?? "something broke"
            }

            if status == .complete && outputImages.isEmpty {
                let outputs: [SessionOutput] = try await supabase.client
                    .from("session_outputs")
                    .select()
                    .eq("session_id", value: sessionId.uuidString.lowercased())
                    .order("created_at", ascending: true)
                    .execute()
                    .value

                var loaded: [UIImage] = []
                for o in outputs {
                    let data = try await storage.download(bucket: .worksheetsOutput, path: o.storagePath)
                    if let img = UIImage(data: data) { loaded.append(img) }
                }
                outputImages = loaded
            }
            if status == .failed {
                error = session.error
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
