//
//  OASidebarViewController.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import UIKit
import Observation

class OASidebarViewController: UIViewController {
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let chatManager: OAChatManager
    private var pendingSelectionChatId: String?

    // Selection mode properties
    private var addButton: UIBarButtonItem!
    private var selectButton: UIBarButtonItem!
    private var cancelButton: UIBarButtonItem!
    private var deleteButton: UIBarButtonItem!
    private var selectAllButton: UIBarButtonItem!
    private var flexibleSpace: UIBarButtonItem!

    enum Section: Int, CaseIterable {
        case chats

        var title: String {
            switch self {
            case .chats:
                return "Recent Chats"
            }
        }
    }

    enum Item: Hashable {
        case chat(OAChat) // Full chat object
    }

    init(chatManager: OAChatManager) {
        self.chatManager = chatManager
        super.init(nibName: nil, bundle: nil)
        self.title = "Chats"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        setupNavigationBar()
        setupDataSource()
    }

    private func setupNavigationBar() {
        // Large title for modern look
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        // Create bar button items
        addButton = UIBarButtonItem(
            systemItem: .add,
            primaryAction: UIAction { [weak self] _ in
                Task {
                    await self?.addNewChat()
                }
            }
        )

        let symbolConf: UIImage.SymbolConfiguration = UIImage.SymbolConfiguration.preferringMulticolor()
        let checkmarkImage = UIImage(systemName: "checkmark.circle")?.withConfiguration(symbolConf)
        selectButton = UIBarButtonItem(
            image: checkmarkImage,
            primaryAction: UIAction { [weak self] _ in
                self?.setEditing(true, animated: true)
            }
        )

        cancelButton = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in
                self?.setEditing(false, animated: true)
            }
        )

        // Create toolbar items
        deleteButton = UIBarButtonItem(
            systemItem: .trash,
            primaryAction: UIAction { [weak self] _ in
                self?.deleteSelectedChats()
            }
        )
        deleteButton.isEnabled = false

        selectAllButton = UIBarButtonItem(
            title: "Select All",
            primaryAction: UIAction { [weak self] _ in
                self?.toggleSelectAll()
            }
        )

        flexibleSpace = UIBarButtonItem(systemItem: .flexibleSpace)
        restoreButtonsConfiguration()
    }

    private func setupCollectionView() {
        var layoutConfig = UICollectionLayoutListConfiguration(appearance: .sidebar)
        layoutConfig.headerMode = .supplementary
        layoutConfig.showsSeparators = false

        // Enable swipe-to-delete
        layoutConfig.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self = self,
                  !self.isEditing, // Disable swipe actions in editing mode
                  let item = self.dataSource.itemIdentifier(for: indexPath),
                  case .chat(let chat) = item else { return nil }

            let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { _, _, completion in
                Task {
                    do {
                        try await self.chatManager.deleteChat(with: chat.id)
                        completion(true)
                    } catch {
                        await MainActor.run {
                            self.showErrorAlert(message: "Failed to delete chat: \(error.localizedDescription)")
                        }
                        completion(false)
                    }
                }
            }
            deleteAction.image = UIImage(systemName: "trash")

            return UISwipeActionsConfiguration(actions: [deleteAction])
        }

        let layout = UICollectionViewCompositionalLayout.list(using: layoutConfig)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.delegate = self

        collectionView.allowsSelection = true
        collectionView.allowsMultipleSelection = false

        view.addSubview(collectionView)
    }

    private func setupDataSource() {
        // Register cell types
        let chatCellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, OAChat> { [weak self] cell, indexPath, chat in
            var content = cell.defaultContentConfiguration()
            content.text = chat.title
            content.secondaryText = "Tap to open"
            content.image = UIImage(systemName: "message")
            content.imageProperties.tintColor = .tertiaryLabel
            cell.contentConfiguration = content

            // Configure accessories based on editing mode
            if self?.isEditing == true {
                cell.accessories = [.multiselect()]
            } else {
                cell.accessories = []
            }
        }

        // Header registration
        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { supplementaryView, elementKind, indexPath in
            let section = Section.allCases[indexPath.section]
            var content = supplementaryView.defaultContentConfiguration()
            content.text = section.title
            supplementaryView.contentConfiguration = content
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .chat(let chat):
                return collectionView.dequeueConfiguredReusableCell(using: chatCellRegistration, for: indexPath, item: chat)
            }
        }

        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateEditButtonState()
        Task { @MainActor in
            await self.updateSnapshot(with: self.chatManager.chats)
            if let pendingChatId = self.pendingSelectionChatId {
                self.selectNewChatInCollectionView(chatId: pendingChatId)
                self.pendingSelectionChatId = nil
            }
        }
    }

    private func updateSnapshot(with chats: [OAChat]) async {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.chats])

        // Add existing chats
        let chatItems = chats.map { Item.chat($0) }
        snapshot.appendItems(chatItems, toSection: .chats)
        await dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func selectLatestChat() {
        let chats = chatManager.chats
        guard !chats.isEmpty else { return }

        let indexPath = IndexPath(item: 0, section: 0)
        collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: indexPath)
    }

    @objc private func addNewChat() async {
        do {
            // Create new chat and automatically select it
            let newChatId = try await chatManager.createAndSelectNewChat()

            await MainActor.run {
                // Schedule the selection to happen after the collection view updates
                self.pendingSelectionChatId = newChatId

                // Handle split view controller navigation for different platforms
                self.handleSplitViewNavigationForNewChat()
            }
        } catch {
            await MainActor.run {
                showErrorAlert(message: "Failed to create new chat: \(error.localizedDescription)")
            }
        }
    }

    /// Selects the newly created chat in the collection view
    private func selectNewChatInCollectionView(chatId: String) {
        // Find the index of the new chat (it should be the first item since chats are sorted by date)
        let chats = chatManager.chats
        if let chatIndex = chats.firstIndex(where: { $0.id == chatId }) {
            let indexPath = IndexPath(item: chatIndex, section: 0)

            // Safety check: ensure collection view has been updated with the expected number of items
            let collectionViewItemCount = collectionView.numberOfItems(inSection: 0)

            guard indexPath.item < collectionViewItemCount else {
                print("⚠️ Cannot select item at index \(indexPath.item) - collection view only has \(collectionViewItemCount) items")
                return
            }

            print("✅ Selecting item at indexPath: \(indexPath), collection view has \(collectionViewItemCount) items")
            collectionView.selectItem(at: indexPath, animated: true, scrollPosition: .top)
        }
    }

    /// Handles split view controller navigation after creating a new chat
    private func handleSplitViewNavigationForNewChat() {
        // If split view is collapsed (iPhone), show the detail view
        if splitViewController?.isCollapsed == true {
            splitViewController?.show(.secondary)
        }
        // On iPad/Mac Catalyst, both views are already visible, so no additional navigation needed
    }

    private func showErrorAlert(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Selection Mode

    private func updateEditButtonState() {
        if self.isEditing {
            setButtonsToEditMode()
        } else {
            restoreButtonsConfiguration()
        }
    }

    func restoreButtonsConfiguration() {
        navigationController?.setToolbarHidden(false, animated: false)
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut], animations: {
            self.navigationItem.rightBarButtonItems = [self.addButton]
            if !self.chatManager.chats.isEmpty {
                self.toolbarItems = [self.flexibleSpace, self.selectButton]
            } else {
                self.toolbarItems = []
            }
        })
    }

    func setButtonsToEditMode() {
        navigationController?.setToolbarHidden(false, animated: false)
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut], animations: {
            self.navigationItem.rightBarButtonItems = []
            self.toolbarItems = [self.flexibleSpace, self.selectAllButton, self.deleteButton, self.cancelButton]
        })
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)

        if editing {
            // Enter selection mode
            setButtonsToEditMode()

            collectionView.allowsSelection = true
            collectionView.allowsMultipleSelection = true

            // Update cell accessories
            reloadVisibleCells()

        } else {
            restoreButtonsConfiguration()

            // Disable multi-selection
            collectionView.allowsMultipleSelection = false

            // Clear selections
            collectionView.indexPathsForSelectedItems?.forEach {
                collectionView.deselectItem(at: $0, animated: animated)
            }

            // Update cell accessories
            reloadVisibleCells()
            updateSelectionUI()
        }
    }

    private func reloadVisibleCells() {
        // Create a new snapshot to trigger cell reconfiguration
        var currentSnapshot = dataSource.snapshot()
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems
        let visibleItems = visibleIndexPaths.compactMap { dataSource.itemIdentifier(for: $0) }

        if !visibleItems.isEmpty {
            currentSnapshot.reloadItems(visibleItems)
            dataSource.apply(currentSnapshot, animatingDifferences: false)
        }
    }

    private func toggleSelectAll() {
        let totalItems = collectionView.numberOfItems(inSection: 0)
        let selectedItems = collectionView.indexPathsForSelectedItems?.count ?? 0

        if selectedItems == totalItems {
            // Deselect all
            collectionView.indexPathsForSelectedItems?.forEach {
                collectionView.deselectItem(at: $0, animated: true)
            }
            selectAllButton.title = "Select All"
        } else {
            // Select all
            for item in 0..<totalItems {
                let indexPath = IndexPath(item: item, section: 0)
                collectionView.selectItem(at: indexPath, animated: true, scrollPosition: [])
            }
            selectAllButton.title = "Deselect All"
        }
        updateSelectionUI()
    }

    private func updateSelectionUI() {
        let selectedCount = collectionView.indexPathsForSelectedItems?.count ?? 0
        let totalItems = collectionView.numberOfItems(inSection: 0)

        // Update delete button
        deleteButton.isEnabled = selectedCount > 0

        // Update select all button
        if selectedCount == totalItems && totalItems > 0 {
            selectAllButton.title = "Deselect All"
        } else {
            selectAllButton.title = "Select All"
        }
    }

    private func deleteSelectedChats() {
        guard let selectedIndexPaths = collectionView.indexPathsForSelectedItems,
              !selectedIndexPaths.isEmpty else { return }

        let selectedChats = selectedIndexPaths.compactMap { indexPath -> OAChat? in
            guard let item = dataSource.itemIdentifier(for: indexPath),
                  case .chat(let chat) = item else { return nil }
            return chat
        }

        let chatCount = selectedChats.count
        let message = chatCount == 1 ?
        "Are you sure you want to delete this chat? This action cannot be undone." :
        "Are you sure you want to delete \(chatCount) chats? This action cannot be undone."

        let alert = UIAlertController(
            title: "Delete Chat\(chatCount > 1 ? "s" : "")",
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            Task {
                await self?.performBatchDelete(chats: selectedChats)
            }
        })

        present(alert, animated: true)
    }

    private func performBatchDelete(chats: [OAChat]) async {
        do {
            let chatIds = chats.map { $0.id }
            try await chatManager.deleteChats(with: chatIds)

            await MainActor.run {
                setEditing(false, animated: true)
            }
        } catch {
            await MainActor.run {
                showErrorAlert(message: "Failed to delete chats: \(error.localizedDescription)")
            }
        }
    }
}

extension OASidebarViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // In selection mode, just update UI
        if isEditing {
            updateSelectionUI()
            return
        }

        // Normal mode - open chat
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {
        case .chat(let chat):
            print("Debug: Selected chat with ID: \(chat.id), title: \(chat.title)")
            Task {
                let detailNav = splitViewController?.viewController(for: .secondary) as? UINavigationController
                let chatVC = detailNav?.topViewController as? OAChatViewController
                await chatVC?.loadChat(with: chat.id)

                if splitViewController?.isCollapsed == true {
                    splitViewController?.show(.secondary)
                }
            }
        }

        collectionView.deselectItem(at: indexPath, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        if isEditing {
            updateSelectionUI()
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case .chat(let chat) = item else {return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                Task {
                    do {
                        try await self?.chatManager.deleteChat(with: chat.id)
                    } catch {
                        await MainActor.run {
                            self?.showErrorAlert(message: "Failed to delete chat: \(error.localizedDescription)")
                        }
                    }
                }
            }

            let selectAction = UIAction(title: "Select", image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in
                self?.setEditing(true, animated: true)
                // Select this item after entering edit mode
                DispatchQueue.main.async {
                    collectionView.selectItem(at: indexPath, animated: true, scrollPosition: [])
                    self?.updateSelectionUI()
                }
            }
            if self.isEditing {
                return UIMenu(title: "", children: [selectAction])
            }
            return UIMenu(title: "", children: [selectAction, deleteAction])
        }
    }
}
