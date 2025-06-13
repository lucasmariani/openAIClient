//
//  OASidebarViewController.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import UIKit
import Combine

class OASidebarViewController: UIViewController {
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let repository: ChatRepository
    private var cancellables = Set<AnyCancellable>()

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
        case chat(String) // Chat ID
    }

    init(repository: ChatRepository) {
        self.repository = repository
        super.init(nibName: nil, bundle: nil)
        self.title = "Chats"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        setupNavigationBar()
        setupDataSource()
        setupBindings()
    }

    private func setupNavigationBar() {
        // Large title for modern look
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        // Add toolbar items
        let addButton = UIBarButtonItem(
            systemItem: .add,
            primaryAction: UIAction { [weak self] _ in
                Task {
                    await self?.addNewChat()
                    self?.selectLatestChat()
                }
            }
        )

        navigationItem.rightBarButtonItem = addButton
    }

    private func setupCollectionView() {
        var layoutConfig = UICollectionLayoutListConfiguration(appearance: .sidebar)
        layoutConfig.headerMode = .supplementary
        layoutConfig.showsSeparators = false
        
        // Enable swipe-to-delete
        layoutConfig.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self = self,
                  let item = self.dataSource.itemIdentifier(for: indexPath),
                  case .chat(let chatID) = item else { return nil }
            
            let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { _, _, completion in
                Task {
                    do {
                        try await self.repository.deleteChat(with: chatID)
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

        view.addSubview(collectionView)
    }

    private func setupDataSource() {
        // Register cell types
        let chatCellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, indexPath, chatID in
            Task {
                guard let self = self,
                      let chat = try? await self.repository.getChat(with: chatID) else { return }
                
                await MainActor.run {
                    var content = cell.defaultContentConfiguration()
                    content.text = chat.title
                    content.secondaryText = "Tap to open"
                    content.image = UIImage(systemName: "message")
                    content.imageProperties.tintColor = .tertiaryLabel
                    cell.contentConfiguration = content
                    cell.accessories = []
                }
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
            case .chat(let chatID):
                return collectionView.dequeueConfiguredReusableCell(using: chatCellRegistration, for: indexPath, item: chatID)
            }
        }

        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    private func setupBindings() {
        repository.chatsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] chats in
                self?.updateSnapshot(with: chats.map { $0.id })
            }
            .store(in: &cancellables)
    }

    private func updateSnapshot(with chatIDs: [String]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.chats])

        // Add existing chats
        let chatItems = chatIDs.map { Item.chat($0) }

        chatIDs.forEach { print("ID: \($0)")}
        print("Chats in CD count: \(chatIDs.count)")

        snapshot.appendItems(chatItems, toSection: .chats)

        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func selectLatestChat() {
        Task {
            do {
                let chats = try await repository.getChats()
                guard !chats.isEmpty else { return }
                await MainActor.run {
                    let indexPath = IndexPath(item: 0, section: 0)
                    self.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
                    self.collectionView.delegate?.collectionView?(self.collectionView, didSelectItemAt: indexPath)
                }
            } catch {
                print("Failed to get chats for selection: \(error)")
            }
        }
    }

    @objc private func addNewChat() async {
        do {
            _ = try await repository.createNewChat()
        } catch {
            await MainActor.run {
                showErrorAlert(message: "Failed to create new chat: \(error.localizedDescription)")
            }
        }
    }

    private func showErrorAlert(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension OASidebarViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // TODO: check that the cell isn't already selected. i dont want to reload everything just because.
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {
        case .chat(let chatID):
            Task {
                let detailNav = splitViewController?.viewController(for: .secondary) as? UINavigationController
                let chatVC = detailNav?.topViewController as? OAChatViewController
                await chatVC?.loadChat(with: chatID)

                if splitViewController?.isCollapsed == true {
                    splitViewController?.show(.secondary)
                }
            }
        }

        collectionView.deselectItem(at: indexPath, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case .chat(let chatID) = item else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                Task {
                    do {
                        try await self?.repository.deleteChat(with: chatID)
                    } catch {
                        await MainActor.run {
                            self?.showErrorAlert(message: "Failed to delete chat: \(error.localizedDescription)")
                        }
                    }
                }
            }

            return UIMenu(title: "", children: [deleteAction])
        }
    }
}
