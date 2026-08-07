//
// WoodChat — внутренний мессенджер Woodstream.
// Профиль: сведения об аккаунте, заблокированные пользователи, удаление аккаунта.
//

import PhotosUI
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

    /// Загрузка аватара через шлюз чата; ссылка сохраняется в профиле и видна в вебе.
    @MainActor
    static func uploadAvatar(jpegData: Data) async throws -> URL {
        guard let credentials = UnsecureRepository.shared.loadCurrentUser(),
              let url = URL(string: "\(woodChatServerURL)/users/avatar") else {
            throw URLError(.userAuthenticationRequired)
        }

        let boundary = "woodchat-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"avatar.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpegData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        struct AvatarResponse: Decodable { let avatar: String }
        let decoded = try JSONDecoder().decode(AvatarResponse.self, from: data)
        guard let avatarURL = URL(string: decoded.avatar) else { throw URLError(.badServerResponse) }

        // Обновляем сохранённую сессию, чтобы аватар сразу показывался в приложении
        UnsecureRepository.shared.save(user: UserCredentials(
            id: credentials.id,
            name: credentials.name,
            avatarURL: avatarURL,
            token: credentials.token,
            birthLand: credentials.birthLand,
            apiToken: credentials.apiToken,
            role: credentials.role
        ))
        return avatarURL
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
    @State private var avatarURL: URL?
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarUploading = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack(spacing: 16) {
                        avatarPreview
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name.isEmpty ? "—" : name)
                                .font(.headline)
                            PhotosPicker(selection: $avatarItem, matching: .images) {
                                Text(avatarUploading ? "Загрузка…" : "Сменить фото")
                                    .font(.subheadline)
                            }
                            .disabled(avatarUploading)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

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
            .task {
                avatarURL = UnsecureRepository.shared.loadCurrentUser()?.avatarURL
                await load()
            }
            .onChange(of: avatarItem) { newItem in
                guard let newItem else { return }
                uploadAvatar(from: newItem)
            }
        }
    }

    @ViewBuilder
    private var avatarPreview: some View {
        ZStack {
            if let avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    avatarPlaceholder
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.gray.opacity(0.25), lineWidth: 1))
        .overlay(avatarUploading ? ProgressView() : nil)
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle().fill(Color.blue.opacity(0.15))
            Image(systemName: "person.fill")
                .font(.system(size: 28))
                .foregroundColor(.blue)
        }
    }

    private func uploadAvatar(from item: PhotosPickerItem) {
        avatarUploading = true
        errorMessage = nil
        Task {
            defer {
                avatarUploading = false
                avatarItem = nil
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    errorMessage = "Не удалось прочитать фото"
                    return
                }
                // Ужимаем до разумного размера аватара
                let side: CGFloat = 512
                let scale = min(1, side / max(image.size.width, image.size.height))
                let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let renderer = UIGraphicsImageRenderer(size: target)
                let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
                guard let jpeg = resized.jpegData(compressionQuality: 0.85) else {
                    errorMessage = "Не удалось обработать фото"
                    return
                }
                avatarURL = try await WoodChatAPI.uploadAvatar(jpegData: jpeg)
            } catch {
                errorMessage = "Не удалось загрузить фото"
            }
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
