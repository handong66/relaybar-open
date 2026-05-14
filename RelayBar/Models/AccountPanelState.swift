import CoreGraphics
import Foundation

struct AccountPanelState {
    let activeAccount: TokenAccount?
    let secondaryAccounts: [TokenAccount]
    let visibleSecondaryAccounts: [TokenAccount]
    let hiddenSecondaryCount: Int
    let availableCount: Int
    let listMaxHeight: CGFloat
    let latestUpdate: Date?

    init(
        accounts: [TokenAccount],
        maxVisibleSecondaryAccounts: Int,
        estimatedHeroHeight: CGFloat,
        estimatedSecondaryHeight: CGFloat,
        listVerticalPadding: CGFloat
    ) {
        self.availableCount = accounts.filter { $0.usageStatus == .ok }.count
        self.latestUpdate = accounts.compactMap(\.lastChecked).max()
        let orderedAccounts = Self.sorted(accounts)
        self.activeAccount = orderedAccounts.first
        let secondaryAccounts = Array(orderedAccounts.dropFirst())
        self.secondaryAccounts = secondaryAccounts
        self.visibleSecondaryAccounts = Array(secondaryAccounts.prefix(maxVisibleSecondaryAccounts))
        self.hiddenSecondaryCount = max(secondaryAccounts.count - visibleSecondaryAccounts.count, 0)

        guard !orderedAccounts.isEmpty else {
            self.listMaxHeight = 0
            return
        }

        let visibleHeight = estimatedHeroHeight + CGFloat(visibleSecondaryAccounts.count) * estimatedSecondaryHeight
        if hiddenSecondaryCount > 0 {
            self.listMaxHeight = visibleHeight + 40 + listVerticalPadding
        } else {
            self.listMaxHeight = visibleHeight + listVerticalPadding
        }
    }

    private static func statusRank(_ account: TokenAccount) -> Int {
        switch account.usageStatus {
        case .ok:
            return 0
        case .warning:
            return 1
        case .exceeded:
            return 2
        case .banned:
            return 3
        }
    }

    private static func sorted(_ accounts: [TokenAccount]) -> [TokenAccount] {
        accounts.sorted { lhs, rhs in
            let left = sortKey(for: lhs)
            let right = sortKey(for: rhs)
            if left.0 != right.0 { return left.0 < right.0 }
            if left.1 != right.1 { return left.1 < right.1 }
            if left.2 != right.2 { return left.2 > right.2 }
            if lhs.email != rhs.email { return lhs.email < rhs.email }
            return lhs.storageKey < rhs.storageKey
        }
    }

    private static func sortKey(for account: TokenAccount) -> (Int, Int, TimeInterval) {
        (
            account.isActive ? 0 : 1,
            statusRank(account),
            account.lastChecked?.timeIntervalSince1970 ?? .zero
        )
    }
}
