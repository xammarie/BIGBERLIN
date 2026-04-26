import SwiftUI

struct AuthView: View {
    @EnvironmentObject var supabase: SupabaseService
    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .signIn
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focused: Field?

    enum Mode { case signIn, signUp }
    enum Field { case email, password }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: max(40, geo.size.height * 0.08))

                    VStack(spacing: 14) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .clipShape(.rect(cornerRadius: 22, style: .continuous))
                        Text("NoWork")
                            .font(.largeTitle.weight(.bold))
                        Text("your homework, in your handwriting")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 14) {
                        TextField("email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focused = .password }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 18)
                            .glassEffect(in: .capsule)

                        SecureField("password", text: $password)
                            .textContentType(mode == .signUp ? .newPassword : .password)
                            .focused($focused, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { submit() }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 18)
                            .glassEffect(in: .capsule)
                    }
                    .frame(maxWidth: 480)

                    Button(action: submit) {
                        HStack(spacing: 10) {
                            if isWorking { ProgressView().controlSize(.small) }
                            Text(mode == .signIn ? "sign in" : "create account")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.glassProminent)
                    .clipShape(.capsule)
                    .frame(maxWidth: 480)
                    .disabled(isWorking || email.isEmpty || password.isEmpty)

                    Button {
                        mode = (mode == .signIn) ? .signUp : .signIn
                        errorMessage = nil
                    } label: {
                        Text(mode == .signIn ? "no account? sign up" : "have an account? sign in")
                            .font(.subheadline)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .glassEffect(in: .capsule)
                    }
                    .foregroundStyle(.primary)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(14)
                            .glassEffect(in: .capsule)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func submit() {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty, !password.isEmpty else { return }
        guard mode == .signIn || password.count >= 8 else {
            errorMessage = "password must be at least 8 characters"
            return
        }
        Task {
            isWorking = true
            errorMessage = nil
            defer { isWorking = false }
            do {
                switch mode {
                case .signIn:
                    try await supabase.signIn(email: normalizedEmail, password: password)
                case .signUp:
                    try await supabase.signUp(email: normalizedEmail, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
