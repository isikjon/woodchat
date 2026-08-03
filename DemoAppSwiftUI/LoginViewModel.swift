//
// WoodChat — внутренний мессенджер Woodstream.
//

import StreamChat
import StreamChatSwiftUI
import SwiftUI

@MainActor class LoginViewModel: ObservableObject {
    @Published var demoUsers = UserCredentials.builtInUsers
    @Published var loading = false
    @Published var showsConfiguration = false
    @Published var email = ""
    @Published var password = ""
    @Published var errorMessage: String?

    @Injected(\.chatClient) var chatClient

    private struct LoginResponse: Decodable {
        struct LoginUser: Decodable {
            let id: String
            let name: String?
            let image: String?
            let role: String?
        }

        let token: String
        let user: LoginUser
    }

    /// Вход через собственный сервер WoodChat: получаем токен и подключаем SDK.
    func login() {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Введите email и пароль"
            return
        }

        loading = true
        errorMessage = nil

        Task {
            do {
                var request = URLRequest(url: URL(string: "\(woodChatServerURL)/auth/login")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(["email": email, "password": password])

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    loading = false
                    errorMessage = "Неверный email или пароль"
                    return
                }

                let result = try JSONDecoder().decode(LoginResponse.self, from: data)
                let credentials = UserCredentials(
                    id: result.user.id,
                    name: result.user.name ?? email,
                    avatarURL: result.user.image.flatMap(URL.init(string:)),
                    token: result.token,
                    birthLand: ""
                )
                connectUser(withCredentials: credentials)
            } catch {
                loading = false
                errorMessage = "Не удалось подключиться к серверу. Проверьте интернет."
                log.error("Ошибка входа: \(error)")
            }
        }
    }

    func demoUserTapped(_ user: UserCredentials) {
        if user.isGuest {
            connectGuestUser(withCredentials: user)
            return
        }

        connectUser(withCredentials: user)
    }

    private func connectUser(withCredentials credentials: UserCredentials) {
        loading = true
        let token = try! Token(rawValue: credentials.token)

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
                log.error("connecting the user failed \(error)")
                return
            }
            withAnimation {
                self?.loading = false
                UnsecureRepository.shared.save(user: credentials)
                AppState.shared.userState = .loggedIn
            }
        }
    }

    private func connectGuestUser(withCredentials credentials: UserCredentials) {
        loading = true

        chatClient.connectGuestUser(
            userInfo: .init(id: credentials.id, name: credentials.name)
        ) { [weak self] error in
            if let error {
                log.error("connecting the user failed \(error)")
                return
            }
            withAnimation {
                self?.loading = false
                AppState.shared.userState = .loggedIn
            }
        }
    }
}
