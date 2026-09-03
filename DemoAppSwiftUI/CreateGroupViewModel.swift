//
// WoodChat — внутренний мессенджер Woodstream.
//

import StreamChat
import StreamChatCommonUI
import StreamChatSwiftUI
import SwiftUI

@MainActor class CreateGroupViewModel: ObservableObject, ChatUserSearchControllerDelegate {
    @Injected(\.chatClient) var chatClient

    var channelController: ChatChannelController!

    @Published var searchText = "" {
        didSet {
            searchUsers(with: searchText)
        }
    }

    @Published var state: NewChatState = .initial
    @Published var chatUsers = [ChatUser]()
    @Published var selectedUsers = [ChatUser]()
    @Published var groupName = ""
    @Published var showGroupConversation = false
    @Published var errorShown = false

    private lazy var searchController: ChatUserSearchController = chatClient.userSearchController()
    private let lastSeenDateFormatter = DateUtils.timeAgo
    private var searchGeneration = 0

    init() {
        searchController.delegate = self
    }

    var canCreateGroup: Bool {
        !selectedUsers.isEmpty && !groupName.isEmpty
    }

    func userTapped(_ user: ChatUser) {
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

    func showChannelView() {
        do {
            channelController = try chatClient.channelController(
                createChannelWithId: .init(
                    type: .messaging,
                    id: String(UUID().uuidString.prefix(10))
                ),
                name: groupName,
                members: Set(selectedUsers.map(\.id))
            )
            channelController.synchronize { [weak self] error in
                if error != nil {
                    self?.errorShown = true
                } else {
                    self?.showGroupConversation = true
                }
            }

        } catch {
            errorShown = true
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
}
