//
//  OAChatViewController.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import UIKit
import OpenAI
import Combine

var isMacCatalyst: Bool {
    #if targetEnvironment(macCatalyst)
    return true
    #else
    return false
    #endif
}

class OAChatViewController: UIViewController {

    private let tableView = UITableView()
    private let inputField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let inputContainerView = UIView()

    private var inputContainerBottomConstraint: NSLayoutConstraint?

    private var dataSource: UITableViewDiffableDataSource<Int, String>!

    private let chatDataManager: OAChatDataManager
    private var currentlySelectedModel: OpenAI.Model?

    private var cancellables = Set<AnyCancellable>()

    init(chatDataManager: OAChatDataManager) {
        self.chatDataManager = chatDataManager
        super.init(nibName: nil, bundle: nil)
        self.chatDataManager.onMessagesUpdated = { [weak self] reconfiguringItemID in
            self?.updateSnapshot(reconfiguringItemID: reconfiguringItemID)
        }
        self.currentlySelectedModel = self.chatDataManager.selectedModel
        title = "Chat"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        inputField.delegate = self
        tableView.allowsSelection = false
        setupSubviews()
        setupDataSource()
        setupKeyboardObservers()

        let tap = UITapGestureRecognizer(target: self, action: #selector(debugTap))
        inputField.addGestureRecognizer(tap)

        chatDataManager.$selectedModel
            .sink { [weak self] value in
                guard let self = self, isMacCatalyst else { return }
                if let button = self.navigationItem.rightBarButtonItem {
                    self.currentlySelectedModel = value
                    button.menu = self.makeModelSelectionMenu()
                }
            }
            .store(in: &cancellables)
    }

    @objc private func debugTap() {
        print("TextField tapped")
    }

//    override func viewDidAppear(_ animated: Bool) {
//        super.viewDidAppear(animated)
//        self.inputField.becomeFirstResponder()
//    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeKeyboardObservers()
    }

    private func setupNavBar() {
        // Add model selection button
        let modelButton = UIBarButtonItem(
            image: UIImage(systemName: "brain.head.profile"),
            style: .plain,
            target: nil,
            action: nil
        )
        navigationItem.rightBarButtonItem = modelButton

        if isMacCatalyst {
            modelButton.menu = makeModelSelectionMenu()
        } else {
            modelButton.target = self
            modelButton.action = #selector(didTapModelButton)
        }

    }

    private func setupSubviews() {
        // Input Container
        inputContainerView.backgroundColor = .systemGray6
        inputContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputContainerView)

        // Input Field
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.isEnabled = true
        inputField.isUserInteractionEnabled = true
        inputField.borderStyle = .roundedRect
        inputField.placeholder = "Type a message..."
        inputContainerView.addSubview(inputField)

        // Send Button
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(scale: .large)
        let sendButtonImage = UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config)
        sendButton.setImage(sendButtonImage, for: .normal)
        sendButton.tintColor = .label
        sendButton.addTarget(self, action: #selector(didTapSendButton), for: .touchUpInside)
        inputContainerView.addSubview(sendButton)

        // TableView
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(OAChatMessageCell.self, forCellReuseIdentifier: "chatMessageCell")
        tableView.separatorStyle = .none // Optional: if you want to hide separators
        tableView.keyboardDismissMode = .interactive // Optional: dismiss keyboard on scroll
        view.addSubview(tableView)

        inputContainerBottomConstraint = inputContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        inputContainerBottomConstraint?.isActive = true

        // Layout Constraints
        NSLayoutConstraint.activate([
            // Input Container View
            inputContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            // Let inputContainerView's height be determined by its content + padding

            // Input Field
            inputField.leadingAnchor.constraint(equalTo: inputContainerView.leadingAnchor, constant: 8),
            inputField.topAnchor.constraint(equalTo: inputContainerView.topAnchor, constant: 8),
            inputField.bottomAnchor.constraint(equalTo: inputContainerView.bottomAnchor, constant: -8),

            // Send Button
            sendButton.leadingAnchor.constraint(equalTo: inputField.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: inputContainerView.trailingAnchor, constant: -8),
            sendButton.centerYAnchor.constraint(equalTo: inputField.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 64), // Or make it intrinsic

            // TableView
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputContainerView.topAnchor)
        ])
    }

    private func setupDataSource() {
        self.dataSource = UITableViewDiffableDataSource<Int, String>(
            tableView: self.tableView
        ) { [weak self] tableView, indexPath, messageID in
            guard let self = self else { return UITableViewCell() }
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "chatMessageCell", for: indexPath) as? OAChatMessageCell else {
                return UITableViewCell()
            }
            cell.prepareForReuse()
            if let message = self.chatDataManager.messages.first(where: { $0.id == messageID }) {
                cell.configure(with: message.content, role: message.role)
            }
            return cell

        }
        self.tableView.dataSource = self.dataSource
    }

    private func updateSnapshot(reconfiguringItemID: String? = nil, animatingDifferences: Bool = true) {
        print("UPDATE SNAPSHOT - Reconfiguring ID: \(reconfiguringItemID ?? "none")")
        let currentMessages = self.chatDataManager.messages
        let messageIDs = currentMessages.map { $0.id }

        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(messageIDs)

        // If a specific item ID needs reconfiguring, tell the snapshot
        if let itemID = reconfiguringItemID, messageIDs.contains(itemID) {
            snapshot.reconfigureItems([itemID])
            print("Snapshot: Marked item \(itemID) for reconfiguration.")
        }

        self.dataSource.apply(snapshot, animatingDifferences: animatingDifferences) {
            // Optional: Completion block for debugging
            print("Snapshot applied. Message count: \(currentMessages.count).")
        }

        if !currentMessages.isEmpty {
            let lastIndexPath = IndexPath(item: currentMessages.count - 1, section: 0)
            if self.tableView.numberOfSections > 0 && self.tableView.numberOfRows(inSection: 0) > lastIndexPath.row {
                 self.tableView.scrollToRow(at: lastIndexPath, at: .bottom, animated: true)
            }
        }
    }

    func loadChat(with id: String) async {
        await self.chatDataManager.saveProvisionaryTextInput(self.inputField.text)
        if let chat = await self.chatDataManager.loadChat(with: id) {
            self.inputField.text = chat.provisionaryInputText
        }
        self.title = self.chatDataManager.getChatTitle(for: id) ?? "Chat"
    }
    
    @objc private func didTapSendButton() {
        guard let text = inputField.text, !text.isEmpty else {
            // Optionally, provide feedback if text is empty or chat is not selected
            return
        }

        // Create the new message object using OARole
        let newMessage = OAChatMessage(
            id: UUID().uuidString,
            role: .user,
            content: text,
            date: Date.now
        )

        // 1. Optimistically update the UI
        self.inputField.text = "" // Clear the input field
        self.chatDataManager.sendMessage(newMessage)
    }

    @objc private func didTapModelButton() {

        if !isMacCatalyst {
            self.presentModelSelectionActionSheet()
        }
    }

    @objc private func presentModelSelectionActionSheet() {
        let alert = UIAlertController(title: "Choose Model", message: nil, preferredStyle: .actionSheet)
        for model in OpenAI.Model.allCases.sorted(by: { $0.displayName < $1.displayName }) {
            let isSelected = (self.chatDataManager.selectedModel == model)
            let action = UIAlertAction(
                title: model.displayName + (isSelected ? " ✓" : ""),
                style: .default
            ) { [weak self] _ in
                Task {
                    await self?.chatDataManager.updateModel(model)
                }
            }
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController, let button = navigationItem.rightBarButtonItem {
            popover.barButtonItem = button
        }
        present(alert, animated: true)
    }

    private func makeModelSelectionMenu() -> UIMenu {
        return UIMenu(title: "Choose Model", children: OpenAI.Model.allCases.sorted(by: { $0.displayName < $1.displayName }).map { model in
            let isSelected = (self.currentlySelectedModel == model)
            return UIAction(
                title: model.displayName,
                state: isSelected ? .on : .off
            ) { [weak self] _ in
                Task {
                    await self?.chatDataManager.updateModel(model)
                }
            }
        })
    }
}

extension OAChatViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        didTapSendButton()
        return true
    }
}

extension OAChatViewController {
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillShow(notification: NSNotification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrameValue = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue,
              let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue,
              let curve = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue else {
            return
        }

        let keyboardFrameInScreen = keyboardFrameValue.cgRectValue
        let keyboardFrameInView = self.view.convert(keyboardFrameInScreen, from: nil)
        let intersection = self.view.bounds.intersection(keyboardFrameInView)
        let keyboardHeight = intersection.height

        inputContainerBottomConstraint?.constant = -keyboardHeight

        UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve), animations: {
            self.view.layoutIfNeeded()
        })
    }

    @objc private func keyboardWillHide(notification: NSNotification) {
        guard let userInfo = notification.userInfo,
              let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue,
              let curve = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue else {
            return
        }

        inputContainerBottomConstraint?.constant = 0

        UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve), animations: {
            self.view.layoutIfNeeded()
        })
    }

}
