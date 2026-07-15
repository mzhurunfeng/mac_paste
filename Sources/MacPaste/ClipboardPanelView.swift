import AppKit
import SwiftUI

struct ClipboardPanelView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var settings: SettingsStore
    let onPaste: (ClipboardItem) -> Void
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            HStack(spacing: 0) {
                historyList
                    .frame(width: 300)

                Divider()

                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 460)
        .background(VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .onChange(of: viewModel.focusSearchRequest) { _ in
            isSearchFocused = true
        }
        .onChange(of: isSearchFocused) { focused in
            viewModel.isSearchFocused = focused
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("搜索粘贴板内容...", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .medium))
                .focused($isSearchFocused)

            Divider()

            HStack(spacing: 8) {
                ForEach(ClipboardFilter.allCases) { filter in
                    Button {
                        viewModel.filter = filter
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(viewModel.filter == filter ? Color.accentColor : Color.primary)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(
                                Capsule()
                                    .fill(viewModel.filter == filter ? Color.accentColor.opacity(0.24) : Color.clear)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.primary.opacity(viewModel.filter == filter ? 0 : 0.16))
                            )
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    Color.clear
                        .frame(height: 1)
                        .id("history-list-top")

                    ForEach(viewModel.sectionedItems, id: \.section.id) { section, items in
                        Text(section.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 10)

                        ForEach(items) { item in
                            HistoryRow(
                                item: item,
                                selected: item.id == viewModel.selectedID,
                                onClick: {
                                    isSearchFocused = false
                                    viewModel.selectedID = item.id
                                },
                                onDoubleClick: { onPaste(item) },
                                onFavoriteToggle: { viewModel.toggleFavorite(id: item.id) }
                            )
                            .equatable()
                            .id(item.id)
                            .padding(.horizontal, 8)
                            .onAppear {
                                viewModel.loadNextPageIfNeeded(currentItem: item)
                            }
                        }
                    }

                    if viewModel.isLoadingPage {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.6)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(.bottom, 8)
            }
            .onChange(of: viewModel.scrollToTopRequest) { _ in
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo("history-list-top", anchor: .top)
                }
            }
            .onChange(of: viewModel.selectedID) { selectedID in
                guard let selectedID else { return }
                proxy.scrollTo(selectedID)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.18))
    }

    @ViewBuilder
    private var detailPane: some View {
        if let item = viewModel.selectedItem {
            VStack(spacing: 0) {
                detailContent(item)
                    .id(item.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(18)

                Divider()

                information(item)
                    .frame(height: 146)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "clipboard")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("暂无粘贴板记录")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func detailContent(_ item: ClipboardItem) -> some View {
        switch item.type {
        case .image:
            if let path = item.imagePath {
                CachedDetailImage(path: path)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("图片不可用")
                    .foregroundStyle(.secondary)
            }
        case .text, .link, .color:
            SelectablePreviewText(text: item.textContent ?? "") {
                isSearchFocused = false
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func information(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("信息")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(role: .destructive) {
                    viewModel.deleteItem(id: item.id)
                } label: {
                    Label("删除", systemImage: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .pointingHandCursor()
            }

            InfoRow(label: "来源", value: item.sourceAppName?.isEmpty == false ? item.sourceAppName! : "-")
            InfoRow(label: "内容类型", value: contentTypeValue(item))
            if item.type == .image {
                InfoRow(label: "尺寸", value: dimensionsValue(item))
                InfoRow(label: "大小", value: ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file))
            } else {
                InfoRow(label: "字符数", value: "\(item.charCount)")
                InfoRow(label: "词数", value: "\(item.wordCount)")
            }
            InfoRow(label: "复制时间", value: item.copiedDescription)
        }
    }

    private func contentTypeValue(_ item: ClipboardItem) -> String {
        switch item.type {
        case .text: "文本"
        case .link: "链接"
        case .color: "颜色"
        case .image: "图片"
        }
    }

    private func dimensionsValue(_ item: ClipboardItem) -> String {
        if let width = item.width, let height = item.height {
            return "\(width)x\(height)"
        }
        return "-"
    }
}

private struct HistoryRow: View, Equatable {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    let item: ClipboardItem
    let selected: Bool
    let onClick: () -> Void
    let onDoubleClick: () -> Void
    let onFavoriteToggle: () -> Void

    static func == (lhs: HistoryRow, rhs: HistoryRow) -> Bool {
        lhs.item == rhs.item && lhs.selected == rhs.selected
    }

    var body: some View {
        HStack(spacing: 7) {
            leadingVisual

            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer()

            Color.clear
                .frame(width: 28, height: 28)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        // 始终保留背景层，避免 LazyVStack 复用 cell 时条件视图残留选中态
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(selectionBackground)
                .opacity(selected ? 1 : 0)
        )
        .overlay {
            HStack(spacing: 0) {
                RowClickHandler(onClick: onClick, onDoubleClick: onDoubleClick)

                Button(action: onFavoriteToggle) {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13))
                        .foregroundStyle(item.isFavorite ? Color.accentColor : Color.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isHovered || item.isFavorite ? 1 : 0)
                .allowsHitTesting(isHovered || item.isFavorite)
                .help(item.isFavorite ? "取消收藏" : "收藏")
            }
        }
        .onHover { isHovered = $0 }
        .pointingHandCursor()
    }

    private var selectionBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.40, blue: 0.68).opacity(0.72)
            : Color(red: 0.70, green: 0.84, blue: 1.00).opacity(0.95)
    }

    @ViewBuilder
    private var leadingVisual: some View {
        if item.type == .image, let imagePath = item.imagePath {
            CachedThumbnailImage(path: imagePath, size: 30)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: item.type.systemImage)
                .font(.system(size: 15))
                .frame(width: 30, height: 30)
        }
    }
}

private struct RowClickHandler: NSViewRepresentable {
    let onClick: () -> Void
    let onDoubleClick: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onClick: onClick, onDoubleClick: onDoubleClick)
    }

    func makeNSView(context: Context) -> ClickView {
        let view = ClickView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: ClickView, context: Context) {
        context.coordinator.onClick = onClick
        context.coordinator.onDoubleClick = onDoubleClick
        view.coordinator = context.coordinator
    }

    final class Coordinator {
        var onClick: () -> Void
        var onDoubleClick: () -> Void

        init(onClick: @escaping () -> Void, onDoubleClick: @escaping () -> Void) {
            self.onClick = onClick
            self.onDoubleClick = onDoubleClick
        }
    }

    final class ClickView: NSView {
        weak var coordinator: Coordinator?

        override func mouseDown(with event: NSEvent) {
            coordinator?.onClick()
            if event.clickCount >= 2 {
                coordinator?.onDoubleClick()
            }
        }
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard hovering != isHovering else { return }
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if isHovering {
                    NSCursor.pop()
                }
            }
    }
}

private extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }
}

private struct CachedThumbnailImage: View {
    let path: String
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.opacity(0.12))
            }
        }
        .onAppear { loadImage() }
        .onChange(of: path) { _ in loadImage() }
    }

    private func loadImage() {
        image = nil
        ImageThumbnailCache.thumbnail(for: path, maxPixelSize: size * 2) { loaded in
            image = loaded
        }
    }
}

private struct CachedDetailImage: View {
    let path: String
    @State private var image: NSImage?
    @State private var loadingPath: String?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { loadImage() }
        .onChange(of: path) { _ in loadImage() }
    }

    private func loadImage() {
        loadingPath = path
        image = nil
        let requestedPath = path
        ImageThumbnailCache.fullImage(for: requestedPath) { loaded in
            guard loadingPath == requestedPath else { return }
            image = loaded
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
        }
        .font(.system(size: 12))
        .padding(.vertical, 1)
    }
}

final class PreviewTextView: NSTextView {
    var onFocus: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onFocus?()
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            onFocus?()
        }
        return became
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "c",
           selectedRange().length > 0 {
            copy(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private struct SelectablePreviewText: NSViewRepresentable {
    let text: String
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFocus: onFocus)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PreviewTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.onFocus = { [weak coordinator = context.coordinator] in
            coordinator?.focusPreview()
        }
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PreviewTextView else { return }
        context.coordinator.onFocus = onFocus
        textView.onFocus = { [weak coordinator = context.coordinator] in
            coordinator?.focusPreview()
        }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator {
        var onFocus: () -> Void

        init(onFocus: @escaping () -> Void) {
            self.onFocus = onFocus
        }

        func focusPreview() {
            onFocus()
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
    }
}
