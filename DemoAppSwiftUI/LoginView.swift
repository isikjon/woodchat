//
// WoodChat — внутренний мессенджер Woodstream.
//

import StreamChatSwiftUI
import SwiftUI

struct LoginView: View {
    @StateObject var viewModel = LoginViewModel()

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
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
        .overlay(
            viewModel.loading ? ProgressView() : nil
        )
        .sheet(isPresented: $viewModel.showsConfiguration) {
            AppConfigurationView()
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

struct DemoUserView: View {
    @Injected(\.fonts) var fonts
    @Injected(\.colors) var colors

    var user: UserCredentials

    private let imageSize: CGFloat = 44

    var body: some View {
        HStack {
            if user.isGuest {
                Image(systemName: "person.fill")
                    .resizable()
                    .foregroundColor(Color(colors.accentPrimary))
                    .frame(width: imageSize, height: imageSize)
                    .aspectRatio(contentMode: .fit)
                    .background(Color(colors.background6))
                    .clipShape(Circle())
            } else {
                UserAvatar(
                    url: user.avatarURL,
                    initials: "",
                    size: imageSize,
                    indicator: .none
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(user.name)
                    .font(fonts.bodyBold)
                Text(user.isGuest ? "Login as Guest" : "Stream test account")
                    .font(fonts.footnote)
                    .foregroundColor(Color(colors.textLowEmphasis))
            }

            Spacer()

            Image(systemName: "arrow.forward")
                .renderingMode(.template)
                .foregroundColor(Color(colors.accentPrimary))
        }
    }
}
