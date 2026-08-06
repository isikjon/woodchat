//
// WoodChat — внутренний мессенджер Woodstream.
// Профиль: сведения об аккаунте, заблокированные пользователи, удаление аккаунта.
//

import StreamChat
import StreamChatSwiftUI
import SwiftUI

// MARK: - Клиент API аккаунта

extension WoodChatAPI {
    struct AccountInfo: Decodable {
        struct AccountUser: Decodable {
            let id: Int
            let name: String?
            let email: String?
            let role: String?
        }

        let user: AccountUser
    }

    struct BlockedUser: Decodable, Identifiable {
        let id: Int
        let name: String?
    }

    static func account() async throws -> AccountInfo {
        let data = try await runRequest(try await buildRequest("account"))
        return try JSONDecoder().decode(AccountInfo.self, from: data)
    }

    static func blockedUsers() async throws -> [BlockedUser] {
        struct Response: Decodable { let items: [BlockedUser] }
        let data = try await runRequest(try await buildRequest("account/blocked-users"))
        return try JSONDecoder().decode(Response.self, from: data).items
    }

    /// Удаление аккаунта — обязательное требование App Store.
    static func deleteAccount(password: String) async throws {
        var request = try await buildRequest("account", method: "DELETE")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["password": password, "confirm": "1"])
        _ = try await runRequest(request)
    }
}

// MARK: - Экран профиля

@available(iOS 16.0, *)
struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Injected(\.chatClient) private var chatClient

    @State private var name = ""
    @State private var email = ""
    @State private var role = ""
    @State private var blocked: [WoodChatAPI.BlockedUser] = []
    @State private var showsDeleteConfirm = false
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var working = false

    var body: some View {
        NavigationView {
            Form {
                Section("Аккаунт") {
                    LabeledContent("Имя", value: name.isEmpty ? "—" : name)
                    LabeledContent("Email", value: email.isEmpty ? "—" : email)
                    LabeledContent("Роль", value: roleTitle)
                }

                Section("Заблокированные") {
                    if blocked.isEmpty {
                        Text("Список пуст")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(blocked) { user in
                            Text(user.name ?? "Пользователь #\(user.id)")
                        }
                    }
                    Text("Заблокировать или пожаловаться можно долгим нажатием на сообщение в чате.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section {
                    Button("Выйти") { logout() }
                }

                Section {
                    Button("Удалить аккаунт", role: .destructive) {
                        showsDeleteConfirm = true
                    }
                } footer: {
                    Text("Аккаунт будет закрыт, личные данные обезличены, доступ прекращён. Действие необратимо.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .overlay(working ? ProgressView() : nil)
            .alert("Удалить аккаунт?", isPresented: $showsDeleteConfirm) {
                SecureField("Пароль", text: $password)
                Button("Отмена", role: .cancel) { password = "" }
                Button("Удалить", role: .destructive) { deleteAccount() }
            } message: {
                Text("Введите пароль для подтверждения. Восстановить аккаунт будет нельзя.")
            }
            .task { await load() }
        }
    }

    private var roleTitle: String {
        switch role {
        case "admin": return "Администратор"
        case "manager": return "Менеджер"
        default: return "Сотрудник"
        }
    }

    private func load() async {
        do {
            let info = try await WoodChatAPI.account()
            name = info.user.name ?? ""
            email = info.user.email ?? ""
            role = info.user.role ?? "user"
            blocked = (try? await WoodChatAPI.blockedUsers()) ?? []
        } catch {
            errorMessage = "Не удалось загрузить данные аккаунта"
        }
    }

    private func logout() {
        UnsecureRepository.shared.removeCurrentUser()
        chatClient.logout {
            Task { @MainActor in
                AppState.shared.userState = .notLoggedIn
            }
        }
    }

    private func deleteAccount() {
        let enteredPassword = password
        password = ""
        guard !enteredPassword.isEmpty else {
            errorMessage = "Введите пароль"
            return
        }

        working = true
        errorMessage = nil

        Task {
            do {
                try await WoodChatAPI.deleteAccount(password: enteredPassword)
                logout()
            } catch {
                errorMessage = "Не удалось удалить аккаунт. Проверьте пароль."
            }
            working = false
        }
    }
}
