//
//  OASidebarViewController.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import UIKit
import Combine

class OASidebarViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var dataSource: UITableViewDiffableDataSource<Int, String>!
    private let coreDataManager: OACoreDataManager
    private var cancellables = Set<AnyCancellable>()

    init(coreDataManager: OACoreDataManager) {
        self.coreDataManager = coreDataManager
        super.init(nibName: nil, bundle: nil)
        self.title = "Chats"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(tableView)
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.delegate = self
        tableView.bounces = true

        setupNavigationBar()
        setupDataSource()
        setupBindings()
        Task {
            await loadInitialChats()
            selectTopMostRowIfAvailable()
        }
    }

    private func setupNavigationBar() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addNewChat))
    }

    private func setupDataSource() {
        self.dataSource = UITableViewDiffableDataSource<Int, String>(
            tableView: self.tableView
        ) { [weak self] table, idxPath, chatID in
            guard let self = self else { return UITableViewCell() }
            let cell = table.dequeueReusableCell(withIdentifier: "Cell", for: idxPath)
            // Access chats directly from dataManager or a local copy updated by Combine
            if let chat = self.coreDataManager.chats.first(where: { $0.id == chatID }) {
                let fmt = DateFormatter(); fmt.dateStyle = .short; fmt.timeStyle = .short
                cell.textLabel?.text = self.formatDateForCellTitle(chat.date)
            }
            return cell
        }
    }

    private func formatDateForCellTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX") // Ensures consistent formatting
        formatter.dateFormat = "d MMMM - HH:mm"
        return formatter.string(from: date)
    }

    private func setupBindings() {
        self.coreDataManager.$chats
            .receive(on: DispatchQueue.main)
            .sink { [weak self] chats in
                self?.updateSnapshot(with: chats.map { $0.id })
            }
            .store(in: &cancellables)
    }

    private func updateSnapshot(with chatIDs: [String]) {
        var snap = NSDiffableDataSourceSnapshot<Int, String>()
        snap.appendSections([0])
        snap.appendItems(chatIDs)
        // Apply snapshot without async/await if dataSource.apply is synchronous
        // If dataSource.apply is async, ensure it's called correctly.
        // For UITableViewDiffableDataSource, `apply` can be called synchronously.
        self.dataSource.apply(snap, animatingDifferences: true)
    }

    func loadInitialChats() async {
        do {
            try await self.coreDataManager.fetchPersistedChats()
            // The Combine binding will automatically update the snapshot.
            // So, no need to manually apply snapshot here after fetch.
        } catch {
            // TODO: Add alert here.
            print("Failed to load chats:", error)
        }
    }

    @objc func addNewChat() {
        Task {
            do {
                try await coreDataManager.newChat()
            } catch {
                // TODO: Add alert here.
                print("Failed to create new chat:", error)
            }
        }
    }

    private func selectTopMostRowIfAvailable() {
        let chats = self.coreDataManager.chats
        if !chats.isEmpty,
           let chat = chats.max(by: { $0.date < $1.date }),
           let index = chats.firstIndex(of: chat) {
            let indexPath = IndexPath(row: index, section: 0)

            self.tableView.selectRow(at: indexPath, animated: true, scrollPosition: .top)
            self.tableView.delegate?.tableView?(tableView, didSelectRowAt: indexPath)
        }
    }
}

extension OASidebarViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let chatID = self.dataSource.itemIdentifier(for: indexPath) else { return }
        Task {
            let detailNav = splitViewController?.viewController(for: .secondary) as? UINavigationController
            let chatVC = detailNav?.topViewController as? OAChatViewController
            await chatVC?.loadChat(with: chatID)

            if self.splitViewController?.isCollapsed == true {
                self.splitViewController?.show(.secondary)
            }
        }
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let chatID = dataSource.itemIdentifier(for: indexPath) else { return nil }

        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] (_, _, completionHandler) in
            guard let self else {
                completionHandler(false)
                return
            }

            Task {
                do {
                    try await self.coreDataManager.deleteChat(with: chatID)
                    completionHandler(true)
                } catch {
                    print("Failed to delete chat with ID \(chatID): \(error)")
                    // TODO: Add alert here.
                    completionHandler(false)
                }
            }
        }
        
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}
