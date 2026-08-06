//
// WoodChat — внутренний мессенджер Woodstream.
// Центр публикаций менеджера: анонсы мегагруппы с отложкой и статусами каналов.
//

import PhotosUI
import SwiftUI

// MARK: - Модели API

struct WCChannelResult: Decodable, Identifiable {
    let channel: String
    let status: String
    let error: String?

    var id: String { channel }

    var channelTitle: String {
        switch channel {
        case "internal": return "Мегагруппа"
        case "whatsapp": return "WhatsApp"
        case "telegram": return "Telegram"
        case "vk": return "ВКонтакте"
        case "site": return "Сайт"
        default: return channel
        }
    }
}

struct WCPublication: Decodable, Identifiable {
    let id: Int
    let body: String?
    let status: String
    let commentsEnabled: Bool?
    let scheduledAt: String?
    let publishedAt: String?
    let views: Int?
    let channelResults: [WCChannelResult]?

    enum CodingKeys: String, CodingKey {
        case id, body, status, views
        case commentsEnabled = "comments_enabled"
        case scheduledAt = "scheduled_at"
        case publishedAt = "published_at"
        case channelResults = "channel_results"
    }

    var statusTitle: String {
        switch status {
        case "draft": return "Черновик"
        case "scheduled": return "Запланирована"
        case "publishing": return "Публикуется"
        case "published": return "Опубликована"
        case "partially_published": return "Частично"
        case "failed": return "Ошибка"
        case "cancelled": return "Отменена"
        default: return status
        }
    }

    var statusColor: Color {
        switch status {
        case "published": return .green
        case "scheduled": return .blue
        case "publishing": return .orange
        case "partially_published": return .orange
        case "failed": return .red
        case "cancelled": return .gray
        default: return .secondary
        }
    }
}

// MARK: - Клиент Laravel API

enum WoodChatAPIError: Error {
    case noToken
    case http(Int, String)
}

enum WoodChatAPI {
    static let base = URL(string: "https://chat.woodstream.online/api/mobile/v1")!

    @MainActor static var token: String? {
        UnsecureRepository.shared.loadCurrentUser()?.apiToken
    }

    static func buildRequest(_ path: String, method: String = "GET") async throws -> URLRequest {
        guard let token = await token else { throw WoodChatAPIError.noToken }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func runRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(code) else {
            throw WoodChatAPIError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    static func publications() async throws -> [WCPublication] {
        struct ListResponse: Decodable { let items: [WCPublication] }
        let data = try await runRequest(try await buildRequest("publications"))
        return try JSONDecoder().decode(ListResponse.self, from: data).items
    }

    static func create(
        text: String,
        images: [Data],
        publishNow: Bool,
        scheduledAt: Date?,
        commentsEnabled: Bool
    ) async throws {
        var request = try await buildRequest("publications", method: "POST")
        let boundary = "woodchat-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }

        field("body", text)
        field("channels[]", "internal")
        field("comments_enabled", commentsEnabled ? "1" : "0")
        if publishNow {
            field("publish_now", "1")
        } else if let scheduledAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            field("scheduled_at", formatter.string(from: scheduledAt))
            field("timezone", TimeZone.current.identifier)
        }

        for (index, image) in images.enumerated() {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append(
                "Content-Disposition: form-data; name=\"attachments[]\"; filename=\"photo\(index).jpg\"\r\n"
                    .data(using: .utf8)!
            )
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(image)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        _ = try await runRequest(request)
    }

    static func publishNow(id: Int) async throws {
        _ = try await runRequest(try await buildRequest("publications/\(id)/publish", method: "POST"))
    }

    static func cancel(id: Int) async throws {
        _ = try await runRequest(try await buildRequest("publications/\(id)/cancel", method: "POST"))
    }

    static func delete(id: Int) async throws {
        _ = try await runRequest(try await buildRequest("publications/\(id)", method: "DELETE"))
    }
}

// MARK: - Экран списка публикаций

@MainActor final class PublicationsViewModel: ObservableObject {
    @Published var publications: [WCPublication] = []
    @Published var loading = false
    @Published var errorMessage: String?

    func reload() async {
        loading = true
        defer { loading = false }
        do {
            publications = try await WoodChatAPI.publications()
            errorMessage = nil
        } catch {
            errorMessage = "Не удалось загрузить публикации"
        }
    }
}

@available(iOS 16.0, *)
struct PublicationsView: View {
    @StateObject private var viewModel = PublicationsViewModel()
    @State private var showsCreate = false

    var body: some View {
        NavigationView {
            Group {
                if viewModel.publications.isEmpty && !viewModel.loading {
                    VStack(spacing: 10) {
                        Image(systemName: "megaphone")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text(viewModel.errorMessage ?? "Публикаций пока нет")
                            .foregroundColor(.secondary)
                        Button("Обновить") { Task { await viewModel.reload() } }
                    }
                } else {
                    List(viewModel.publications) { publication in
                        PublicationRow(publication: publication) {
                            Task { await viewModel.reload() }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await viewModel.reload() }
                }
            }
            .navigationTitle("Анонсы")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showsCreate = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Новая публикация")
                }
            }
            .sheet(isPresented: $showsCreate) {
                CreatePublicationView {
                    Task { await viewModel.reload() }
                }
            }
            .task { await viewModel.reload() }
        }
        .navigationViewStyle(.stack)
    }
}

private struct PublicationRow: View {
    let publication: WCPublication
    let onChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(publication.statusTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(publication.statusColor.opacity(0.15))
                    .foregroundColor(publication.statusColor)
                    .clipShape(Capsule())
                Spacer()
                if let views = publication.views, views > 0 {
                    Label("\(views)", systemImage: "eye")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(publication.body?.isEmpty == false ? publication.body! : "Без текста")
                .lineLimit(3)

            if let results = publication.channelResults, !results.isEmpty {
                HStack(spacing: 6) {
                    ForEach(results) { result in
                        Text(result.channelTitle)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task {
                    try? await WoodChatAPI.delete(id: publication.id)
                    onChanged()
                }
            } label: {
                Label("Удалить", systemImage: "trash")
            }

            if publication.status == "draft" || publication.status == "scheduled" {
                Button {
                    Task {
                        try? await WoodChatAPI.publishNow(id: publication.id)
                        onChanged()
                    }
                } label: {
                    Label("Опубликовать", systemImage: "paperplane")
                }
                .tint(.green)
            }

            if publication.status == "scheduled" {
                Button {
                    Task {
                        try? await WoodChatAPI.cancel(id: publication.id)
                        onChanged()
                    }
                } label: {
                    Label("Отменить", systemImage: "xmark.circle")
                }
                .tint(.orange)
            }
        }
    }
}

// MARK: - Создание публикации

@available(iOS 16.0, *)
struct CreatePublicationView: View {
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var commentsEnabled = true
    @State private var publishNow = true
    @State private var scheduledAt = Date().addingTimeInterval(3600)
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photoData: [Data] = []
    @State private var sending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section("Текст анонса") {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                }

                Section("Фотографии") {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                        Label(
                            photoData.isEmpty ? "Добавить фото" : "Выбрано фото: \(photoData.count)",
                            systemImage: "photo.on.rectangle.angled"
                        )
                    }
                    .onChange(of: photoItems) { items in
                        Task {
                            var loaded: [Data] = []
                            for item in items {
                                if let data = try? await item.loadTransferable(type: Data.self) {
                                    loaded.append(data)
                                }
                            }
                            photoData = loaded
                        }
                    }
                }

                Section("Параметры") {
                    Toggle("Комментарии разрешены", isOn: $commentsEnabled)
                    Toggle("Опубликовать сразу", isOn: $publishNow)
                    if !publishNow {
                        DatePicker("Дата и время", selection: $scheduledAt, in: Date()...)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }
            .navigationTitle("Новая публикация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(publishNow ? "Опубликовать" : "Запланировать") {
                        submit()
                    }
                    .disabled(sending || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photoData.isEmpty))
                }
            }
            .overlay(sending ? ProgressView() : nil)
        }
    }

    private func submit() {
        sending = true
        errorMessage = nil
        Task {
            do {
                try await WoodChatAPI.create(
                    text: text,
                    images: photoData,
                    publishNow: publishNow,
                    scheduledAt: publishNow ? nil : scheduledAt,
                    commentsEnabled: commentsEnabled
                )
                onCreated()
                dismiss()
            } catch {
                errorMessage = "Не удалось создать публикацию"
            }
            sending = false
        }
    }
}
