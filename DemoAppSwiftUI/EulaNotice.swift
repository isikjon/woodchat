//
// WoodChat — внутренний мессенджер Woodstream.
// Согласие с пользовательским соглашением на экранах входа и регистрации.
//

import SwiftUI

/// Пользовательское соглашение с правилами общения и нулевой терпимостью
/// к оскорблениям. Требование App Review (Guideline 1.2): согласие должно
/// быть показано до входа и до создания учётной записи.
enum Eula {
    static let url = URL(string: "https://woodstream.online/eula")!
}

/// Подпись под кнопкой входа: «Нажимая… вы соглашаетесь…» со ссылкой.
struct EulaNotice: View {
    /// Действие, к которому относится согласие: «Войти» или «Зарегистрироваться».
    let actionTitle: String

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 4) {
            Text("Нажимая «\(actionTitle)», вы соглашаетесь с")
                .foregroundColor(.secondary)
            Button {
                openURL(Eula.url)
            } label: {
                Text("Условиями использования (EULA)")
                    .underline()
            }
            .accessibilityIdentifier("eulaLink")
        }
        .font(.footnote)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}

/// Галочка согласия на экране регистрации: без неё кнопка неактивна.
struct EulaAcceptToggle: View {
    @Binding var accepted: Bool

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                accepted.toggle()
            } label: {
                Image(systemName: accepted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundColor(accepted ? .accentColor : .secondary)
            }
            .accessibilityIdentifier("eulaCheckbox")
            .accessibilityLabel("Согласие с условиями использования")

            VStack(alignment: .leading, spacing: 2) {
                Text("Я принимаю условия использования и согласен, что оскорбления, спам и недопустимый контент запрещены.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Button {
                    openURL(Eula.url)
                } label: {
                    Text("Читать соглашение (EULA)")
                        .font(.footnote)
                        .underline()
                }
                .accessibilityIdentifier("eulaLinkRegister")
            }
        }
        .padding(.top, 8)
    }
}
