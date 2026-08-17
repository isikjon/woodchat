//
// WoodChat — внутренний мессенджер Woodstream.
//

import StreamChat
import StreamChatCommonUI
import StreamChatSwiftUI
import SwiftUI
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    var streamChat: StreamChat?

    var chatClient: ChatClient = {
        var config = ChatClientConfig(apiKey: .init(apiKeyString))
        // WoodChat: приложение работает с собственным сервером вместо облака Stream
        config.baseURL = BaseURL(url: URL(string: woodChatServerURL)!)
        config.isLocalStorageEnabled = true
        // App Group отключён (бесплатный Apple ID не поддерживает).
        // Вернуть при платном аккаунте: config.applicationGroupIdentifier = applicationGroupIdentifier

        let client = ChatClient(config: config)
        return client
    }()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        /*
         //Customizations, uncomment to customize.
         var colors = ColorPalette()
         colors.tintColor = Color(.streamBlue)

         var fonts = Fonts()
         fonts.footnoteBold = Font.footnote

         let images = Images()
         images.reactionLoveBig = UIImage(systemName: "heart.fill")!

         let appearance = Appearance(colors: colors, images: images, fonts: fonts)

         let channelNamer: ChatChannelNamer = { channel, currentUserId in
         "This is our custom name: \(channel.name ?? "no name")"
         }
         let utils = Utils(channelNamer: channelNamer)

         streamChat = StreamChat(chatClient: chatClient, appearance: appearance, utils: utils)

         */

        /*
         let messageTypeResolver = CustomMessageTypeResolver()
         let utils = Utils(messageTypeResolver: messageTypeResolver)

         streamChat = StreamChat(chatClient: chatClient, appearance: appearance, utils: utils)
         */

        LogConfig.level = StreamRuntimeCheck.logLevel ?? .warning
        LogConfig.formatters = [
            PrefixLogFormatter(prefixes: [.info: "ℹ️", .debug: "🛠", .warning: "⚠️", .error: "🚨"])
        ]
        if let subsystems = StreamRuntimeCheck.subsystems {
            LogConfig.subsystems = subsystems
        }
        
        // Единый набор реакций WoodChat: те же эмодзи, что в веб-версии
        var appearance = Appearance()
        appearance.images.availableMessagesReactionEmojis = [
            "like": "👍",
            "love": "❤️",
            "haha": "😂",
            "fire": "🔥",
            "clap": "👏",
            "pray": "🙏",
            "ok": "👌",
            "wow": "😮"
        ]

        // Даты всегда на русском: бандл объявляет только en-локализацию,
        // поэтому системная локаль процесса не переключается на русскую сама
        let ruLocale = Locale(identifier: "ru_RU")
        let messageDateFormatter = DateFormatter.makeDefault()
        messageDateFormatter.locale = ruLocale
        let timestampFormatter = ChannelListMessageTimestampFormatter()
        timestampFormatter.timeFormatter.locale = ruLocale
        timestampFormatter.relativeDateFormatter.locale = ruLocale
        timestampFormatter.weekDayDateFormatter.locale = ruLocale
        timestampFormatter.weekDayDateFormatter.setLocalizedDateFormatFromTemplate("EEEE")
        timestampFormatter.dateFormatter.locale = ruLocale
        let separatorFormatter = DefaultMessageDateSeparatorFormatter()
        separatorFormatter.dateFormatter.locale = ruLocale
        separatorFormatter.dateFormatter.setLocalizedDateFormatFromTemplate("MMMdd")

        let utils = Utils(
            dateFormatter: messageDateFormatter,
            messageTimestampFormatter: timestampFormatter,
            messageDateSeparatorFormatter: separatorFormatter,
            channelListConfig: ChannelListConfig(
                channelItemMutedStyle: .bottomRightCorner
            ),
            messageListConfig: AppConfiguration.makeMessageListConfig(),
            composerConfig: ComposerConfig(isVoiceRecordingEnabled: true)
        )
        streamChat = StreamChat(chatClient: chatClient, appearance: appearance, utils: utils)
        
        let credentials = SecureUserRepository.shared.loadCurrentUser()
        if let credentials, let token = try? Token(rawValue: credentials.token) {
            chatClient.connectUser(
                userInfo: .init(
                    id: credentials.id,
                    name: credentials.name,
                    imageURL: credentials.avatarURL,
                    language: AppConfiguration.default.translationLanguage
                ),
                token: token
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                if AppState.shared.userState == .launchAnimation {
                    AppState.shared.userState = credentials == nil ? .notLoggedIn : .loggedIn
                }
            }
        }

        UNUserNotificationCenter.current().delegate = NotificationsHandler.shared

        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let sceneConfig = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        sceneConfig.delegateClass = SceneDelegate.self
        return sceneConfig
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        guard let currentUserId = chatClient.currentUserId else {
            log.warning("cannot add the device without connecting as user first, did you call connectUser")
            return
        }

        chatClient.currentUserController().addDevice(.apn(token: deviceToken)) { error in
            if let error {
                log.error("adding a device failed with an error \(error)")
                return
            }
            // App Groups отключены (нужны только для расширения уведомлений),
            // поэтому пишем в обычные настройки приложения
            UserDefaults.standard.set(currentUserId, forKey: currentUserIdRegisteredForPush)
        }
    }
}

extension UIColor {
    static let streamBlue = UIColor(red: 0, green: 108.0 / 255.0, blue: 255.0 / 255.0, alpha: 1)
}

extension StreamRuntimeCheck {
    static var logLevel: LogLevel? {
        guard let value = ProcessInfo.processInfo.environment["STREAM_LOG_LEVEL"] else { return nil }
        guard let intValue = Int(value) else { return nil }
        return LogLevel(rawValue: intValue)
    }
    
    static var subsystems: LogSubsystem? {
        guard let value = ProcessInfo.processInfo.environment["STREAM_LOG_SUBSYSTEM"] else { return nil }
        guard let intValue = Int(value) else { return nil }
        return LogSubsystem(rawValue: intValue)
    }
}
