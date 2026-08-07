//
// WoodChat — внутренний мессенджер Woodstream.
//

import StreamChat
import StreamChatSwiftUI
import SwiftUI

public struct CustomChannelHeader: ToolbarContent {
    @Injected(\.fonts) var fonts
    @Injected(\.images) var images
    @Injected(\.colors) var colors

    var title: String
    var currentUserController: CurrentChatUserController
    @Binding var isNewChatShown: Bool
    @Binding var actionsPopupShown: Bool

    @MainActor
    public var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(title)
                .font(fonts.bodyBold)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                isNewChatShown = true
                notifyHideTabBar()
            } label: {
                Image(uiImage: images.messageActionEdit)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundColor(Color(colors.navigationBarGlyph))
                    .padding(.all, 8)
                    .background(Color(colors.navigationBarTintColor))
                    .clipShape(Circle())
            }
            .accessibilityLabel(Text("Новый чат"))
        }
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                actionsPopupShown = true
            } label: {
                if let user = currentUserController.currentUser {
                    UserAvatar(user: user, size: 36)
                        .accessibilityLabel("Профиль и настройки")
                        .accessibilityAddTraits(.isButton)
                } else {
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 36, height: 36)
                        .accessibilityLabel("Профиль и настройки")
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
    }
}

struct CustomChannelModifier: ChannelListHeaderViewModifier {
    @Injected(\.chatClient) var chatClient

    var title: String

    @State var isChooseChannelQueryShown = false
    @State var isNewChatShown = false
    @State var logoutAlertShown = false
    @State var actionsPopupShown = false
    @State var blockedUsersShown = false
    @State var accountShown = false
    @State var backgroundsShown = false

    func body(content: Content) -> some View {
        ZStack {
            if #available(iOS 26, *) {
                content.toolbarThemed {
                    CustomChannelHeader(
                        title: title,
                        currentUserController: chatClient.currentUserController(),
                        isNewChatShown: $isNewChatShown,
                        actionsPopupShown: $actionsPopupShown
                    )
                    #if compiler(>=6.2)
                    .sharedBackgroundVisibility(.hidden)
                    #endif
                }
            } else {
                content.toolbarThemed {
                    CustomChannelHeader(
                        title: title,
                        currentUserController: chatClient.currentUserController(),
                        isNewChatShown: $isNewChatShown,
                        actionsPopupShown: $actionsPopupShown
                    )
                }
            }
            
            NavigationLink(isActive: $blockedUsersShown) {
                BlockedUsersView()
            } label: {
                EmptyView()
            }
            .opacity(0) // Fixes showing accessibility button shape

            NavigationLink(isActive: $isNewChatShown) {
                NewChatView(isNewChatShown: $isNewChatShown)
            } label: {
                EmptyView()
            }
            .isDetailLink(UIDevice.current.userInterfaceIdiom == .pad)
            .opacity(0) // Fixes showing accessibility button shape
            .alert(isPresented: $logoutAlertShown) {
                Alert(
                    title: Text("Выход"),
                    message: Text("Выйти из аккаунта?"),
                    primaryButton: .destructive(Text("Выйти")) {
                        withAnimation {
                            chatClient.logout {
                                UnsecureRepository.shared.removeCurrentUser()
                                DispatchQueue.main.async {
                                    AppState.shared.userState = .notLoggedIn
                                }
                            }
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
            .confirmationDialog("", isPresented: $actionsPopupShown) {
                if #available(iOS 16.0, *) {
                    Button("Профиль и аккаунт") {
                        accountShown = true
                    }
                }
                Button("Заблокированные пользователи") {
                    blockedUsersShown = true
                }

                Button("Фон чатов") {
                    backgroundsShown = true
                }

                Button("Выйти", role: .destructive) {
                    logoutAlertShown = true
                }

                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Выберите действие")
            }
            .confirmationDialog("", isPresented: $isChooseChannelQueryShown) {
                ChooseChannelQueryView()
            } message: {
                Text("Выберите фильтр чатов")
            }
            .sheet(isPresented: $accountShown) {
                if #available(iOS 16.0, *) {
                    AccountView()
                }
            }
            .sheet(isPresented: $backgroundsShown) {
                ChatBackgroundsCatalogView()
            }
        }
    }
}
