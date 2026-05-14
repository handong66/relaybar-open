import Foundation

enum ProviderSummaryProvider {
    case codex
    case antigravity
}

enum ProviderSummaryState {
    static func subtitle(
        provider: ProviderSummaryProvider,
        accountCount: Int,
        isRefreshing: Bool
    ) -> String? {
        if accountCount == 0 {
            switch provider {
            case .codex:
                return L.menuCodexEmptyDescription
            case .antigravity:
                return L.menuAntigravityEmptyDescription
            }
        }

        if isRefreshing {
            return L.menuRefreshingNow
        }

        return nil
    }
}
