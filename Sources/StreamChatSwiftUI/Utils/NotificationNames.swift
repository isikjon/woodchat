//
// WoodChat: события внутри приложения.
//

import Foundation

public extension Notification.Name {
    /// Жалоба на сообщение доставлена на сервер — показываем подтверждение.
    static let woodchatReportSent = Notification.Name("woodchat.reportSent")
}
