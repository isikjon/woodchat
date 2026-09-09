//
// WoodChat: события внутри приложения.
//

import Foundation

public extension Notification.Name {
    /// Жалоба на сообщение доставлена на сервер — показываем подтверждение.
    static let woodchatReportSent = Notification.Name("woodchat.reportSent")

    /// Пользователь заблокирован или разблокирован — список сообщений
    /// перечитывает состав и сразу прячет чужой контент (правило Apple 1.2).
    static let woodchatBlockChanged = Notification.Name("woodchat.blockChanged")
}
