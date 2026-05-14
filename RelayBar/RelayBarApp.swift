import AppKit
import SwiftUI

@main
struct RelayBarApp: App {
    @StateObject private var store = TokenStore.shared
    @StateObject private var oauth = OAuthManager.shared
    @StateObject private var antigravityStore = AntigravityAccountStore.shared
    @StateObject private var antigravityOAuth = AntigravityOAuthManager.shared
    @StateObject private var credentialTransferWindowModel = CredentialTransferWindowModel.shared

    init() {
        AppIdentityMigration.migrateLegacyLanguageOverride()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(oauth)
                .environmentObject(antigravityStore)
                .environmentObject(antigravityOAuth)
        } label: {
            MenuBarIconView()
        }
        .menuBarExtraStyle(.window)

        Window("RelayBar Credentials", id: CredentialTransferWindowModel.windowID) {
            CredentialTransferWindowView()
                .environmentObject(store)
                .environmentObject(antigravityStore)
                .environmentObject(credentialTransferWindowModel)
        }

        Window(L.antigravityOAuthConfigTitle, id: AntigravityOAuthConfigWindowModel.windowID) {
            AntigravityOAuthConfigWindowView()
        }
        .windowResizability(.contentSize)
    }
}

/// 菜单栏图标：固定应用图标，点击后展开下方面板
struct MenuBarIconView: View {
    var body: some View {
        Group {
            if let icon = menuBarIcon {
                Image(nsImage: icon)
                    .renderingMode(.original)
                    .interpolation(.high)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "terminal.fill")
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .accessibilityLabel(AppIdentity.displayName)
    }

    private var menuBarIcon: NSImage? {
        if let assetIcon = NSImage(named: NSImage.Name("MenuBarIcon")) {
            return assetIcon
        }
        guard let url = Bundle.main.url(forResource: "menuBarIconFallback", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
