//
// WoodChat — внутренний мессенджер Woodstream.
// Локальная защита: блокировка по Face ID / Touch ID / коду, шторка при
// сворачивании (скрывает переписку в свитчере), проверка джейлбрейка.
//

import LocalAuthentication
import SwiftUI

// MARK: - Блокировка приложения

@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()

    private static let enabledKey = "woodchat.biometricLock"

    /// Включена ли блокировка (по умолчанию да).
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    /// Заблокирован ли экран прямо сейчас.
    @Published var isLocked: Bool = false

    private var authenticating = false

    private init() {
        if UserDefaults.standard.object(forKey: Self.enabledKey) == nil {
            isEnabled = true
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        }
    }

    /// Доступна ли на устройстве биометрия или код-пароль.
    var canUseAuthentication: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Заблокировать при уходе в фон (вызывается при старте и сворачивании).
    func lockIfNeeded() {
        guard isEnabled, canUseAuthentication else {
            isLocked = false
            return
        }
        isLocked = true
    }

    /// Запросить разблокировку по Face ID / Touch ID / коду.
    func authenticate() {
        guard isLocked, !authenticating else { return }
        guard isEnabled, canUseAuthentication else {
            isLocked = false
            return
        }

        authenticating = true
        let context = LAContext()
        context.localizedReason = "Подтвердите личность для входа в WoodChat"
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Подтвердите личность для входа в WoodChat"
        ) { [weak self] success, _ in
            Task { @MainActor in
                guard let self else { return }
                self.authenticating = false
                if success {
                    self.isLocked = false
                }
            }
        }
    }
}

// MARK: - Экран блокировки

struct AppLockOverlay: View {
    @ObservedObject private var lock = AppLockManager.shared

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                Text("WoodChat заблокирован")
                    .font(.headline)
                Button {
                    lock.authenticate()
                } label: {
                    Text("Разблокировать")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear { lock.authenticate() }
    }
}

// MARK: - Шторка при сворачивании (скрывает содержимое в App Switcher)

struct PrivacyScreenView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.blue)
                Text("WoodChat")
                    .font(.title2.weight(.bold))
            }
        }
    }
}

// MARK: - Проверка джейлбрейка

enum JailbreakCheck {
    /// Базовые признаки взломанного устройства. В симуляторе всегда false.
    static var isJailbroken: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let suspiciousPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/",
            "/private/var/lib/cydia",
            "/usr/bin/ssh"
        ]
        for path in suspiciousPaths where FileManager.default.fileExists(atPath: path) {
            return true
        }

        // Попытка записи за пределы песочницы
        let probe = "/private/woodchat_jb_probe.txt"
        do {
            try "probe".write(toFile: probe, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: probe)
            return true
        } catch {
            // Ожидаемо: писать нельзя
        }

        // Открытие схемы менеджера пакетов
        if let url = URL(string: "cydia://package/com.example"),
           UIApplication.shared.canOpenURL(url) {
            return true
        }

        return false
        #endif
    }
}
