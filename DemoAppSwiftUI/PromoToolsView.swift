//
// WoodChat — внутренний мессенджер Woodstream.
// Промокоды и подарочные карты: поиск, проверка, погашение, активация.
// Экран для менеджеров, повторяет возможности веб-версии.
//

import SwiftUI

// MARK: - Модели

struct WCPromoCode: Decodable, Identifiable {
    let id: Int
    let code: String
    let type: String
    let value: Double
    let status: String
    let statusLabel: String?
    let usedCount: Int
    let maxUses: Int?
    let minOrderAmount: Double?
    let expiresAt: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id, code, type, value, status, description
        case statusLabel = "status_label"
        case usedCount = "used_count"
        case maxUses = "max_uses"
        case minOrderAmount = "min_order_amount"
        case expiresAt = "expires_at"
    }

    /// «−10%» или «−1 500 ₽»
    var valueLabel: String {
        type == "percent"
            ? "−\(WCMoney.short(value))%"
            : "−\(WCMoney.rubles(value))"
    }

    var usageLabel: String {
        guard let maxUses else { return "Использован \(usedCount) раз" }
        return "Использован \(usedCount) из \(maxUses)"
    }
}

struct WCGiftCard: Decodable, Identifiable {
    let id: Int
    let code: String
    let nominal: Double
    let balance: Double
    let status: String
    let statusLabel: String?
    let isSpendable: Bool
    let expiresAt: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case id, code, nominal, balance, status, note
        case statusLabel = "status_label"
        case isSpendable = "is_spendable"
        case expiresAt = "expires_at"
    }
}

enum WCMoney {
    static func rubles(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value == value.rounded() ? 0 : 2
        formatter.groupingSeparator = " "
        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(number) ₽"
    }

    static func short(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }
}

// MARK: - API

extension WoodChatAPI {
    struct PromoSearchResult: Decodable {
        let promoCodes: [WCPromoCode]
        let giftCards: [WCGiftCard]

        enum CodingKeys: String, CodingKey {
            case promoCodes = "promo_codes"
            case giftCards = "gift_cards"
        }
    }

    static func promoSearch(_ query: String) async throws -> PromoSearchResult {
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let data = try await runRequest(try await buildRequest("promo-tools/search?q=\(escaped)"))
        return try JSONDecoder().decode(PromoSearchResult.self, from: data)
    }

    /// Результат проверки промокода: применим ли и на какую скидку.
    struct PromoCheck: Decodable {
        let ok: Bool
        let reason: String?
        let discount: Double
    }

    /// Проверка промокода на сумму заказа: скидка без списания.
    static func promoCheck(id: Int, orderAmount: Double) async throws -> PromoCheck {
        struct Response: Decodable { let check: PromoCheck }
        var request = try await buildRequest("promo-tools/promo-codes/\(id)/check", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["order_amount": orderAmount])
        return try JSONDecoder().decode(Response.self, from: try await runRequest(request)).check
    }

    /// Погашение промокода — операция транзакционная, повторно не сработает.
    static func promoRedeem(id: Int, orderAmount: Double) async throws -> Double {
        struct Response: Decodable { let discount: Double }
        var request = try await buildRequest("promo-tools/promo-codes/\(id)/redeem", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["order_amount": orderAmount])
        return try JSONDecoder().decode(Response.self, from: try await runRequest(request)).discount
    }

    static func giftCardActivate(id: Int) async throws {
        _ = try await runRequest(try await buildRequest("promo-tools/gift-cards/\(id)/activate", method: "POST"))
    }

    /// Списание с подарочной карты.
    static func giftCardRedeem(id: Int, amount: Double) async throws -> Double {
        struct Response: Decodable { let giftCard: WCGiftCard
            enum CodingKeys: String, CodingKey { case giftCard = "gift_card" } }
        var request = try await buildRequest("promo-tools/gift-cards/\(id)/redeem", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["amount": amount])
        return try JSONDecoder().decode(Response.self, from: try await runRequest(request)).giftCard.balance
    }
}

// MARK: - Экран

@available(iOS 16.0, *)
struct PromoToolsView: View {
    @StateObject private var viewModel = PromoToolsViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchField

                if viewModel.loading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if viewModel.searched && viewModel.promoCodes.isEmpty && viewModel.giftCards.isEmpty {
                    emptyState
                } else {
                    resultsList
                }
            }
            .navigationTitle("Промокоды")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Ошибка", isPresented: $viewModel.showsError) {
                Button("Понятно", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "Не удалось выполнить операцию")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("Код промокода или карты", text: $viewModel.query)
                .autocapitalization(.allCharacters)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await viewModel.search() } }
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "ticket").font(.system(size: 40)).foregroundColor(.secondary)
            Text("Ничего не нашлось")
                .font(.headline)
            Text("Проверьте код: нужно минимум 3 символа")
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var resultsList: some View {
        List {
            if !viewModel.promoCodes.isEmpty {
                Section("Промокоды") {
                    ForEach(viewModel.promoCodes) { code in
                        NavigationLink {
                            PromoCodeDetailView(code: code, viewModel: viewModel)
                        } label: {
                            PromoCodeRow(code: code)
                        }
                    }
                }
            }
            if !viewModel.giftCards.isEmpty {
                Section("Подарочные карты") {
                    ForEach(viewModel.giftCards) { card in
                        NavigationLink {
                            GiftCardDetailView(card: card, viewModel: viewModel)
                        } label: {
                            GiftCardRow(card: card)
                        }
                    }
                }
            }
            if !viewModel.searched {
                Section {
                    Text("Введите код промокода или подарочной карты, чтобы проверить срок, остаток и погасить.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Строки списка

@available(iOS 16.0, *)
private struct PromoCodeRow: View {
    let code: WCPromoCode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(code.code).font(.body.weight(.semibold))
                Spacer()
                Text(code.valueLabel).foregroundColor(.blue)
            }
            HStack(spacing: 6) {
                StatusBadge(text: code.statusLabel ?? code.status, active: code.status == "active")
                Text(code.usageLabel).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

@available(iOS 16.0, *)
private struct GiftCardRow: View {
    let card: WCGiftCard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(card.code).font(.body.weight(.semibold))
                Spacer()
                Text(WCMoney.rubles(card.balance)).foregroundColor(.green)
            }
            HStack(spacing: 6) {
                StatusBadge(text: card.statusLabel ?? card.status, active: card.isSpendable)
                Text("Номинал \(WCMoney.rubles(card.nominal))").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct StatusBadge: View {
    let text: String
    let active: Bool

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((active ? Color.green : Color.gray).opacity(0.15))
            .foregroundColor(active ? .green : .gray)
            .clipShape(Capsule())
    }
}

// MARK: - Промокод: проверка и погашение

@available(iOS 16.0, *)
private struct PromoCodeDetailView: View {
    let code: WCPromoCode
    @ObservedObject var viewModel: PromoToolsViewModel

    @State private var orderAmount = ""
    @State private var discount: Double?
    @State private var redeemed = false
    @State private var showsRedeemConfirm = false

    private var amount: Double? { Double(orderAmount.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        Form {
            Section("Промокод") {
                LabeledContent("Код", value: code.code)
                LabeledContent("Скидка", value: code.valueLabel)
                LabeledContent("Статус", value: code.statusLabel ?? code.status)
                LabeledContent("Использований", value: code.usageLabel)
                if let min = code.minOrderAmount, min > 0 {
                    LabeledContent("Минимальный заказ", value: WCMoney.rubles(min))
                }
                if let expires = code.expiresAt {
                    LabeledContent("Действует до", value: WCDate.human(expires))
                }
                if let description = code.description, !description.isEmpty {
                    Text(description).font(.footnote).foregroundColor(.secondary)
                }
            }

            Section("Сумма заказа") {
                TextField("Например 25000", text: $orderAmount)
                    .keyboardType(.decimalPad)

                Button("Проверить скидку") {
                    Task { discount = await viewModel.check(code: code, amount: amount ?? 0) }
                }
                .disabled(amount == nil || viewModel.working)

                if let discount {
                    LabeledContent("Скидка составит", value: WCMoney.rubles(discount))
                        .foregroundColor(.blue)
                }
            }

            Section {
                Button(redeemed ? "Погашен" : "Погасить промокод") {
                    showsRedeemConfirm = true
                }
                .disabled(amount == nil || redeemed || viewModel.working || code.status != "active")
            } footer: {
                Text("Погашение списывает использование безвозвратно. Проверить скидку можно сколько угодно раз.")
            }
        }
        .navigationTitle(code.code)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(viewModel.working ? ProgressView() : nil)
        .alert("Погасить промокод?", isPresented: $showsRedeemConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Погасить", role: .destructive) {
                Task {
                    if let value = await viewModel.redeem(code: code, amount: amount ?? 0) {
                        discount = value
                        redeemed = true
                    }
                }
            }
        } message: {
            Text("Промокод \(code.code) будет засчитан как использованный.")
        }
    }
}

// MARK: - Подарочная карта: активация и списание

@available(iOS 16.0, *)
private struct GiftCardDetailView: View {
    let card: WCGiftCard
    @ObservedObject var viewModel: PromoToolsViewModel

    @State private var balance: Double?
    @State private var amount = ""
    @State private var activated = false
    @State private var showsRedeemConfirm = false

    private var value: Double? { Double(amount.replacingOccurrences(of: ",", with: ".")) }
    private var currentBalance: Double { balance ?? card.balance }

    var body: some View {
        Form {
            Section("Карта") {
                LabeledContent("Код", value: card.code)
                LabeledContent("Номинал", value: WCMoney.rubles(card.nominal))
                LabeledContent("Остаток", value: WCMoney.rubles(currentBalance))
                LabeledContent("Статус", value: activated ? "Активирована" : (card.statusLabel ?? card.status))
                if let expires = card.expiresAt {
                    LabeledContent("Действует до", value: WCDate.human(expires))
                }
                if let note = card.note, !note.isEmpty {
                    Text(note).font(.footnote).foregroundColor(.secondary)
                }
            }

            if !card.isSpendable && !activated {
                Section {
                    Button("Активировать карту") {
                        Task { activated = await viewModel.activate(card: card) }
                    }
                    .disabled(viewModel.working)
                } footer: {
                    Text("Карту нужно активировать, прежде чем списывать с неё.")
                }
            }

            Section("Списание") {
                TextField("Сумма списания", text: $amount)
                    .keyboardType(.decimalPad)
                Button("Списать") { showsRedeemConfirm = true }
                    .disabled(value == nil || viewModel.working || (!card.isSpendable && !activated) || currentBalance <= 0)
            }
        }
        .navigationTitle(card.code)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(viewModel.working ? ProgressView() : nil)
        .alert("Списать с карты?", isPresented: $showsRedeemConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Списать", role: .destructive) {
                Task {
                    if let newBalance = await viewModel.redeem(card: card, amount: value ?? 0) {
                        balance = newBalance
                        amount = ""
                    }
                }
            }
        } message: {
            Text("С карты \(card.code) спишется \(WCMoney.rubles(value ?? 0)). Операцию нельзя отменить.")
        }
    }
}

enum WCDate {
    /// ISO-строка сервера в человеческий вид
    static func human(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Модель экрана

@available(iOS 16.0, *)
@MainActor
final class PromoToolsViewModel: ObservableObject {
    @Published var query = ""
    @Published var promoCodes: [WCPromoCode] = []
    @Published var giftCards: [WCGiftCard] = []
    @Published var loading = false
    @Published var working = false
    @Published var searched = false
    @Published var errorMessage: String?
    @Published var showsError = false

    func clear() {
        query = ""
        promoCodes = []
        giftCards = []
        searched = false
    }

    func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else {
            fail("Введите минимум 3 символа кода")
            return
        }

        loading = true
        defer { loading = false }
        do {
            let result = try await WoodChatAPI.promoSearch(text)
            promoCodes = result.promoCodes
            giftCards = result.giftCards
            searched = true
        } catch {
            fail("Не удалось найти код. Проверьте связь.")
        }
    }

    /// Возвращает скидку либо показывает причину, по которой код не применим.
    func check(code: WCPromoCode, amount: Double) async -> Double? {
        guard let result = await run({ try await WoodChatAPI.promoCheck(id: code.id, orderAmount: amount) }) else {
            return nil
        }
        if !result.ok {
            fail(result.reason ?? "Промокод не применим к этому заказу")
            return nil
        }
        return result.discount
    }

    func redeem(code: WCPromoCode, amount: Double) async -> Double? {
        await run { try await WoodChatAPI.promoRedeem(id: code.id, orderAmount: amount) }
    }

    func redeem(card: WCGiftCard, amount: Double) async -> Double? {
        await run { try await WoodChatAPI.giftCardRedeem(id: card.id, amount: amount) }
    }

    func activate(card: WCGiftCard) async -> Bool {
        let done: Bool? = await run {
            try await WoodChatAPI.giftCardActivate(id: card.id)
            return true
        }
        return done ?? false
    }

    private func run<T>(_ operation: () async throws -> T) async -> T? {
        working = true
        defer { working = false }
        do {
            return try await operation()
        } catch let WoodChatAPIError.http(_, body) {
            fail(Self.serverMessage(from: body) ?? "Сервер отклонил операцию")
            return nil
        } catch {
            fail("Не удалось выполнить операцию")
            return nil
        }
    }

    /// Сервер присылает причину отказа по-русски — показываем её как есть.
    private static func serverMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? String,
              !message.isEmpty else {
            return nil
        }
        return message
    }

    private func fail(_ message: String) {
        errorMessage = message
        showsError = true
    }
}
