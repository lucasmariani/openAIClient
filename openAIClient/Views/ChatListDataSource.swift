//
//  ChatListDataSource.swift
//  openAIClient
//
//  Created by Lucas on 30.06.25.
//

import UIKit

@MainActor
class ChatListDataSource: NSObject {
    
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
        case chat(OAChat)
    }
    
    private var diffableDataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private weak var collectionView: UICollectionView?
    
    func configure(for collectionView: UICollectionView) {
        self.collectionView = collectionView
        setupDataSource(for: collectionView)
    }



    private func setupDataSource(for collectionView: UICollectionView) {
        // Cell registration for chat items
        let chatCellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, OAChat> { cell, indexPath, chat in
            var content = UIListContentConfiguration.cell()
            content.text = chat.title
            content.secondaryText = "Tap to open"
            content.image = UIImage(systemName: "message")
            content.imageProperties.tintColor = .tertiaryLabel
            
#if targetEnvironment(macCatalyst)
            content.textProperties.font = .systemFont(ofSize: 13, weight: .medium)
            content.secondaryTextProperties.font = .systemFont(ofSize: 11, weight: .regular)
#endif
            
            cell.contentConfiguration = content

            // Configure background for selection states
            var backgroundConfig = UIBackgroundConfiguration.listCell()
            backgroundConfig.cornerRadius = 6
            cell.backgroundConfiguration = backgroundConfig

            // Configure update handler for state changes
            cell.configurationUpdateHandler = { cell, state in
                var updatedConfig = content
                var updatedBackground = backgroundConfig
                
                // Keep selected cells highlighted
                if state.isSelected {
                    updatedBackground.backgroundColor = .systemFill
                    updatedConfig.textProperties.color = .label
                    updatedConfig.secondaryTextProperties.color = .secondaryLabel
                } else if state.isHighlighted {
                    updatedBackground.backgroundColor = .systemFill.withAlphaComponent(0.5)
                    updatedConfig.textProperties.color = .label
                    updatedConfig.secondaryTextProperties.color = .secondaryLabel
                } else {
                    updatedBackground.backgroundColor = .clear
                    updatedConfig.textProperties.color = .label
                    updatedConfig.secondaryTextProperties.color = .tertiaryLabel
                }
                
                cell.contentConfiguration = updatedConfig
                cell.backgroundConfiguration = updatedBackground
            }

            // Configure accessories based on collection view's editing state
            if collectionView.isEditing {
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
        
        // Configure diffable data source
        diffableDataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .chat(let chat):
                return collectionView.dequeueConfiguredReusableCell(using: chatCellRegistration, for: indexPath, item: chat)
            }
        }
        
        diffableDataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }
    
    func updateSnapshot(with chats: [OAChat]) async {
        guard diffableDataSource != nil else { 
            assertionFailure("DataSource not configured. Call configure(for:) first")
            return 
        }
        
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.chats])
        
        let chatItems = chats.map { Item.chat($0) }
        snapshot.appendItems(chatItems, toSection: .chats)
        
        await diffableDataSource.apply(snapshot, animatingDifferences: true)
    }
    
    func reloadVisibleCells() {
        guard let collectionView = collectionView,
              diffableDataSource != nil else { return }
        
        var currentSnapshot = diffableDataSource.snapshot()
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems
        let visibleItems = visibleIndexPaths.compactMap { diffableDataSource.itemIdentifier(for: $0) }
        
        if !visibleItems.isEmpty {
            currentSnapshot.reloadItems(visibleItems)
            diffableDataSource.apply(currentSnapshot, animatingDifferences: false)
        }
    }
    
    func getSelectedChats() -> [OAChat] {
        guard let collectionView = collectionView,
              let selectedIndexPaths = collectionView.indexPathsForSelectedItems,
              !selectedIndexPaths.isEmpty else { return [] }
        
        return selectedIndexPaths.compactMap { indexPath -> OAChat? in
            guard let item = diffableDataSource.itemIdentifier(for: indexPath),
                  case .chat(let chat) = item else { return nil }
            return chat
        }
    }
    
    func chat(at indexPath: IndexPath) -> OAChat? {
        guard let item = diffableDataSource.itemIdentifier(for: indexPath),
              case .chat(let chat) = item else { return nil }
        return chat
    }
}

