//
// WoodChat — внутренний мессенджер Woodstream.
//

import StreamChat
import StreamChatSwiftUI
import SwiftUI

struct CreateGroupView: View, KeyboardReadable {
    @Injected(\.fonts) var fonts
    @Injected(\.colors) var colors

    @StateObject var viewModel = CreateGroupViewModel()

    @Binding var isNewChatShown: Bool

    @State private var keyboardShown = false

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $viewModel.searchText)
                .padding(.vertical, !viewModel.selectedUsers.isEmpty ? 0 : 16)

            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(viewModel.selectedUsers) { user in
                        SelectedUserGroupView(
                            viewModel: viewModel,
                            user: user
                        )
                    }
                }
                .padding(.all, !viewModel.selectedUsers.isEmpty ? 16 : 0)
            }

            UsersHeaderView(title: "Результаты поиска")
            if viewModel.state == .initial {
                VerticallyCenteredView {
                    Text("Введите не менее 2 символов имени")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color(colors.textLowEmphasis))
                        .padding(.horizontal, 24)
                }
            } else if viewModel.state == .loading {
                VerticallyCenteredView {
                    ProgressView()
                }
            } else if viewModel.state == .loaded {
                List(viewModel.chatUsers) { user in
                    Button {
                        withAnimation {
                            viewModel.userTapped(user)
                        }
                    } label: {
                        ChatUserView(
                            user: user,
                            onlineText: viewModel.onlineInfo(for: user),
                            isSelected: viewModel.isSelected(user: user)
                        )
                    }
                }
                .listStyle(.plain)
            } else if viewModel.state == .noUsers {
                VerticallyCenteredView {
                    Text("Никого не найдено")
                        .font(.title2)
                        .foregroundColor(Color(colors.textLowEmphasis))
                }
            } else if viewModel.state == .error {
                VerticallyCenteredView {
                    Text("Не удалось выполнить поиск")
                        .font(.title2)
                        .foregroundColor(Color(colors.textLowEmphasis))
                }
            }
        }
        .toolbarThemed(content: {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    GroupNameView(
                        viewModel: viewModel,
                        isNewChatShown: $isNewChatShown
                    )
                } label: {
                    Image(systemName: "arrow.forward")
                }
                .isDetailLink(false)
                .disabled(viewModel.selectedUsers.isEmpty)
            }
        })
        .navigationTitle("Участники группы")
        .alert(isPresented: $viewModel.errorShown) {
            Alert.defaultErrorAlert
        }
        .onReceive(keyboardWillChangePublisher) { visible in
            keyboardShown = visible
        }
        .modifier(HideKeyboardOnTapGesture(shouldAdd: keyboardShown))
    }
}

struct SelectedUserGroupView: View {
    @Injected(\.fonts) var fonts

    private let avatarSize: CGFloat = 50

    @StateObject var viewModel: CreateGroupViewModel
    var user: ChatUser

    var body: some View {
        VStack {
            UserAvatar(user: user, size: avatarSize)
            Text(user.name ?? user.id)
                .lineLimit(1)
                .font(fonts.footnote)
        }
        .overlay(
            TopRightView {
                Button(action: {
                    withAnimation {
                        viewModel.userTapped(user)
                    }
                }, label: {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 16, height: 16)

                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color.black.opacity(0.8))
                    }
                    .padding(.all, 4)
                })
            }
            .offset(x: 6, y: -4)
        )
        .frame(width: avatarSize)
    }
}

struct SearchBar: View {
    @Injected(\.colors) var colors

    @Binding var text: String

    @State private var isEditing = false

    var body: some View {
        HStack {
            TextField("Введите имя", text: $text)
                .padding(7)
                .padding(.horizontal, 25)
                .background(Color(colors.background1))
                .cornerRadius(16)
                .overlay(
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 8)

                        if isEditing {
                            Button(action: {
                                text = ""

                            }) {
                                Image(systemName: "multiply.circle.fill")
                                    .foregroundColor(.gray)
                                    .padding(.trailing, 8)
                            }
                        }
                    }
                )
                .padding(.horizontal, 10)
                .onTapGesture {
                    isEditing = true
                }

            if isEditing {
                Button(action: {
                    isEditing = false
                    text = ""

                    // Dismiss the keyboard
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                }) {
                    Text("Отмена")
                }
                .padding(.trailing, 10)
                .transition(.move(edge: .trailing))
                .animation(.default, value: isEditing)
            }
        }
    }
}
