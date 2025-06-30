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
    private let dataSource = ChatListDataSource()

    private let chatManager: OAChatManager
    private var pendingSelectionChatId: String?

    // Selection mode properties
    private var addButton: UIBarButtonItem!
    private var selectButton: UIBarButtonItem!
    private var doneButton: UIBarButtonItem!
    private var deleteButton: UIBarButtonItem!
    private var selectAllButton: UIBarButtonItem!
    private var flexibleSpace: UIBarButtonItem!

    init(chatManager: OAChatManager) {
        self.chatManager = chatManager
        super.init(nibName: nil, bundle: nil)
        self.title = "Chats"
    }

    required init?(coder: NSCoder) { fatalError() }


    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupCollectionView()
        setupCollectionViewUI()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateEditButtonState()
        Task { @MainActor in
            await self.dataSource.updateSnapshot(with: self.chatManager.chats)
            if let pendingChatId = self.pendingSelectionChatId {
                self.selectNewChatInCollectionView(chatId: pendingChatId)
                self.pendingSelectionChatId = nil
            }
        }
    }

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: createLayout())
        collectionView.delegate = self
        collectionView.allowsSelection = true
        collectionView.allowsMultipleSelection = false

        dataSource.configure(for: collectionView)
    }

    private func createLayout() -> UICollectionViewCompositionalLayout {
        var layoutConfig = UICollectionLayoutListConfiguration(appearance: .sidebar)
        layoutConfig.headerMode = .supplementary
        layoutConfig.showsSeparators = false

        // Enable swipe-to-delete
        layoutConfig.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self = self,
                  !self.isEditing, // Disable swipe actions in editing mode
                  let chat = self.dataSource.chat(at: indexPath) else { return nil }

            let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { _, _, completion in
                Task {
                    await self.deleteChat(with: chat.id, completion: completion)
                }
            }
            deleteAction.image = UIImage(systemName: "trash")

            return UISwipeActionsConfiguration(actions: [deleteAction])
        }

        return UICollectionViewCompositionalLayout.list(using: layoutConfig)
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

        selectButton = UIBarButtonItem(
            systemItem: .edit,
            primaryAction: UIAction { [weak self] _ in
                self?.setEditing(true, animated: true)
            }
        )

        doneButton = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak self] _ in
                self?.setEditing(false, animated: true)
            }
        )
        doneButton.style = .prominent

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

    private func setupCollectionViewUI() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
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
            self.toolbarItems = [self.selectAllButton, self.flexibleSpace, self.deleteButton, self.doneButton]
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
            dataSource.reloadVisibleCells()

        } else {
            restoreButtonsConfiguration()

            // Disable multi-selection
            collectionView.allowsMultipleSelection = false

            // Clear selections
            collectionView.indexPathsForSelectedItems?.forEach {
                collectionView.deselectItem(at: $0, animated: animated)
            }

            // Update cell accessories
            dataSource.reloadVisibleCells()
            updateSelectionUI()
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

    private func deleteSelectedChats() {
        let selectedChats = dataSource.getSelectedChats()

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

    private func navigateToChat(with id: String) async {
        let detailNav = splitViewController?.viewController(for: .secondary) as? UINavigationController
        let chatVC = detailNav?.topViewController as? OAChatViewController
        await chatVC?.loadChat(with: id)

        if splitViewController?.isCollapsed == true {
            splitViewController?.show(.secondary)
        }
    }

    private func deleteChat(with id: String, completion: ((Bool) -> Void)?) async {
        do {
            try await self.chatManager.deleteChat(with: id)
            completion?(true)
        } catch {
            await MainActor.run {
                self.showErrorAlert(message: "Failed to delete chat: \(error.localizedDescription)")
                completion?(false)
            }
        }
    }
}

// MARK: - UICollectionViewDelegate

extension OASidebarViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // In selection mode, just update UI
        if isEditing {
            updateSelectionUI()
            return
        }

        // Normal mode - open chat
        guard let chat = dataSource.chat(at: indexPath) else { return }

        print("Debug: Selected chat with ID: \(chat.id), title: \(chat.title)")
        Task {
            await navigateToChat(with: chat.id)
        }
        collectionView.deselectItem(at: indexPath, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        if isEditing {
            updateSelectionUI()
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let chat = dataSource.chat(at: indexPath) else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let deleteAction = UIAction(title: "Delete",
                                        image: UIImage(systemName: "trash"),
                                        attributes: .destructive) { [weak self] _ in
                Task { @MainActor in
                    await self?.deleteChat(with: chat.id, completion: nil)
                }
            }

            let selectAction = UIAction(title: "Select",
                                        image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in
                self?.setEditing(true, animated: true)
                // Select this item after entering edit mode
                Task { @MainActor in
                    self?.collectionView.selectItem(at: indexPath, animated: true, scrollPosition: [])
                    self?.updateSelectionUI()
                }
            }

            let deselectAction = UIAction(title: "Deselect",
                                          image: UIImage(systemName: "checkmark.circle.badge.xmark")) { [weak self] _ in
                self?.setEditing(true, animated: true)
                // Select this item after entering edit mode
                Task { @MainActor in
                    self?.collectionView.deselectItem(at: indexPath, animated: true)
                    self?.updateSelectionUI()
                }
            }
            let isSelected = collectionView.indexPathsForSelectedItems?.contains { $0 == indexPath } ?? false
            if self.isEditing {
                return UIMenu(title: "", children: [isSelected ? deselectAction : selectAction])
            }
            return UIMenu(title: "", children: [selectAction, deleteAction])
        }
    }
}
