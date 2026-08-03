//
// WoodChat — внутренний мессенджер Woodstream.
//

import Foundation
import StreamChat

enum ChannelListQueryIdentifier: String, CaseIterable, Identifiable {
    case initial
    case archived
    case pinned
    
    var id: String {
        rawValue
    }
    
    var title: String {
        switch self {
        case .initial: "Initial Channels"
        case .archived: "Archived Channels"
        case .pinned: "Pinned Channels"
        }
    }
}
