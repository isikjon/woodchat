//
// Copyright © 2026 Stream.io Inc. All rights reserved.
//

import StreamChat
import SwiftUI

/// The orientation of media attachments in a gallery, determined by the
/// first attachment's original dimensions.
public enum MediaGalleryOrientation: Sendable {
    case landscape
    case portrait
    case square

    /// Initializes the orientation from the given pixel dimensions.
    ///
    /// Uses a tolerance of 5% around a 1:1 ratio to classify near-square
    /// images as ``square``. Falls back to ``landscape`` when dimensions
    /// are unavailable.
    public init(width: Double?, height: Double?) {
        guard let width, let height, width > 0, height > 0 else {
            self = .landscape
            return
        }
        let ratio = width / height
        if ratio > 1.05 {
            self = .landscape
        } else if ratio < 0.95 {
            self = .portrait
        } else {
            self = .square
        }
    }
}

/// A container view that displays media (image and video) attachments in a
/// gallery grid layout.
///
/// The layout adapts based on the orientation (landscape, portrait, square)
/// of the first image attachment and the total number of media items:
/// - **1 item**: Full-bleed single image whose container aspect ratio
///   matches the detected orientation.
/// - **2 items**: Two items side by side in a landscape-aspect container.
/// - **3 items**: One item on the left (full height) with two stacked
///   on the right.
/// - **4+ items**: A 2×2 grid. When there are more than four items the
///   last visible cell shows a "+N" overlay with the remaining count.
///
/// This view does **not** render message text or a bubble background.
/// Tapping any cell opens the full-screen gallery.
public struct MessageMediaAttachmentsContainerView<Factory: ViewFactory>: View {
    @Injected(\.colors) private var colors
    @Injected(\.fonts) private var fonts
    @Injected(\.tokens) private var tokens

    let factory: Factory
    let message: ChatMessage
    let width: CGFloat

    @State private var galleryShown = false
    @State private var selectedIndex = 0
    private var spacing: CGFloat { tokens.spacingXxxs }
    private var cornerRadius: CGFloat { tokens.messageBubbleRadiusAttachment }
    private let maxDisplayedItems = 10

    public init(
        factory: Factory,
        message: ChatMessage,
        width: CGFloat
    ) {
        self.factory = factory
        self.message = message
        self.width = width
    }

    public var body: some View {
        galleryGrid
            .fullScreenCover(isPresented: $galleryShown, onDismiss: {
                selectedIndex = 0
            }) {
                factory.makeMediaViewer(
                    options: MediaViewerOptions(
                        mediaAttachments: sources,
                        message: message,
                        isShown: $galleryShown,
                        options: .init(selectedIndex: selectedIndex)
                    )
                )
            }
            .accessibilityIdentifier("MessageMediaAttachmentsContainerView")
    }

    // MARK: - Layout

    @ViewBuilder
    private var galleryGrid: some View {
        let items = sources
        let size = containerSize(for: items.count)

        Group {
            switch items.count {
            case 0:
                EmptyView()
            case 1:
                singleItemLayout(items[0], width: size.width, height: size.height)
            case 2:
                twoItemLayout(items, size: size)
            case 3:
                threeItemLayout(items, size: size)
            default:
                mosaicLayout(Array(items.prefix(maxDisplayedItems)))
            }
        }
        .frame(width: size.width, height: items.count > 3 ? nil : size.height)
    }

    /**
     Мозаика как в Telegram: снимки раскладываются по рядам, в каждом ряду
     высота общая, а ширина пропорциональна кадру. Так альбом показывается
     целиком и ничего не режется в квадрат.
     */
    @ViewBuilder
    private func mosaicLayout(_ items: [MediaAttachment]) -> some View {
        let rows = MediaMosaicPlanner.rows(for: items, containerWidth: width, spacing: spacing)
        VStack(spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: spacing) {
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { cellIndex, cell in
                        let isLast = rowIndex == rows.count - 1 && cellIndex == row.cells.count - 1
                        if isLast && remainingCount > 0 {
                            overflowCell(cell.item, width: cell.width, height: row.height, index: cell.index)
                        } else {
                            mediaCell(cell.item, width: cell.width, height: row.height, index: cell.index)
                        }
                    }
                }
            }
        }
        .frame(width: width)
    }

    private func singleItemLayout(
        _ item: MediaAttachment,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        mediaCell(item, width: width, height: height, index: 0)
    }

    @ViewBuilder
    private func twoItemLayout(
        _ items: [MediaAttachment],
        size: CGSize
    ) -> some View {
        if orientation == .landscape {
            // Landscape: stacked vertically
            let cellHeight = (size.height - spacing) / 2
            VStack(spacing: spacing) {
                mediaCell(items[0], width: size.width, height: cellHeight, index: 0)
                mediaCell(items[1], width: size.width, height: cellHeight, index: 1)
            }
        } else {
            // Portrait / Square: side by side
            let cellWidth = (size.width - spacing) / 2
            HStack(spacing: spacing) {
                mediaCell(items[0], width: cellWidth, height: size.height, index: 0)
                mediaCell(items[1], width: cellWidth, height: size.height, index: 1)
            }
        }
    }

    @ViewBuilder
    private func threeItemLayout(
        _ items: [MediaAttachment],
        size: CGSize
    ) -> some View {
        if orientation == .landscape {
            // Landscape: top item full width, bottom two side by side
            let cellWidth = (size.width - spacing) / 2
            let cellHeight = (size.height - spacing) / 2
            VStack(spacing: spacing) {
                mediaCell(items[0], width: size.width, height: cellHeight, index: 0)
                HStack(spacing: spacing) {
                    mediaCell(items[1], width: cellWidth, height: cellHeight, index: 1)
                    mediaCell(items[2], width: cellWidth, height: cellHeight, index: 2)
                }
            }
        } else {
            // Portrait / Square: left item full height, right two stacked
            let cellWidth = (size.width - spacing) / 2
            let cellHeight = (size.height - spacing) / 2
            HStack(spacing: spacing) {
                mediaCell(items[0], width: cellWidth, height: size.height, index: 0)
                VStack(spacing: spacing) {
                    mediaCell(items[1], width: cellWidth, height: cellHeight, index: 1)
                    mediaCell(items[2], width: cellWidth, height: cellHeight, index: 2)
                }
            }
        }
    }

    @ViewBuilder
    private func fourPlusItemLayout(
        _ items: [MediaAttachment],
        size: CGSize
    ) -> some View {
        let cellWidth = (size.width - spacing) / 2
        let cellHeight = (size.height - spacing) / 2
        if orientation == .landscape {
            // Landscape: two rows (VStack of HStacks)
            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    mediaCell(items[0], width: cellWidth, height: cellHeight, index: 0)
                    mediaCell(items[1], width: cellWidth, height: cellHeight, index: 1)
                }
                HStack(spacing: spacing) {
                    mediaCell(items[2], width: cellWidth, height: cellHeight, index: 2)
                    overflowCell(items[3], width: cellWidth, height: cellHeight, index: 3)
                }
            }
        } else {
            // Portrait / Square: two columns (HStack of VStacks)
            HStack(spacing: spacing) {
                VStack(spacing: spacing) {
                    mediaCell(items[0], width: cellWidth, height: cellHeight, index: 0)
                    mediaCell(items[2], width: cellWidth, height: cellHeight, index: 2)
                }
                VStack(spacing: spacing) {
                    mediaCell(items[1], width: cellWidth, height: cellHeight, index: 1)
                    overflowCell(items[3], width: cellWidth, height: cellHeight, index: 3)
                }
            }
        }
    }

    private func overflowCell(
        _ item: MediaAttachment,
        width: CGFloat,
        height: CGFloat,
        index: Int
    ) -> some View {
        ZStack {
            mediaCell(item, width: width, height: height, index: index)
            if remainingCount > 0 {
                Color.black.opacity(0.4)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                Text("+\(remainingCount)")
                    .foregroundColor(Color(colors.staticColorText))
                    .font(fonts.title)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: - Cell

    private func mediaCell(
        _ item: MediaAttachment,
        width: CGFloat,
        height: CGFloat,
        index: Int
    ) -> some View {
        MessageMediaAttachmentContentView(
            factory: factory,
            source: item,
            width: width,
            height: height,
            cornerRadius: cornerRadius,
            isOutgoing: message.isSentByCurrentUser
        )
        .withUploadingStateIndicator(for: item.uploadingState, url: item.url)
        .contentShape(Rectangle())
        .onTapGesture {
            if message.localState == nil {
                selectedIndex = index
                galleryShown = true
            }
        }
        .accessibilityLabel(L10n.Message.Attachment.accessibilityLabel(index + 1))
        .accessibilityAddTraits(item.type == .video ? .startsMediaSession : .isImage)
    }

    // MARK: - Data

    private var orientation: MediaGalleryOrientation {
        if let first = sources.first {
            return MediaGalleryOrientation(
                width: first.originalWidth,
                height: first.originalHeight
            )
        }
        return .landscape
    }

    private var sources: [MediaAttachment] {
        MediaAttachment.galleryOrdered(from: message)
    }

    private func containerSize(for itemCount: Int) -> CGSize {
        guard itemCount > 0 else { return .zero }
        let maxItemWidth = width
        if itemCount == 1 {
            switch orientation {
            case .landscape:
                // Width-constrained: 256×192 at max width
                return CGSize(width: maxItemWidth, height: maxItemWidth * 3.0 / 4.0)
            case .portrait:
                // Height-constrained: 192×256 at max width
                return CGSize(width: maxItemWidth * 3.0 / 4.0, height: maxItemWidth)
            case .square:
                return CGSize(width: maxItemWidth, height: maxItemWidth)
            }
        } else {
            // Multi-item always uses landscape ratio
            return CGSize(width: maxItemWidth, height: maxItemWidth * 3.0 / 4.0)
        }
    }

    private var remainingCount: Int {
        max(sources.count - maxDisplayedItems, 0)
    }
}

// MARK: - Планировщик мозаики

/// Раскладка альбома по рядам: в ряду кадры одной высоты, ширина — по пропорциям.
/// Логика близка к Telegram: 2–3 кадра в ряду, панорамы и очень вытянутые
/// снимки занимают ряд целиком.
enum MediaMosaicPlanner {
    struct Cell {
        let item: MediaAttachment
        let index: Int
        let width: CGFloat
    }

    struct Row {
        let cells: [Cell]
        let height: CGFloat
    }

    /// Пропорции кадра; если сервер их не прислал, считаем снимок квадратным.
    private static func ratio(_ item: MediaAttachment) -> CGFloat {
        guard let width = item.originalWidth, let height = item.originalHeight,
              width > 0, height > 0 else {
            return 1
        }
        // Слишком вытянутые кадры ограничиваем, иначе ряд становится нитью
        return min(max(CGFloat(width / height), 0.5), 2.5)
    }

    static func rows(for items: [MediaAttachment], containerWidth: CGFloat, spacing: CGFloat) -> [Row] {
        guard !items.isEmpty, containerWidth > 0 else { return [] }

        let ratios = items.map(ratio)
        let groups = groupIndices(ratios: ratios)

        return groups.map { group in
            let groupRatios = group.map { ratios[$0] }
            let sum = groupRatios.reduce(0, +)
            let available = containerWidth - spacing * CGFloat(group.count - 1)
            // Общая высота ряда: при ней суммарная ширина кадров равна доступной
            let height = (available / max(sum, 0.01)).rounded()
            let cells = group.map { index in
                Cell(item: items[index], index: index, width: (ratios[index] * height).rounded())
            }
            return Row(cells: cells, height: height)
        }
    }

    /// Разбивка на ряды: широкие кадры ставим по два, узкие — по три.
    private static func groupIndices(ratios: [CGFloat]) -> [[Int]] {
        var groups: [[Int]] = []
        var current: [Int] = []

        func flush() {
            if !current.isEmpty {
                groups.append(current)
                current = []
            }
        }

        for index in ratios.indices {
            current.append(index)
            let widthSum = current.map { ratios[$0] }.reduce(0, +)
            // Ряд закрываем, когда кадры вместе стали достаточно широкими
            let enough = current.count >= 3 || widthSum >= 2.2
            if enough {
                flush()
            }
        }
        flush()

        // Одинокий кадр в последнем ряду приклеиваем к предыдущему, если там место
        if groups.count > 1, let last = groups.last, last.count == 1, groups[groups.count - 2].count < 3 {
            let lonely = groups.removeLast()
            groups[groups.count - 1].append(contentsOf: lonely)
        }

        return groups
    }
}
