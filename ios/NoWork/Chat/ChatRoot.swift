import SwiftUI

struct ChatRoot: View {
    @StateObject private var vm = ChatViewModel()
    @State private var showSidebar = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                Group {
                    if vm.messages.isEmpty {
                        EmptyHome(vm: vm)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        MessagesScroll(vm: vm)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    PromptBar(vm: vm, inputFocused: $inputFocused)
                        .padding(.horizontal, 14)
                        .padding(.top, 6)
                        .padding(.bottom, 10)
                        .background(
                            Color(.systemBackground)
                                .opacity(inputFocused ? 1 : 0)
                        )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSidebar = true } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.headline)
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                            .clipShape(.rect(cornerRadius: 6, style: .continuous))
                        Text("NoWork")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { startNewChat() } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.headline)
                    }
                }
            }
            .sheet(isPresented: $showSidebar) {
                SidebarView { chatId in
                    showSidebar = false
                    if let chatId {
                        loadExistingChat(id: chatId)
                    } else {
                        startNewChat()
                    }
                }
            }
        }
    }

    private func startNewChat() {
        vm.chatId = nil
        vm.messages = []
        vm.input = ""
        vm.clearAttachments()
        vm.pendingAction = nil
        vm.error = nil
    }

    private func loadExistingChat(id: UUID) {
        vm.messages = []
        Task { await vm.loadChat(id) }
    }
}

struct EmptyHome: View {
    @ObservedObject var vm: ChatViewModel
    @Environment(\.horizontalSizeClass) private var hSize

    private var isWide: Bool { hSize == .regular }

    var body: some View {
        VStack(alignment: isWide ? .center : .leading, spacing: 28) {
            Spacer().frame(height: 8)

            Text(isWide ? "What do you want to NoWork on?" : "What do you want\nto NoWork on?")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .multilineTextAlignment(isWide ? .center : .leading)
                .lineLimit(isWide ? 1 : nil)
                .minimumScaleFactor(isWide ? 0.7 : 1)
                .frame(maxWidth: .infinity, alignment: isWide ? .center : .leading)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            chipsContainer

            if let err = vm.error {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: isWide ? .center : .leading)
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var chipsContainer: some View {
        let chips = FlowLayout(spacing: 10, alignment: isWide ? .center : .leading) {
            ForEach(WorksheetAction.allCases) { action in
                ActionChip(
                    action: action,
                    isSelected: vm.pendingAction == action
                ) {
                    vm.toggleAction(action)
                }
            }
        }

        if isWide {
            chips
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 18)
        } else {
            chips.padding(.horizontal, 18)
        }
    }
}

struct ActionChip: View {
    let action: WorksheetAction
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: action.systemImage)
                    .font(.subheadline.weight(.medium))
                Text(action.displayName)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background {
                if isSelected {
                    Capsule().fill(Color.accentColor)
                }
            }
            .glassEffect(in: .capsule)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.18), value: isSelected)
    }
}

/// Wraps chips in lines like the wireframe: each chip takes its content width,
/// flowing to the next line when it doesn't fit. Each row is independently
/// aligned (leading or center) within the container width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let arranged = arrange(maxWidth: maxWidth, subviews: subviews)
        return CGSize(width: maxWidth.isFinite ? maxWidth : arranged.contentWidth, height: arranged.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arranged = arrange(maxWidth: bounds.width, subviews: subviews)
        for (i, frame) in arranged.frames.enumerated() {
            subviews[i].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(
        maxWidth: CGFloat,
        subviews: Subviews
    ) -> (frames: [CGRect], contentWidth: CGFloat, height: CGFloat) {
        var rows: [Row] = [Row()]
        var sizes: [CGSize] = []

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)
            let prospectiveWidth = rows[rows.count - 1].width
                + (rows[rows.count - 1].indices.isEmpty ? 0 : spacing)
                + size.width
            if prospectiveWidth > maxWidth, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let i = rows.count - 1
            if !rows[i].indices.isEmpty { rows[i].width += spacing }
            rows[i].indices.append(index)
            rows[i].width += size.width
            rows[i].height = max(rows[i].height, size.height)
        }

        var frames: [CGRect] = Array(repeating: .zero, count: subviews.count)
        var y: CGFloat = 0
        var contentWidth: CGFloat = 0
        for (idx, row) in rows.enumerated() {
            let startX: CGFloat
            switch alignment {
            case .center:
                startX = max(0, (maxWidth - row.width) / 2)
            case .trailing:
                startX = max(0, maxWidth - row.width)
            default:
                startX = 0
            }
            var x: CGFloat = startX
            for (k, sIdx) in row.indices.enumerated() {
                if k > 0 { x += spacing }
                frames[sIdx] = CGRect(origin: CGPoint(x: x, y: y), size: sizes[sIdx])
                x += sizes[sIdx].width
            }
            contentWidth = max(contentWidth, row.width)
            y += row.height
            if idx < rows.count - 1 { y += spacing }
        }

        return (frames, contentWidth, y)
    }
}

struct MessagesScroll: View {
    @ObservedObject var vm: ChatViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    Spacer().frame(height: 8)
                    ForEach(vm.messages) { msg in
                        MessageRow(message: msg).id(msg.id)
                    }
                    if vm.isWorking {
                        TypingIndicator()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                    }
                    Spacer().frame(height: 8)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.messages.count) { _, _ in
                if let last = vm.messages.last {
                    withAnimation(.snappy) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct TypingIndicator: View {
    @State private var bounce = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(bounce ? 0.3 : 0.9)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(i) * 0.15),
                        value: bounce
                    )
            }
        }
        .onAppear { bounce = true }
    }
}

struct MessageRow: View {
    let message: DisplayMessage

    var body: some View {
        switch message {
        case .userText(_, let text, let paths):
            UserBubble(text: text, attachmentPaths: paths)
        case .assistantText(_, let text):
            AssistantText(text: text)
        case .worksheetSession(_, let sessionId, let action):
            SessionCard(sessionId: sessionId, action: action)
        case .videoJob(_, let jobId, let prompt):
            VideoJobCard(jobId: jobId, prompt: prompt)
        }
    }
}

struct UserBubble: View {
    let text: String
    let attachmentPaths: [String]

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 8) {
                if !attachmentPaths.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(attachmentPaths.prefix(3), id: \.self) { path in
                            AsyncStorageImage(bucket: .worksheetsInput, path: path)
                                .frame(width: 80, height: 110)
                                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                if !text.isEmpty {
                    Text(text)
                        .font(.body)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.accentColor)
                        )
                        .foregroundStyle(Color.white)
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

struct AssistantText: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkle")
                .font(.footnote)
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }
}

struct SessionCard: View {
    let sessionId: UUID
    let action: WorksheetAction

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: action.systemImage)
                .font(.footnote)
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 8) {
                Text(action.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                SessionDetailView(sessionId: sessionId)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }
}

struct VideoJobCard: View {
    let jobId: String
    let prompt: String
    @State private var status: String = "starting…"
    @State private var videoUrl: URL?
    @State private var error: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "play.rectangle.fill")
                .font(.footnote)
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))

            VStack(alignment: .leading, spacing: 8) {
                Text("Explainer video")
                    .font(.subheadline.weight(.semibold))
                Text(prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                if let url = videoUrl {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text("watch")
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(Color.white)
                    }
                } else if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(status).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .task { await poll() }
    }

    private func poll() async {
        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(5))
            do {
                let job = try await EdgeFunctions.shared.videoStatus(jobId: jobId)
                status = job.status
                if let urlStr = job.resolvedVideoUrl, let url = URL(string: urlStr) {
                    videoUrl = url
                    return
                }
                if job.status == "failed" {
                    error = job.error ?? "failed"
                    return
                }
            } catch {
                self.error = error.localizedDescription
                return
            }
        }
    }
}
