import Combine
import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published private(set) var sectionedItems: [(section: TimeSection, items: [ClipboardItem])] = []
    @Published var selectedID: ClipboardItem.ID?
    @Published var searchQuery = "" {
        didSet { scheduleSearchReload() }
    }
    @Published var filter: ClipboardFilter = .all {
        didSet { reload(resetPaging: true) }
    }
    @Published private(set) var isLoadingPage = false
    @Published private(set) var hasMoreItems = true
    @Published private(set) var scrollToTopRequest = 0
    @Published private(set) var focusSearchRequest = 0
    @Published var isSearchFocused = false

    private let store: ClipboardStore
    private let pageSize = 50
    private var currentOffset = 0
    private var searchTask: Task<Void, Never>?
    private var pageLoadToken = UUID()

    init(store: ClipboardStore) {
        self.store = store
        reload(resetPaging: true)
    }

    var selectedItem: ClipboardItem? {
        if let selectedID, let item = items.first(where: { $0.id == selectedID }) {
            return item
        }
        return items.first
    }

    func reload(resetPaging: Bool = false) {
        do {
            let requestedLimit: Int
            if resetPaging {
                currentOffset = 0
                hasMoreItems = true
                pageLoadToken = UUID()
                requestedLimit = pageSize
            } else {
                requestedLimit = max(currentOffset, pageSize)
            }

            let fetchedItems = try store.fetchItems(
                searchQuery: searchQuery,
                filter: filter,
                limit: requestedLimit,
                offset: 0
            )
            items = fetchedItems
            currentOffset = fetchedItems.count
            hasMoreItems = fetchedItems.count == requestedLimit
            updateSectionedItems()

            if selectedID == nil || !items.contains(where: { $0.id == selectedID }) {
                selectedID = items.first?.id
            }
        } catch {
            NSLog("MacPaste history reload failed: \(error.localizedDescription)")
        }
    }

    func reloadAfterClipboardCapture() {
        reload(resetPaging: true)
        selectFirst()
        scrollToTopRequest += 1
    }

    func prepareForOpen() {
        searchTask?.cancel()
        if !searchQuery.isEmpty {
            searchQuery = ""
        }
        reload(resetPaging: true)
        selectFirst()
        scrollToTopRequest += 1
        focusSearchRequest += 1
    }

    func requestSearchFocus() {
        focusSearchRequest += 1
    }

    func bumpItemToTop(id: Int64) {
        do {
            try store.touchItem(id: id)
        } catch {
            NSLog("MacPaste bump item failed: \(error.localizedDescription)")
        }
    }

    func deleteItem(id: ClipboardItem.ID) {
        guard let deletedIndex = items.firstIndex(where: { $0.id == id }) else { return }
        do {
            try store.deleteItem(id: id)
            items.remove(at: deletedIndex)
            currentOffset = max(0, currentOffset - 1)
            updateSectionedItems()

            if items.isEmpty {
                selectedID = nil
                hasMoreItems = false
            } else {
                let nextIndex = min(deletedIndex, items.count - 1)
                selectedID = items[nextIndex].id
            }
        } catch {
            NSLog("MacPaste delete item failed: \(error.localizedDescription)")
        }
    }

    func loadNextPageIfNeeded(currentItem item: ClipboardItem) {
        guard hasMoreItems, !isLoadingPage else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard index >= items.count - 10 else { return }

        isLoadingPage = true
        let token = pageLoadToken
        let offset = currentOffset
        let query = searchQuery
        let activeFilter = filter

        store.fetchItemsAsync(searchQuery: query, filter: activeFilter, limit: pageSize, offset: offset) { [weak self] result in
            guard let self, self.pageLoadToken == token else { return }
            self.isLoadingPage = false

            do {
                let nextItems = try result.get()
                self.items.append(contentsOf: nextItems)
                self.currentOffset += nextItems.count
                self.hasMoreItems = nextItems.count == self.pageSize
                self.updateSectionedItems()
            } catch {
                NSLog("MacPaste history pagination failed: \(error.localizedDescription)")
            }
        }
    }

    func selectFirst() {
        selectedID = items.first?.id
    }

    func selectNext() {
        guard !items.isEmpty else { return }
        let currentIndex = items.firstIndex(where: { $0.id == selectedID }) ?? -1
        let nextIndex = min(currentIndex + 1, items.count - 1)
        selectedID = items[nextIndex].id
    }

    func selectPrevious() {
        guard !items.isEmpty else { return }
        let currentIndex = items.firstIndex(where: { $0.id == selectedID }) ?? 0
        let previousIndex = max(currentIndex - 1, 0)
        selectedID = items[previousIndex].id
    }

    private func scheduleSearchReload() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            reload(resetPaging: true)
        }
    }

    private func updateSectionedItems() {
        var grouped: [TimeSection: [ClipboardItem]] = [:]
        for item in items {
            let section = TimeSection.section(for: item.createdAt)
            grouped[section, default: []].append(item)
        }

        sectionedItems = TimeSection.allCases.compactMap { section in
            guard let sectionItems = grouped[section], !sectionItems.isEmpty else { return nil }
            return (section, sectionItems)
        }
    }
}
