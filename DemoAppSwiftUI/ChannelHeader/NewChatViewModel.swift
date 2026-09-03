//
// WoodChat — внутренний мессенджер Woodstream.
//

import StreamChat
import StreamChatCommonUI
import StreamChatSwiftUI
import SwiftUI

@MainActor class NewChatViewModel: ObservableObject, ChatUserSearchControllerDelegate {
    @Injected(\.chatClient) var chatClient

    @Published var searchText: String = "" {
        didSet {
            searchUsers(with: searchText)
        }
    }

    @Published var messageText: String = ""
    @Published var chatUsers = [ChatUser]()
    @Published var state: NewChatState = .initial
    @Published var selectedUsers = [ChatUser]() {
        didSet {
            if !updatingSelectedUsers {
                updatingSelectedUsers = true
                if !selectedUsers.isEmpty {
                    do {
                        try makeChannelController()
                    } catch {
                        state = .error
                        updatingSelectedUsers = false
                    }

                } else {
                    withAnimation {
                        state = .loaded
                        updatingSelectedUsers = false
                    }
                }
            }
        }
    }

    private var loadingNextUsers: Bool = false
    private var updatingSelectedUsers: Bool = false
    private var searchGeneration = 0

    var channelController: ChatChannelController?

    private lazy var searchController: ChatUserSearchController = chatClient.userSearchController()
    private let lastSeenDateFormatter = DateUtils.timeAgo

    init() {
        searchController.delegate = self
    }

    func userTapped(_ user: ChatUser) {
        if updatingSelectedUsers {
            return
        }

        if selectedUsers.contains(user) {
            selectedUsers.removeAll { selected in
                selected == user
            }
        } else {
            selectedUsers.append(user)
        }
    }

    func onlineInfo(for user: ChatUser) -> String {
        if user.isOnline {
            "В сети"
        } else if let lastActiveAt = user.lastActiveAt,
                  let timeAgo = lastSeenDateFormatter(lastActiveAt) {
            timeAgo
        } else {
            "Не в сети"
        }
    }

    func isSelected(user: ChatUser) -> Bool {
        selectedUsers.contains(user)
    }

    func onChatUserAppear(_ user: ChatUser) {
        guard normalizedSearchTerm.count >= 2 else { return }
        guard let index = chatUsers.firstIndex(where: { element in
            user.id == element.id
        }) else {
            return
        }

        if index < chatUsers.count - 10 {
            return
        }

        if !loadingNextUsers {
            loadingNextUsers = true
            let generation = searchGeneration
            searchController.loadNextUsers { [weak self] _ in
                guard let self = self else { return }
                self.loadingNextUsers = false
                guard generation == self.searchGeneration else { return }
                self.chatUsers = self.searchController.userArray
            }
        }
    }

    // MARK: - ChatUserSearchControllerDelegate

    func controller(
        _ controller: ChatUserSearchController,
        didChangeUsers changes: [ListChange<ChatUser>]
    ) {
        guard controller === searchController else { return }
        guard normalizedSearchTerm.count >= 2 else {
            chatUsers = []
            state = .initial
            return
        }
        chatUsers = controller.userArray
    }

    // MARK: - private

    private func searchUsers(with term: String?) {
        let normalized = term?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        searchGeneration += 1
        let generation = searchGeneration
        searchController.delegate = nil

        guard normalized.count >= 2 else {
            chatUsers = []
            state = .initial
            return
        }

        state = .loading
        // Отдельный контроллер не смешивает результаты быстро сменившихся запросов.
        searchController = chatClient.userSearchController()
        searchController.delegate = self
        searchController.search(term: normalized) { [weak self] error in
            guard let self, generation == self.searchGeneration else { return }
            if error != nil {
                self.state = .error
            } else {
                self.chatUsers = self.searchController.userArray
                self.state = self.chatUsers.isEmpty ? .noUsers : .loaded
            }
        }
    }

    private var normalizedSearchTerm: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeChannelController() throws {
        let selectedUserIds = Set(selectedUsers.map(\.id))
        channelController = try chatClient.channelController(
            createDirectMessageChannelWith: selectedUserIds,
            name: nil,
            imageURL: nil,
            extraData: [:]
        )
        channelController?.synchronize { [weak self] error in
            if error != nil {
                self?.state = .error
                self?.updatingSelectedUsers = false
            } else {
                withAnimation {
                    self?.state = .channel
                    self?.updatingSelectedUsers = false
                }
            }
        }
    }
}

enum NewChatState {
    case initial
    case loading
    case noUsers
    case error
    case loaded
    case channel
}
