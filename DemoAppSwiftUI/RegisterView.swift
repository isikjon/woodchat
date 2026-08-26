//
// WoodChat — внутренний мессенджер Woodstream.
//

import StreamChat
import StreamChatSwiftUI
import SwiftUI

@MainActor final class RegisterViewModel: ObservableObject {
    @Published var name = ""
    @Published var email = ""
    @Published var password = ""
    @Published var loading = false
    @Published var errorMessage: String?

    @Injected(\.chatClient) var chatClient

    private struct RegisterResponse: Decodable {
        struct RegisteredUser: Decodable {
            let id: String
            let name: String?
            let image: String?
            let role: String?
        }

        let token: String
        let user: RegisteredUser
        let apiToken: String?

        enum CodingKeys: String, CodingKey {
            case token, user
            case apiToken = "api_token"
        }
    }

    /// Сервер объясняет отказ текстом — показываем его как есть, а не общей фразой.
    private struct ServerError: Decodable {
        let message: String
    }

    /// Регистрация на сервере WoodChat с автоматическим входом при успехе.
    func register(onSuccess: @escaping () -> Void) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, !email.isEmpty, !password.isEmpty else {
            errorMessage = "Заполните имя, email и пароль"
            return
        }
        guard password.count >= 8 else {
            errorMessage = "Пароль должен быть не короче 8 символов"
            return
        }

        loading = true
        errorMessage = nil

        Task {
            do {
                let body = ["name": name, "email": email, "password": password]

                var request = URLRequest(url: URL(string: "\(woodChatServerURL)/auth/register")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(body)

                let (data, response) = try await WoodChatNetwork.pinnedSession.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    loading = false
                    errorMessage = "Не удалось связаться с сервером"
                    return
                }

                guard http.statusCode == 201 else {
                    loading = false
                    let parsed = try? JSONDecoder().decode(ServerError.self, from: data)
                    errorMessage = parsed?.message ?? "Не удалось зарегистрироваться"
                    return
                }

                let result = try JSONDecoder().decode(RegisterResponse.self, from: data)
                let credentials = UserCredentials(
                    id: result.user.id,
                    name: result.user.name ?? name,
                    avatarURL: result.user.image.flatMap(URL.init(string:)),
                    token: result.token,
                    birthLand: "",
                    apiToken: result.apiToken,
                    role: result.user.role
                )
                connectUser(withCredentials: credentials, onSuccess: onSuccess)
            } catch {
                loading = false
                errorMessage = "Не удалось подключиться к серверу. Проверьте интернет."
                log.error("Ошибка регистрации: \(error)")
            }
        }
    }

    /// Тот же путь входа, что и после логина: подключаем SDK и сохраняем сессию.
    private func connectUser(withCredentials credentials: UserCredentials, onSuccess: @escaping () -> Void) {
        guard let token = try? Token(rawValue: credentials.token) else {
            loading = false
            errorMessage = "Сервер вернул некорректный токен"
            return
        }

        chatClient.connectUser(
            userInfo: .init(
                id: credentials.id,
                name: credentials.name,
                imageURL: credentials.avatarURL,
                language: AppConfiguration.default.translationLanguage
            ),
            token: token
        ) { [weak self] error in
            if let error {
                log.error("Не удалось подключить пользователя после регистрации: \(error)")
                self?.loading = false
                self?.errorMessage = "Учётная запись создана, но войти не удалось. Попробуйте войти вручную."
                return
            }
            withAnimation {
                self?.loading = false
                SecureUserRepository.shared.save(user: credentials)
                onSuccess()
                AppState.shared.userState = .loggedIn
            }
        }
    }
}

struct RegisterView: View {
    @StateObject private var viewModel = RegisterViewModel()
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Создание учётной записи")
                        .font(.system(size: 24, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)

                    TextField("Имя", text: $viewModel.name)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)

                    TextField("Email", text: $viewModel.email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)

                    SecureField("Пароль (от 8 символов)", text: $viewModel.password)
                        .textContentType(.newPassword)
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
                        viewModel.register {
                            presentationMode.wrappedValue.dismiss()
                        }
                    } label: {
                        Text("Зарегистрироваться")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.loading)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .overlay(viewModel.loading ? ProgressView() : nil)
        }
    }
}
