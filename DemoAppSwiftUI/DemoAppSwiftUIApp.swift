//
// WoodChat — внутренний мессенджер Woodstream.
//

import Combine
import StreamChat
import StreamChatSwiftUI
import SwiftUI

@main
struct DemoAppSwiftUIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Injected(\.chatClient) public var chatClient: ChatClient
    @State private var appConfig = AppConfiguration.default

    @ObservedObject var appState = AppState.shared
    @ObservedObject var notificationsHandler = NotificationsHandler.shared
    @ObservedObject var appLock = AppLockManager.shared

    @Environment(\.scenePhase) private var scenePhase
    @State private var jailbreakWarningShown = false

    var channelListController: ChatChannelListController? {
        appState.channelListController
    }

    var channelListSearchType: ChannelListSearchType {
        .messages
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                switch appState.userState {
                case .launchAnimation:
                    StreamLogoLaunch()
                case .notLoggedIn:
                    LoginView()
                case .loggedIn:
                    TabView {
                        channelListView()
                            .tabItem { Label("Чаты", systemImage: "message") }
                            .badge(appState.unreadCount.channels)
                        if #available(iOS 16.0, *),
                           SecureUserRepository.shared.loadCurrentUser()?.isManager == true {
                            PublicationsView()
                                .tabItem { Label("Анонсы", systemImage: "megaphone") }
                            PromoToolsView()
                                .tabItem { Label("Промо", systemImage: "ticket") }
                        }
                    }
                    .environment(\.layoutDirection, appConfig.forceRTL ? .rightToLeft : .leftToRight)
                    .id(appState.contentIdentifier)
                }

                // Шторка при сворачивании — прячет переписку в App Switcher
                if scenePhase != .active, appState.userState == .loggedIn {
                    PrivacyScreenView()
                }

                // Блокировка по Face ID / коду поверх всего
                if appLock.isLocked, appState.userState == .loggedIn {
                    AppLockOverlay()
                }
            }
            .alert("Небезопасное устройство", isPresented: $jailbreakWarningShown) {
                Button("Понятно", role: .cancel) {}
            } message: {
                Text("Похоже, устройство взломано (jailbreak). Данные переписки могут быть небезопасны. Рекомендуем использовать приложение на обычном устройстве.")
            }
            .onAppear {
                if JailbreakCheck.isJailbroken {
                    jailbreakWarningShown = true
                }
                // Холодный старт с сохранённой сессией — сразу под замок
                if SecureUserRepository.shared.loadCurrentUser() != nil {
                    appLock.lockIfNeeded()
                }
            }
        }
        .onChange(of: appState.userState) { newValue in
            if newValue == .loggedIn {
                // Запрашиваем разрешение и регистрируем устройство в APNs.
                // Токен уходит на шлюз через addDevice в AppDelegate.
                notificationsHandler.setupRemoteNotifications()
            }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                appLock.lockIfNeeded()
            case .active:
                if appLock.isLocked { appLock.authenticate() }
            default:
                break
            }
        }
    }

    func channelListView() -> ChatChannelListView<DemoAppFactory> {
        if notificationsHandler.notificationChannelId != nil {
            ChatChannelListView(
                viewFactory: DemoAppFactory.shared,
                channelListController: channelListController,
                title: "WoodChat",
                selectedChannelId: notificationsHandler.notificationChannelId,
                searchType: channelListSearchType
            )
        } else {
            ChatChannelListView(
                viewFactory: DemoAppFactory.shared,
                channelListController: channelListController,
                title: "WoodChat",
                searchType: channelListSearchType
            )
        }
    }

    func threadListView() -> ChatThreadListView<DemoAppFactory> {
        ChatThreadListView(viewFactory: DemoAppFactory.shared)
    }
}

@MainActor class AppState: ObservableObject, CurrentChatUserControllerDelegate {
    @Injected(\.chatClient) var chatClient: ChatClient

    // Recreate the content view when channel query changes.
    @Published private(set) var contentIdentifier: String = ""
    
    @Published var userState: UserState = .launchAnimation
    @Published var unreadCount: UnreadCount = .noUnread

    private(set) var channelListController: ChatChannelListController?
    private(set) var currentUserController: CurrentChatUserController?
    private var cancellables = Set<AnyCancellable>()

    static let shared = AppState()

    private init() {
        $userState
            .removeDuplicates()
            .filter { $0 == .notLoggedIn }
            .sink { [weak self] _ in
                self?.didLogout()
            }
            .store(in: &cancellables)
        $userState
            .removeDuplicates()
            .filter { $0 == .loggedIn }
            .sink { [weak self] _ in
                self?.didLogin()
            }
            .store(in: &cancellables)
    }
    
    private func didLogout() {
        channelListController = nil
        currentUserController = nil
    }
    
    private func didLogin() {
        setChannelQueryIdentifier(.initial)
        
        currentUserController = chatClient.currentUserController()
        currentUserController?.delegate = self
        currentUserController?.synchronize()
    }
    
    func setChannelQueryIdentifier(_ identifier: ChannelListQueryIdentifier) {
        let query = AppState.channelListQuery(forIdentifier: identifier, chatClient: chatClient)
        channelListController = chatClient.channelListController(query: query)
        contentIdentifier = identifier.rawValue
    }

    func currentUserController(_ controller: CurrentChatUserController, didChangeCurrentUserUnreadCount: UnreadCount) {
        unreadCount = didChangeCurrentUserUnreadCount
        let totalUnreadBadge = unreadCount.channels + unreadCount.threads
        // Бейдж ставим только если разрешение на уведомления уже выдано —
        // иначе iOS сам показывает системный запрос (push отложены).
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            Task { @MainActor in
                if #available(iOS 16.0, *) {
                    UNUserNotificationCenter.current().setBadgeCount(totalUnreadBadge)
                } else {
                    UIApplication.shared.applicationIconBadgeNumber = totalUnreadBadge
                }
            }
        }
    }
}

enum UserState {
    case launchAnimation
    case notLoggedIn
    case loggedIn
}

extension AppState {
    private static func channelListQuery(
        forIdentifier identifier: ChannelListQueryIdentifier,
        chatClient: ChatClient
    ) -> ChannelListQuery {
        guard let currentUserId = chatClient.currentUserId else { fatalError("Not logged in") }
        switch identifier {
        case .initial:
            var sort: [Sorting<ChannelListSortingKey>] = [Sorting(key: .default)]
            if AppConfiguration.default.isChannelPinningFeatureEnabled {
                sort.insert(Sorting(key: .pinnedAt), at: 0)
            }
            return ChannelListQuery(
                filter: .containMembers(userIds: [currentUserId]),
                sort: sort
            )
        case .archived:
            return ChannelListQuery(
                filter: .and([
                    .containMembers(userIds: [currentUserId]),
                    .equal(.archived, to: true)
                ])
            )
        case .pinned:
            return ChannelListQuery(
                filter: .and([
                    .containMembers(userIds: [currentUserId]),
                    .equal(.pinned, to: true)
                ])
            )
        }
    }
}
