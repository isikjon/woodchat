//
// WoodChat — внутренний мессенджер Woodstream.
//

import UIKit

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func sceneWillResignActive(_ scene: UIScene) {
        if NotificationsHandler.shared.notificationChannelId != nil {
            NotificationsHandler.shared.notificationChannelId = nil
        }
    }
}
