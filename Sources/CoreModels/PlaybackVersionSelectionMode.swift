import Foundation

public enum PlaybackVersionSelectionMode: String, Codable, CaseIterable, Sendable {
    case askEveryTime
    case rememberChoice

    public var title: LocalizedStringResource {
        switch self {
        case .askEveryTime: "Ask every time"
        case .rememberChoice: "Remember my choice"
        }
    }
}
