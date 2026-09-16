//
// WoodChat — внутренний мессенджер Woodstream.
//

import StreamChatSwiftUI
import SwiftUI

struct LoginView: View {
    @StateObject var viewModel = LoginViewModel()
    @State private var showsRegistration = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("WoodChat")
                .font(.system(size: 34, weight: .bold))
                .padding(.bottom, 4)

            Text("Мессенджер Woodstream")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 32)

            VStack(spacing: 12) {
                TextField("Email", text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)

                SecureField("Пароль", text: $viewModel.password)
                    .textContentType(.password)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    viewModel.login()
                } label: {
                    Text("Войти")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.loading)

                Button {
                    showsRegistration = true
                } label: {
                    Text("Создать учётную запись")
                        .font(.subheadline)
                }
                .disabled(viewModel.loading)
                .padding(.top, 4)

                // Согласие с правилами до входа — требование App Review (1.2)
                EulaNotice(actionTitle: "Войти")
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
        .overlay(
            viewModel.loading ? ProgressView() : nil
        )
        .sheet(isPresented: $showsRegistration) {
            RegisterView()
        }
        .onAppear {
            #if DEBUG
            // Автовход для автотестов: только Debug-сборка, только при заданных переменных окружения
            let env = ProcessInfo.processInfo.environment
            if let email = env["WOODCHAT_TEST_EMAIL"],
               let password = env["WOODCHAT_TEST_PASSWORD"],
               !viewModel.loading {
                viewModel.email = email
                viewModel.password = password
                viewModel.login()
            }
            #endif
        }
    }
}
