import SwiftUI

struct AuthView: View {
    @EnvironmentObject var supabase: SupabaseService
    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .signIn
    @State private var isWorking = false
    @State private var errorMessage: String?

    enum Mode { case signIn, signUp }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "pencil.and.scribble")
                    .font(.system(size: 56, weight: .light))
                Text("homework copilot")
                    .font(.title2.weight(.semibold))
                Text("worksheets, your handwriting")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                TextField("email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .glassEffect(in: .rect(cornerRadius: 14))

                SecureField("password", text: $password)
                    .textContentType(mode == .signUp ? .newPassword : .password)
                    .padding(14)
                    .glassEffect(in: .rect(cornerRadius: 14))
            }
            .padding(.horizontal)

            Button(action: submit) {
                HStack {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text(mode == .signIn ? "sign in" : "create account")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .disabled(isWorking || email.isEmpty || password.isEmpty)
            .padding(.horizontal)

            Button {
                mode = (mode == .signIn) ? .signUp : .signIn
                errorMessage = nil
            } label: {
                Text(mode == .signIn ? "no account? sign up" : "have account? sign in")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Spacer()
        }
        .padding()
    }

    private func submit() {
        Task {
            isWorking = true
            errorMessage = nil
            defer { isWorking = false }
            do {
                switch mode {
                case .signIn:
                    try await supabase.signIn(email: email, password: password)
                case .signUp:
                    try await supabase.signUp(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
