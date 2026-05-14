import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum CredentialTransferPanelMode {
    case export
    case importPreview

    var title: String {
        switch self {
        case .export:
            return L.credentialsSelectAccountsTitle
        case .importPreview:
            return L.credentialsImportPreviewTitle
        }
    }

    var description: String {
        switch self {
        case .export:
            return L.credentialsExportDescription
        case .importPreview:
            return L.credentialsImportDescription
        }
    }

    var confirmTitle: String {
        switch self {
        case .export:
            return L.credentialsExportConfirm
        case .importPreview:
            return L.credentialsImportConfirm
        }
    }
}

struct CredentialTransferPanelResult {
    let selectedItemIDs: Set<String>
    let conflictActions: [String: CredentialImportConflictAction]
}

struct CredentialTransferFlow {
    let mode: CredentialTransferPanelMode
    let items: [CredentialTransferSelectableItem]
    let state: CredentialTransferPanelState
}

@MainActor
final class CredentialTransferPanelState: ObservableObject {
    let mode: CredentialTransferPanelMode
    let items: [CredentialTransferSelectableItem]

    @Published var selectedItemIDs: Set<String>
    @Published var conflictActions: [String: CredentialImportConflictAction]

    init(
        mode: CredentialTransferPanelMode,
        items: [CredentialTransferSelectableItem]
    ) {
        self.mode = mode
        self.items = items
        self.selectedItemIDs = Set(items.map(\.id))
        self.conflictActions = Dictionary(
            uniqueKeysWithValues: items
                .filter(\.hasConflict)
                .map { ($0.id, .overwrite) }
        )
    }

    var providerSections: [(CredentialTransferProvider, [CredentialTransferSelectableItem])] {
        CredentialTransferProvider.allCases.compactMap { provider in
            let providerItems = items.filter { $0.provider == provider }
            guard !providerItems.isEmpty else { return nil }
            return (provider, providerItems)
        }
    }

    var selectedCount: Int {
        selectedItemIDs.count
    }

    var totalCount: Int {
        items.count
    }

    var hasConflicts: Bool {
        items.contains(where: \.hasConflict)
    }

    var canConfirm: Bool {
        !selectedItemIDs.isEmpty
    }

    func isSelected(_ item: CredentialTransferSelectableItem) -> Bool {
        selectedItemIDs.contains(item.id)
    }

    func selectedCount(for provider: CredentialTransferProvider) -> Int {
        items
            .filter { $0.provider == provider && selectedItemIDs.contains($0.id) }
            .count
    }

    func setSelected(_ isSelected: Bool, for item: CredentialTransferSelectableItem) {
        var next = selectedItemIDs
        if isSelected {
            next.insert(item.id)
        } else {
            next.remove(item.id)
        }
        selectedItemIDs = next
    }

    func setAll(_ isSelected: Bool, for provider: CredentialTransferProvider) {
        let ids = items.filter { $0.provider == provider }.map(\.id)
        var next = selectedItemIDs
        if isSelected {
            next.formUnion(ids)
        } else {
            next.subtract(ids)
        }
        selectedItemIDs = next
    }

    func conflictAction(for item: CredentialTransferSelectableItem) -> CredentialImportConflictAction {
        conflictActions[item.id] ?? .overwrite
    }

    func setConflictAction(_ action: CredentialImportConflictAction, for item: CredentialTransferSelectableItem) {
        var next = conflictActions
        next[item.id] = action
        conflictActions = next
    }

    func result() -> CredentialTransferPanelResult {
        CredentialTransferPanelResult(
            selectedItemIDs: selectedItemIDs,
            conflictActions: conflictActions
        )
    }
}

struct CredentialTransferSelectionView: View {
    @ObservedObject var state: CredentialTransferPanelState
    let statusMessage: String?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        MenuPanelSurface {
            VStack(alignment: .leading, spacing: 0) {
                header

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(state.providerSections, id: \.0.id) { provider, items in
                            providerSection(provider: provider, items: items)
                        }
                    }
                    .padding(18)
                }

                Divider()

                footer
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.mode.title)
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .foregroundColor(MenuDesignTokens.ink)

            Text(state.mode.description)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(MenuDesignTokens.inkSoft)

            HStack(spacing: 8) {
                MenuCapsuleBadge(
                    text: state.mode == .export ? L.exportCredentials : L.importCredentials,
                    tint: MenuDesignTokens.accent
                )
                MenuCapsuleBadge(
                    text: "\(L.credentialsSelectedCount) \(state.selectedCount) / \(state.totalCount)",
                    tint: MenuDesignTokens.inkSoft
                )
                if state.mode == .importPreview, state.hasConflicts {
                    MenuCapsuleBadge(text: L.credentialsDuplicateBadge, tint: MenuDesignTokens.warning)
                }
            }

            if let statusMessage, !statusMessage.isEmpty {
                MenuNoticeRow(message: statusMessage, tone: .warning)
            }
        }
        .padding(18)
    }

    private func providerSection(
        provider: CredentialTransferProvider,
        items: [CredentialTransferSelectableItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MenuSectionHeading(
                    title: provider.title,
                    detail: "\(state.selectedCount(for: provider))/\(items.count)"
                )

                Spacer()

                Button(L.credentialsSelectAll) {
                    state.setAll(true, for: provider)
                }
                .buttonStyle(MenuSecondaryButtonStyle())

                Button(L.credentialsDeselectAll) {
                    state.setAll(false, for: provider)
                }
                .buttonStyle(MenuSecondaryButtonStyle())
            }

            VStack(spacing: 10) {
                ForEach(items) { item in
                    itemRow(item)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: MenuDesignTokens.sectionRadius, style: .continuous)
                .fill(MenuDesignTokens.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MenuDesignTokens.sectionRadius, style: .continuous)
                .stroke(MenuDesignTokens.subtleBorder, lineWidth: 0.8)
        }
    }

    private func itemRow(_ item: CredentialTransferSelectableItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { state.isSelected(item) },
                    set: { state.setSelected($0, for: item) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(MenuDesignTokens.ink)
                            .lineLimit(1)

                        MenuCapsuleBadge(text: item.provider.title, tint: MenuDesignTokens.inkSoft)

                        if let badgeText = item.badgeText, !badgeText.isEmpty {
                            MenuCapsuleBadge(text: badgeText, tint: MenuDesignTokens.accent)
                        }

                        if item.isSourceActive {
                            MenuCapsuleBadge(text: L.credentialsActiveBadge, tint: MenuDesignTokens.positive)
                        }

                        if item.hasConflict {
                            MenuCapsuleBadge(text: L.credentialsDuplicateBadge, tint: MenuDesignTokens.warning)
                        }
                    }

                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(MenuDesignTokens.inkSoft)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)
            }

            if state.mode == .importPreview, item.hasConflict, state.isSelected(item) {
                HStack(spacing: 12) {
                    Text(L.credentialsConflictLabel)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(MenuDesignTokens.inkSoft)

                    Picker("", selection: Binding(
                        get: { state.conflictAction(for: item) },
                        set: { state.setConflictAction($0, for: item) }
                    )) {
                        ForEach(CredentialImportConflictAction.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                .padding(.leading, 30)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MenuDesignTokens.surfaceMuted)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MenuDesignTokens.subtleBorder, lineWidth: 0.8)
        }
    }

    private var footer: some View {
        HStack {
            if !state.canConfirm {
                Text(L.credentialsNoAccountsSelected)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(MenuDesignTokens.critical)
            }

            Spacer()

            Button(L.cancel, action: onCancel)
                .buttonStyle(MenuSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)

            Button(state.mode.confirmTitle, action: onConfirm)
                .buttonStyle(MenuPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!state.canConfirm)
        }
        .padding(18)
    }
}

@MainActor
final class CredentialTransferWindowModel: ObservableObject {
    static let shared = CredentialTransferWindowModel()
    static let windowID = "credential-transfer"

    @Published var flow: CredentialTransferFlow?
    @Published var isImportPickerPresented = false
    @Published var shouldPromptForImportFile = false
    @Published var statusMessage: String?
    @Published var completionMessage: String?

    func prepareExport(
        codexAccounts: [TokenAccount],
        activeCodexStorageKey: String?,
        antigravityPool: AntigravityAccountPool
    ) {
        let items = CredentialTransferService.shared.exportItems(
            codexAccounts: codexAccounts,
            activeCodexStorageKey: activeCodexStorageKey,
            antigravityPool: antigravityPool
        )
        flow = CredentialTransferFlow(
            mode: .export,
            items: items,
            state: CredentialTransferPanelState(mode: .export, items: items)
        )
        statusMessage = nil
        shouldPromptForImportFile = false
        isImportPickerPresented = false
    }

    func beginImport() {
        flow = nil
        statusMessage = nil
        shouldPromptForImportFile = true
        isImportPickerPresented = false
    }

    func clearWindowState() {
        flow = nil
        statusMessage = nil
        shouldPromptForImportFile = false
        isImportPickerPresented = false
    }

    func clearCompletionMessage() {
        completionMessage = nil
    }
}

struct CredentialTransferWindowView: View {
    @EnvironmentObject private var store: TokenStore
    @EnvironmentObject private var antigravityStore: AntigravityAccountStore
    @EnvironmentObject private var transferModel: CredentialTransferWindowModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var languageRefreshToken = 0

    var body: some View {
        Group {
            if let flow = transferModel.flow {
                CredentialTransferSelectionView(
                    state: flow.state,
                    statusMessage: transferModel.statusMessage,
                    onCancel: closeWindow,
                    onConfirm: { confirm(flow) }
                )
                .frame(width: 720, height: 620)
            } else {
                MenuPanelSurface {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L.credentialsImportPreviewTitle)
                            .font(.system(size: 24, weight: .semibold, design: .serif))
                            .foregroundColor(MenuDesignTokens.ink)

                        Text(transferModel.statusMessage ?? L.credentialsImportHelp)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(MenuDesignTokens.inkSoft)
                            .lineLimit(3)

                        HStack(spacing: 8) {
                            Button {
                                transferModel.isImportPickerPresented = true
                            } label: {
                                Label(L.importCredentials, systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(MenuPrimaryButtonStyle())
                            .keyboardShortcut(.defaultAction)

                            Button(L.cancel) {
                                closeWindow()
                            }
                            .buttonStyle(MenuSecondaryButtonStyle())
                            .keyboardShortcut(.cancelAction)
                        }
                    }
                    .frame(width: 460, height: 220, alignment: .topLeading)
                    .padding(22)
                }
            }
        }
        .id(languageRefreshToken)
        .fileImporter(
            isPresented: $transferModel.isImportPickerPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportSelection(result)
        } onCancellation: {
            if transferModel.flow == nil {
                closeWindow()
            }
        }
        .onAppear {
            if transferModel.shouldPromptForImportFile {
                transferModel.shouldPromptForImportFile = false
                DispatchQueue.main.async {
                    transferModel.isImportPickerPresented = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            languageRefreshToken += 1
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            transferModel.statusMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                let bundle = try CredentialTransferService.shared.importBundleData(data)
                let items = CredentialTransferService.shared.importItems(
                    from: bundle,
                    existingCodexAccounts: store.accounts,
                    existingAntigravityAccounts: antigravityStore.accounts
                )
                guard !items.isEmpty else {
                    throw CredentialTransferError.emptyBundle
                }
                transferModel.flow = CredentialTransferFlow(
                    mode: .importPreview,
                    items: items,
                    state: CredentialTransferPanelState(mode: .importPreview, items: items)
                )
                transferModel.statusMessage = nil
            } catch {
                transferModel.statusMessage = error.localizedDescription
            }
        }
    }

    private func confirm(_ flow: CredentialTransferFlow) {
        let selection = flow.state.result()
        let selectionResult = CredentialTransferService.shared.makeSelectionResult(
            from: flow.items,
            selectedItemIDs: selection.selectedItemIDs,
            conflictActions: selection.conflictActions
        )

        switch flow.mode {
        case .export:
            do {
                let data = try CredentialTransferService.shared.exportBundleData(from: selectionResult)
                let panel = NSSavePanel()
                panel.canCreateDirectories = true
                panel.allowedContentTypes = [.json]
                panel.nameFieldStringValue = CredentialTransferService.shared.suggestedFilename()
                panel.title = L.exportCredentials
                panel.message = L.credentialsExportWarning

                guard panel.runModal() == .OK, let url = panel.url else { return }
                try SecureFileWriter.writeSensitiveData(data, to: url, secureParentDirectory: false)
                transferModel.completionMessage = L.credentialsExported(url.lastPathComponent, selectionResult.selectedCount)
                closeWindow()
            } catch {
                transferModel.statusMessage = error.localizedDescription
            }
        case .importPreview:
            do {
                let codexSummary = try store.applyImportedAccounts(
                    selectionResult.codexAccounts,
                    conflictActions: selectionResult.codexConflictActions
                )
                let antigravitySummary = antigravityStore.applyImportedPool(
                    selectionResult.antigravityPool,
                    conflictActions: selectionResult.antigravityConflictActions
                )
                transferModel.completionMessage = L.credentialsImported(
                    codexAdded: codexSummary.addedCount,
                    codexOverwritten: codexSummary.overwrittenCount,
                    codexSkipped: codexSummary.skippedCount,
                    antigravityAdded: antigravitySummary.addedCount,
                    antigravityOverwritten: antigravitySummary.overwrittenCount,
                    antigravitySkipped: antigravitySummary.skippedCount
                )
                closeWindow()
            } catch {
                transferModel.statusMessage = error.localizedDescription
            }
        }
    }

    private func closeWindow() {
        transferModel.clearWindowState()
        dismissWindow(id: CredentialTransferWindowModel.windowID)
    }
}
