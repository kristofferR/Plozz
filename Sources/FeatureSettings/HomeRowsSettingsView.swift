#if canImport(SwiftUI)
import SwiftUI
import CoreModels
import CoreUI

/// The shared section editor adapts existing row feeds without changing their identities.
public struct HomeRowsSettingsView: View {
    public let libraries: [AggregatedLibrary]
    public let accounts: [ResolvedAccount]
    public let visibility: HomeLibraryVisibilityModel
    @Environment(HeroSettingsModel.self) private var hero
    @Environment(HeroBackgroundSettingsModel.self) private var heroBackground
    @State private var inventory: HomeSectionCatalogModel
    @State private var isReordering = false
    @State private var isLifting = false
    @State private var reloadRevision = 0
    @State private var editError: AppError?

    public init(
        libraries: [AggregatedLibrary], accounts: [ResolvedAccount],
        visibility: HomeLibraryVisibilityModel
    ) {
        self.init(libraries: libraries, accounts: accounts, visibility: visibility, inventory: HomeSectionCatalogModel())
    }

    init(
        libraries: [AggregatedLibrary], accounts: [ResolvedAccount],
        visibility: HomeLibraryVisibilityModel, inventory: HomeSectionCatalogModel
    ) {
        self.libraries = libraries
        self.accounts = accounts
        self.visibility = visibility
        _inventory = State(initialValue: inventory)
    }

    private var requestID: HomeSectionCatalogModel.RequestID {
        HomeSectionCatalogModel.requestID(libraries: libraries, accounts: accounts, visibility: visibility)
    }

    public var body: some View {
        HomeEditorPage(title: Text("Customize Home")) {
            #if os(tvOS)
            HStack(spacing: SettingsFormMetrics.controlSpacing) {
                SettingsPageHeader("Customize Home")
                reorderButton
            }
            editorControls
            #endif
            HomeEditorLink {
                HomeHeroSettingsView(libraries: libraries, accounts: accounts, visibility: visibility)
                    .environment(hero)
                    .environment(heroBackground)
            } label: {
                HomeEditorRowLabel(
                    title: Text("Hero"), subtitle: heroSummary
                )
            }
            .accessibilityIdentifier("home-section-hero")
            .disabled(isReordering)

            let catalog = inventory.requestID == requestID ? inventory.catalog : HomeSectionCatalog(libraries: [])
            let sections = catalog.sections(in: visibility.visibility)
            let choices = catalog.editableChoices(in: visibility.visibility)
            if isReordering {
                let byID = Dictionary(choices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                LiftableReorderList(
                    sections: .init(enabled: sections.enabled, disabled: []),
                    disabledSectionTitle: "Hidden", disabledPlaceholder: "No hidden rows",
                    isLifting: $isLifting, allowsHiding: false,
                    row: { id in
                        let choice = byID[id]
                        return .init(
                            title: choice?.homeEditorTitle ?? Text("Section"),
                            symbolName: "rectangle.grid.1x2",
                            providerKind: choice?.library?.providerKind ?? choice?.serverRow?.providerKind,
                            mediaShareTransport: choice?.library?.transportKind,
                            subtitle: choice?.homeEditorSource
                        )
                    },
                    onChange: { order in
                        do {
                            try visibility.reorderHomeSections(order.enabled, catalog: catalog)
                            editError = nil
                        } catch { editError = (error as? AppError) ?? .invalidResponse }
                    }
                )
                .disabled(inventory.isLoading)
                .accessibilityIdentifier("home-section-reorder-list")
            } else {
                ForEach(sections.enabled, id: \.self) { id in
                    if let choice = choices.first(where: { $0.id == id }) {
                        HomeEditorLink {
                            HomeSectionSettingsView(
                                choice: choice, inventory: inventory, visibility: visibility,
                                libraries: libraries, accounts: accounts
                            )
                        } label: {
                            HomeSectionChoiceLabel(choice: choice)
                        }
                        .accessibilityIdentifier("home-section-\(id.presentationID)")
                    }
                }
            }
            addSectionButton(identifier: "home-section-add-bottom")
            if editError != nil {
                InlineErrorMessage(Text("Couldn't update this section. Try again."))
            }
            HomeCatalogStatus(inventory: inventory, accounts: accounts, libraries: libraries) {
                reloadRevision += 1
            }
            .disabled(isReordering)
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                SettingsPageLink {
                    addSectionDestination
                } label: {
                    Label("Add section", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .disabled(isReordering)
                .accessibilityIdentifier("home-section-add")
                reorderButton
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            editorControls
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background { SettingsPageBackground() }
        }
        #endif
        .task(id: HomeSectionCatalogModel.loadID(
            libraries: libraries, accounts: accounts, visibility: visibility, revision: reloadRevision
        )) {
            await inventory.load(libraries: libraries, accounts: accounts, visibility: visibility)
        }
        .onChange(of: requestID) { _, _ in
            isReordering = false
            isLifting = false
            editError = nil
        }
    }

    private var editorControls: some View {
        #if os(tvOS)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { controls }
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) { controls }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        #else
        controls
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }

    private var controls: some View {
        Group {
            HomeRowPresetPicker(visibility: visibility)
                .id(ObjectIdentifier(visibility))
                .disabled(isReordering)
            #if os(tvOS)
            addSectionButton(identifier: "home-section-add")
            #endif
        }
    }

    private var reorderButton: some View {
        Button {
            isReordering.toggle()
            isLifting = false
        } label: {
            if isReordering { Text("Done").fixedSize(horizontal: false, vertical: true) }
            else { Text("Reorder").fixedSize(horizontal: false, vertical: true) }
        }
        .disabled(isLifting || (!isReordering && (inventory.isLoading
            || inventory.catalog.sections(in: visibility.visibility).enabled.count < 2)))
        .accessibilityIdentifier("home-section-reorder")
        #if os(tvOS)
        .plozzActionButton(role: .secondary)
        #endif
    }

    private func addSectionButton(identifier: String) -> some View {
        SettingsPageLink {
            addSectionDestination
        } label: {
            Text("Add section").fixedSize(horizontal: false, vertical: true)
        }
        .plozzActionButton(role: .secondary)
        .disabled(isReordering)
        .accessibilityIdentifier(identifier)
    }

    private var addSectionDestination: some View {
        HomeAddSectionView(
            inventory: inventory, visibility: visibility, libraries: libraries, accounts: accounts
        )
    }

    private var heroSummary: Text {
        #if os(tvOS)
        if hero.settings.style == .followsFocus { return Text("Showcase") }
        #endif
        return hero.settings.isEnabled ? Text("Pinned at top") : Text("Off")
    }
}
#endif
