//
// WoodChat — внутренний мессенджер Woodstream.
// Фоны чатов: каталог встроенных фонов, выбор сохраняется на устройстве.
//

import StreamChatSwiftUI
import SwiftUI

// MARK: - Модель фона

struct WCChatBackground: Identifiable, Equatable {
    let id: String
    let name: String
    /// Цвета градиента (пустой массив — стандартный фон приложения)
    let colors: [Color]

    static let all: [WCChatBackground] = [
        WCChatBackground(id: "default", name: "Стандартный", colors: []),
        WCChatBackground(id: "wood", name: "Дерево", colors: [
            Color(red: 0.96, green: 0.91, blue: 0.84),
            Color(red: 0.87, green: 0.76, blue: 0.62)
        ]),
        WCChatBackground(id: "sunrise", name: "Рассвет", colors: [
            Color(red: 1.00, green: 0.93, blue: 0.85),
            Color(red: 0.99, green: 0.80, blue: 0.72)
        ]),
        WCChatBackground(id: "sky", name: "Небо", colors: [
            Color(red: 0.87, green: 0.94, blue: 1.00),
            Color(red: 0.71, green: 0.85, blue: 0.98)
        ]),
        WCChatBackground(id: "mint", name: "Мята", colors: [
            Color(red: 0.88, green: 0.97, blue: 0.91),
            Color(red: 0.72, green: 0.90, blue: 0.80)
        ]),
        WCChatBackground(id: "lavender", name: "Лаванда", colors: [
            Color(red: 0.93, green: 0.91, blue: 0.99),
            Color(red: 0.82, green: 0.78, blue: 0.95)
        ]),
        WCChatBackground(id: "peach", name: "Персик", colors: [
            Color(red: 1.00, green: 0.92, blue: 0.88),
            Color(red: 0.98, green: 0.78, blue: 0.68)
        ]),
        WCChatBackground(id: "sand", name: "Песок", colors: [
            Color(red: 0.97, green: 0.95, blue: 0.89),
            Color(red: 0.90, green: 0.85, blue: 0.72)
        ]),
        WCChatBackground(id: "ocean", name: "Океан", colors: [
            Color(red: 0.80, green: 0.92, blue: 0.94),
            Color(red: 0.55, green: 0.78, blue: 0.85)
        ]),
        WCChatBackground(id: "rose", name: "Роза", colors: [
            Color(red: 0.99, green: 0.91, blue: 0.94),
            Color(red: 0.95, green: 0.75, blue: 0.83)
        ]),
        WCChatBackground(id: "graphite", name: "Графит", colors: [
            Color(red: 0.24, green: 0.25, blue: 0.27),
            Color(red: 0.13, green: 0.14, blue: 0.16)
        ]),
        WCChatBackground(id: "night", name: "Ночь", colors: [
            Color(red: 0.10, green: 0.13, blue: 0.22),
            Color(red: 0.04, green: 0.05, blue: 0.10)
        ])
    ]

    static func byId(_ id: String) -> WCChatBackground {
        all.first { $0.id == id } ?? all[0]
    }

    @MainActor
    @ViewBuilder
    func fill() -> some View {
        if colors.isEmpty {
            Color(InjectedValues[\.colors].backgroundCoreApp)
        } else {
            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - Хранилище выбора

@MainActor
final class WCBackgroundStore: ObservableObject {
    static let shared = WCBackgroundStore()
    private static let key = "woodchat.chatBackground"

    @Published var selectedId: String {
        didSet { UserDefaults.standard.set(selectedId, forKey: Self.key) }
    }

    private init() {
        selectedId = UserDefaults.standard.string(forKey: Self.key) ?? "default"
    }

    var selected: WCChatBackground { WCChatBackground.byId(selectedId) }
}

// MARK: - Фон в списке сообщений

struct WCChatBackgroundView: View {
    @ObservedObject private var store = WCBackgroundStore.shared

    var body: some View {
        store.selected.fill()
            .ignoresSafeArea()
    }
}

// MARK: - Каталог фонов

struct ChatBackgroundsCatalogView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject private var store = WCBackgroundStore.shared

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(WCChatBackground.all) { background in
                        Button {
                            store.selectedId = background.id
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color(UIColor.secondarySystemBackground))
                                    background.fill()
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                    // Мини-превью пузырей сообщений
                                    VStack(spacing: 6) {
                                        HStack {
                                            Capsule().fill(Color.white.opacity(0.9))
                                                .frame(width: 52, height: 14)
                                            Spacer()
                                        }
                                        HStack {
                                            Spacer()
                                            Capsule().fill(Color.blue.opacity(0.85))
                                                .frame(width: 60, height: 14)
                                        }
                                    }
                                    .padding(12)

                                    if store.selectedId == background.id {
                                        VStack {
                                            HStack {
                                                Spacer()
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(.blue)
                                                    .background(Circle().fill(Color.white))
                                            }
                                            Spacer()
                                        }
                                        .padding(6)
                                    }
                                }
                                .frame(height: 110)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(
                                            store.selectedId == background.id ? Color.blue : Color.gray.opacity(0.25),
                                            lineWidth: store.selectedId == background.id ? 2 : 1
                                        )
                                )

                                Text(background.name)
                                    .font(.footnote)
                                    .foregroundColor(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)

                Text("Фон применяется ко всем чатам на этом устройстве.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .navigationTitle("Фон чатов")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }
}
