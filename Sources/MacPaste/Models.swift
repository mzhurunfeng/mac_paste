import AppKit
import Foundation

enum ClipboardItemType: String, CaseIterable, Codable, Identifiable {
    case text
    case link
    case color
    case image

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: "文本"
        case .link: "链接"
        case .color: "颜色"
        case .image: "图片"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "doc.text"
        case .link: "link"
        case .color: "paintpalette"
        case .image: "photo"
        }
    }
}

enum ClipboardFilter: String, CaseIterable, Identifiable {
    case all
    case favorite
    case text
    case image
    case link
    case color

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部类型"
        case .favorite: "收藏"
        case .text: "文本"
        case .image: "图片"
        case .link: "链接"
        case .color: "颜色"
        }
    }

    var itemType: ClipboardItemType? {
        switch self {
        case .all, .favorite: nil
        case .text: .text
        case .image: .image
        case .link: .link
        case .color: .color
        }
    }
}

struct ClipboardItem: Identifiable, Equatable {
    let id: Int64
    let type: ClipboardItemType
    let title: String
    let textContent: String?
    let imagePath: String?
    let createdAt: Date
    let charCount: Int
    let wordCount: Int
    let byteSize: Int
    let width: Int?
    let height: Int?
    let contentHash: String
    let sourceAppName: String?
    let isFavorite: Bool

    var displaySubtitle: String {
        let source = sourceAppName?.isEmpty == false ? sourceAppName! : "-"
        switch type {
        case .image:
            if let width, let height {
                return "\(source) · \(width)x\(height)"
            }
            return "\(source) · 图片"
        default:
            return "\(source) · \(relativeTime)"
        }
    }

    var relativeTime: String {
        RelativeDateTimeFormatter.short.localizedString(for: createdAt, relativeTo: Date())
    }

    var copiedDescription: String {
        if Calendar.current.isDateInToday(createdAt) {
            return "今天 \(DateFormatters.time.string(from: createdAt))"
        }
        if Calendar.current.isDateInYesterday(createdAt) {
            return "昨天 \(DateFormatters.time.string(from: createdAt))"
        }
        return DateFormatters.dateTime.string(from: createdAt)
    }
}

enum TimeSection: String, CaseIterable, Identifiable {
    case today = "今天"
    case yesterday = "昨天"
    case thisMonth = "本月"
    case older = "更早"

    var id: String { rawValue }

    static func section(for date: Date) -> TimeSection {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return .today
        }
        if calendar.isDateInYesterday(date) {
            return .yesterday
        }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .month) {
            return .thisMonth
        }
        return .older
    }
}

enum DateFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()

    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .medium
        return formatter
    }()
}

extension RelativeDateTimeFormatter {
    static let short: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
