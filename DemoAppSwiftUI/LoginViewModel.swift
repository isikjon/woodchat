//
// WoodChat — внутренний мессенджер Woodstream.
//

import StreamChat
import StreamChatSwiftUI
import SwiftUI

@MainActor class LoginViewModel: ObservableObject {
    @Published var loading = false
    @Published var email = ""
    @Published var password = ""
    @Published var errorMessage: String?

    @Injected(\.chatClient) var chatClient

    // Клиентская защита от перебора: растущая задержка после неудач
    private var failedAttempts = 0
    private var lockedUntil: Date?

    private struct LoginResponse: Decodable {
        struct LoginUser: Decodable {
            let id: String
            let name: String?
            let image: String?
            let role: String?
        }

        let token: String
        let user: LoginUser
        let apiToken: String?

        enum CodingKeys: String, CodingKey {
            case token, user
            case apiToken = "api_token"
        }
    }

    /// Вход через собственный сервер WoodChat: получаем токен и подключаем SDK.
    func login() {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Введите email и пароль"
            return
        }

        // Клиентская пауза после серии неудачных попыток
        if let lockedUntil, lockedUntil > Date() {
            let seconds = Int(lockedUntil.timeIntervalSinceNow) + 1
            errorMessage = "Слишком много попыток. Подождите \(seconds) с."
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

                let (data, response) = try await WoodChatNetwork.pinnedSession.data(for: request)

                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    loading = false
                    if (response as? HTTPURLResponse)?.statusCode == 403 {
                        // Аккаунт забанен модерацией — это не ошибка пароля
                        errorMessage = "Аккаунт заблокирован за нарушение правил. Напишите на info@woodstream.online."
                        return
                    }
                    registerFailedAttempt()
                    errorMessage = "Неверный email или пароль"
                    return
                }

                failedAttempts = 0
                lockedUntil = nil

                let result = try JSONDecoder().decode(LoginResponse.self, from: data)
                let credentials = UserCredentials(
                    id: result.user.id,
                    name: result.user.name ?? email,
                    avatarURL: result.user.image.flatMap(URL.init(string:)),
                    token: result.token,
                    birthLand: "",
                    apiToken: result.apiToken,
                    role: result.user.role
                )
                connectUser(withCredentials: credentials)
            } catch {
                loading = false
                errorMessage = (error as? URLError)?.code == .timedOut
                    ? "Сервер не отвечает. Проверьте интернет и попробуйте ещё раз."
                    : "Не удалось подключиться к серверу. Проверьте интернет."
                log.error("Ошибка входа: \(error)")
            }
        }
    }

    /// После 5 неудач подряд включаем паузу (30 с), чтобы усложнить перебор.
    private func registerFailedAttempt() {
        failedAttempts += 1
        if failedAttempts >= 5 {
            lockedUntil = Date().addingTimeInterval(30)
            failedAttempts = 0
        }
    }

    /// Сколько ждём установления соединения SDK, прежде чем показать ошибку.
    private static let connectTimeout: TimeInterval = 20
    private var connectTimeoutTask: Task<Void, Never>?

    private func connectUser(withCredentials credentials: UserCredentials) {
        guard let token = try? Token(rawValue: credentials.token) else {
            loading = false
            errorMessage = "Сервер вернул некорректный токен"
            return
        }
        loading = true

        // Страховка от вечной крутилки: если соединение не поднялось за отведённое
        // время, отпускаем кнопку и просим повторить
        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.connectTimeout * 1_000_000_000))
            guard !Task.isCancelled, let self, self.loading else { return }
            self.loading = false
            self.errorMessage = "Сервер не отвечает. Проверьте интернет и попробуйте ещё раз."
            self.chatClient.disconnect {}
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
            guard let self else { return }
            // Таймаут уже сработал и показал ошибку — поздний ответ игнорируем
            guard self.loading else { return }
            self.connectTimeoutTask?.cancel()
            if let error {
                log.error("connecting the user failed \(error)")
                self.loading = false
                self.errorMessage = "Не удалось подключиться к серверу. Попробуйте ещё раз."
                return
            }
            withAnimation {
                self.loading = false
                SecureUserRepository.shared.save(user: credentials)
                AppState.shared.userState = .loggedIn
            }
        }
    }
}
