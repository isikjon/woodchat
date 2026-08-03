//
// WoodChat — внутренний мессенджер Woodstream.
//

import SwiftUI

@MainActor class LaunchAnimationState: ObservableObject {
    @Published var showAnimation = true

    init() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.showAnimation = false
        }
    }
}
