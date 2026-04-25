import SwiftUI

// Optional onboarding — accessible from Library tab. Skip by default.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step: Int = 0

    var body: some View {
        NavigationStack {
            VStack {
                TabView(selection: $step) {
                    introCard.tag(0)
                    handwritingCard.tag(1)
                    knowledgeCard.tag(2)
                    doneCard.tag(3)
                }
                .tabViewStyle(.page)

                Button(step == 3 ? "let's go" : "next") {
                    if step == 3 { dismiss() } else { step += 1 }
                }
                .buttonStyle(.glassProminent)
                .padding()
            }
            .navigationTitle("welcome")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("skip") { dismiss() }
                }
            }
        }
    }

    private var introCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "pencil.and.scribble").font(.system(size: 80))
            Text("homework copilot")
                .font(.title.weight(.semibold))
            Text("upload a worksheet, pick an action, get it back in your handwriting.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .foregroundStyle(.secondary)
        }
    }

    private var handwritingCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "highlighter").font(.system(size: 80))
            Text("set up your handwriting")
                .font(.title2.weight(.semibold))
            Text("draw a sample or upload a photo. you can do this later in the library tab.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .foregroundStyle(.secondary)
            NavigationLink {
                AddHandwritingView { _ in }
            } label: {
                Text("add a sample")
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .glassEffect(in: .capsule)
            }
        }
    }

    private var knowledgeCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical").font(.system(size: 80))
            Text("knowledge base (optional)")
                .font(.title2.weight(.semibold))
            Text("upload notes or past worksheets — the agent uses them as context. completely optional.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .foregroundStyle(.secondary)
        }
    }

    private var doneCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles").font(.system(size: 80))
            Text("you're set")
                .font(.title.weight(.semibold))
            Text("pick an action on the home tab to start.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .foregroundStyle(.secondary)
        }
    }
}
