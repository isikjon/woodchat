//
// WoodChat — внутренний мессенджер Woodstream.
//

import Foundation

// WoodChat: собственный сервер (шлюз Stream-протокола на chat.woodstream.online)
public let apiKeyString = "woodchat"
public let woodChatServerURL = "https://chat.woodstream.online/streamapi"
public let applicationGroupIdentifier = "group.com.isikjandev.woodchat"
public let currentUserIdRegisteredForPush = "currentUserIdRegisteredForPush"

public struct UserCredentials: Codable, Sendable {
    public let id: String
    public let name: String
    public let avatarURL: URL?
    public let token: String
    public let birthLand: String
    /// Токен REST API Laravel (публикации, промокоды); nil у старых сохранённых сессий
    public let apiToken: String?
    /// Роль пользователя: "manager" или "user"
    public let role: String?

    public init(
        id: String,
        name: String,
        avatarURL: URL?,
        token: String,
        birthLand: String,
        apiToken: String? = nil,
        role: String? = nil
    ) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.token = token
        self.birthLand = birthLand
        self.apiToken = apiToken
        self.role = role
    }

    var isManager: Bool {
        role == "manager"
    }

}

extension UserCredentials: Identifiable {
    static func builtInUsersByID(id: String) -> UserCredentials? {
        builtInUsers.filter { $0.id == id }.first
    }

    // Зашитых учётных записей нет: вход только через сервер Woodstream.
    static let builtInUsers: [UserCredentials] = []
}
