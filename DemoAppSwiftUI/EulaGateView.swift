//
// WoodChat — внутренний мессенджер Woodstream.
// Полноэкранное согласие с пользовательским соглашением до входа.
//

import SwiftUI

/// Принял ли пользователь соглашение на этом устройстве.
/// Требование App Review (Guideline 1.2): текст соглашения показывается
/// до входа и регистрации, без согласия дальше не пройти.
enum EulaConsent {
    private static let key = "woodchat.eulaAcceptedVersion"
    /// Меняется при изменении текста — тогда согласие запрашивается заново.
    static let version = 1

    static var isAccepted: Bool {
        UserDefaults.standard.integer(forKey: key) >= version
    }

    static func accept() {
        UserDefaults.standard.set(version, forKey: key)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Экран соглашения: полный текст внутри приложения, галочка и кнопка.
struct EulaGateView: View {
    let onAccepted: () -> Void

    @State private var accepted = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Пользовательское соглашение")
                    .font(.title2.bold())
                Text("Terms of Use (EULA)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Group {
                        eulaHeading("Правила общения в WoodChat")
                        Text("WoodChat — внутренний мессенджер Woodstream. Пользуясь приложением, вы принимаете это соглашение и обязуетесь соблюдать правила общения.")
                        eulaHeading("Нулевая терпимость к недопустимому контенту")
                        Text("Мы придерживаемся политики НУЛЕВОЙ ТЕРПИМОСТИ к оскорбительному контенту и недопустимому поведению. Строго запрещены: травля, оскорбления, разжигание ненависти и дискриминация; материалы сексуального, жестокого или противоправного характера; спам, мошенничество и обман; выдача себя за другого человека; публикация чужих персональных данных.")
                        eulaHeading("Жалобы и блокировка")
                        Text("Любой пользователь может пожаловаться на сообщение (долгое нажатие → «Пожаловаться») и заблокировать другого пользователя (долгое нажатие → «Заблокировать»). Заблокированный скрывается сразу: его сообщения исчезают из чатов, поиска и медиа. Список заблокированных — в профиле.")
                        eulaHeading("Реакция в течение 24 часов")
                        Text("Каждая жалоба разбирается модерацией в течение 24 часов. Нарушающий правила контент удаляется, нарушитель получает ограничение доступа или блокировку аккаунта. При грубых или повторных нарушениях аккаунт блокируется навсегда.")
                    }
                    Divider().padding(.vertical, 4)
                    Group {
                        eulaHeading("Zero tolerance policy")
                        Text("WoodChat is Woodstream's internal messenger with user-generated content. By using the app you accept these terms. We have ZERO TOLERANCE for objectionable content and abusive users: harassment, hate speech, sexual or violent material, spam, scams and impersonation are prohibited.")
                        eulaHeading("Reporting, blocking and moderation")
                        Text("Any user can report a message (long press → «Пожаловаться» / Report) and block another user (long press → «Заблокировать» / Block); blocked users' content is hidden immediately. Every report is reviewed within 24 hours; violating content is removed and the offending user is restricted or permanently banned.")
                    }
                    Button {
                        openURL(Eula.url)
                    } label: {
                        Text("Полный текст соглашения / Full text: woodstream.online/eula")
                            .font(.footnote)
                            .underline()
                    }
                    .accessibilityIdentifier("eulaFullTextLink")
                }
                .font(.subheadline)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            VStack(spacing: 12) {
                Divider()
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        accepted.toggle()
                    } label: {
                        Image(systemName: accepted ? "checkmark.square.fill" : "square")
                            .font(.system(size: 22))
                            .foregroundColor(accepted ? .accentColor : .secondary)
                    }
                    .accessibilityIdentifier("eulaGateCheckbox")
                    .accessibilityLabel("Согласие с условиями использования")
                    Text("Я принимаю условия использования и согласен, что оскорбления, спам и недопустимый контент запрещены. / I accept the terms and the zero tolerance policy.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)

                Button {
                    EulaConsent.accept()
                    onAccepted()
                } label: {
                    Text("Принять и продолжить")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!accepted)
                .accessibilityIdentifier("eulaAcceptButton")
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .background(Color(.systemBackground))
        }
    }

    private func eulaHeading(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.bold())
            .padding(.top, 4)
    }
}
