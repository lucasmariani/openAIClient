//
//  OAChatViewController.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import UIKit
import Observation

class OAChatViewController: UIViewController {
    
    private enum ChatStateIdentifier: String {
        case emptyPlaceholder
        case errorPlaceholder
    }
    
    private struct Constants {
        static let emptyPlaceholder = ChatStateIdentifier.emptyPlaceholder.rawValue
        static let errorPlaceholder = ChatStateIdentifier.errorPlaceholder.rawValue
        static let emptyPlaceholerText = "Select a chat to start messaging"
        static let errorPlaceholderText = "Error loading chat"
        static let streamingPlacerholderText = "Streaming response..."
        static let loadedPlaceholderText = "Type a message..."
        
        static let cellId = "chatMessageCell"
    }
    
    private let tableView = UITableView()
    private let inputField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let inputContainerView = UIView()
    
    private var inputContainerBottomConstraint: NSLayoutConstraint?
    
    private var dataSource: UITableViewDiffableDataSource<Int, String>!
    
    private let chatDataManager: OAChatDataManager
    private var currentlySelectedModel: OAModel?
    
    private var observationTask: Task<Void, Never>?
    
    init(chatDataManager: OAChatDataManager) {
        self.chatDataManager = chatDataManager
        super.init(nibName: nil, bundle: nil)
        self.currentlySelectedModel = self.chatDataManager.selectedModel
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    deinit {
        observationTask?.cancel()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground
        self.inputField.delegate = self
        self.tableView.allowsSelection = false
        self.setupSubviews()
        self.setupDataSource()
        self.setupNavBar()
        self.chatDataManager.loadLatestChat()
        
        startObservation()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupKeyboardObservers()
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeKeyboardObservers()
    }
    
    private func setupNavBar() {
        self.title = nil
        self.navigationItem.largeTitleDisplayMode = .never
        
        let modelButton = UIBarButtonItem(
            image: UIImage(systemName: "brain.head.profile"),
            style: .plain,
            target: nil,
            action: nil
        )
        navigationItem.rightBarButtonItem = modelButton
        
        if OAPlatform.isMacCatalyst {
            modelButton.menu = makeModelSelectionMenu()
        } else {
            modelButton.target = self
            modelButton.action = #selector(didTapModelButton)
        }
    }
    
    private func setupSubviews() {
        // Input Container
        
        inputContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputContainerView)
        
        // Input Field
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.isEnabled = true
        inputField.isUserInteractionEnabled = true
        inputField.borderStyle = .roundedRect
        //        inputField.placeholder = Constants.loadedPlaceholderText
        inputContainerView.addSubview(inputField)
        
        // Send Button
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(scale: .large)
        let sendButtonImage = UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config)
        sendButton.setImage(sendButtonImage, for: .normal)
        sendButton.tintColor = .label
        sendButton.addTarget(self, action: #selector(didTapSendButton), for: .touchUpInside)
        
#if !targetEnvironment(macCatalyst)
        sendButton.configuration = .glass()
#endif
        inputContainerView.addSubview(sendButton)
        
        // TableView
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(OAChatMessageCell.self, forCellReuseIdentifier: Constants.cellId)
        tableView.separatorStyle = .none // Optional: if you want to hide separators
        tableView.keyboardDismissMode = .interactive // Optional: dismiss keyboard on scroll
        view.addSubview(tableView)
        
        inputContainerBottomConstraint = inputContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        inputContainerBottomConstraint?.isActive = true
        
        // Layout Constraints
        NSLayoutConstraint.activate([
            // Input Container View
            inputContainerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            inputContainerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            
            
            // Input Field
            inputField.leadingAnchor.constraint(equalTo: inputContainerView.leadingAnchor, constant: 8),
            inputField.topAnchor.constraint(equalTo: inputContainerView.topAnchor, constant: 8),
            inputField.bottomAnchor.constraint(equalTo: inputContainerView.bottomAnchor, constant: -8),
            
            // Send Button
            sendButton.leadingAnchor.constraint(equalTo: inputField.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: inputContainerView.trailingAnchor, constant: -8),
            sendButton.centerYAnchor.constraint(equalTo: inputField.centerYAnchor),
            sendButton.heightAnchor.constraint(equalTo: inputField.heightAnchor),
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
        ) { [weak self] (tableView: UITableView, indexPath: IndexPath, messageID: String) -> UITableViewCell in
            guard let self = self else { return UITableViewCell() }
            
            // Handle placeholder cases
            if messageID == Constants.emptyPlaceholder {
                let cell = UITableViewCell()
                cell.textLabel?.text = Constants.emptyPlaceholerText
                cell.textLabel?.textColor = .secondaryLabel
                cell.textLabel?.textAlignment = .center
                cell.selectionStyle = .none
                return cell
            }
            
            if messageID == Constants.errorPlaceholder {
                let cell = UITableViewCell()
                cell.textLabel?.text = Constants.errorPlaceholderText
                cell.textLabel?.textColor = .systemRed
                cell.textLabel?.textAlignment = .center
                cell.selectionStyle = .none
                return cell
            }
            
            // Handle normal message case
            guard let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellId, for: indexPath) as? OAChatMessageCell else {
                return UITableViewCell()
            }
            
            if case .chat(_, let messages, _, _) = self.chatDataManager.viewState,
               let message = messages.first(where: { $0.id == messageID }) {
                cell.configure(with: message.content, role: message.role)
            } else {
                cell.configure(with: "Message not found", role: .system)
            }
            return cell
        }
        self.tableView.dataSource = self.dataSource
    }
    
    private func startObservation() {
        observationTask?.cancel()
        observationTask = Task { @MainActor in
            // Use the clean AsyncStream from ChatDataManager
            for await event in chatDataManager.uiEventStream {
                guard !Task.isCancelled else { break }
                
                switch event {
                case .viewStateChanged(let newState):
                    updateUI(for: newState)
                case .modelChanged:
                    updateModelSelection()
                }
            }
        }
    }
    
    
    @MainActor
    private func updateUI(for state: ChatViewState) {
        switch state {
        case .empty:
            updateSnapshot(for: .empty)
            inputField.isEnabled = false
            sendButton.isEnabled = false
            inputField.text = ""
            inputField.placeholder = Constants.emptyPlaceholerText
            
        case .chat(let id, let messages, let reconfiguringMessageID, let isStreaming):
            updateSnapshot(for: .chat(id: id, messages: messages, reconfiguringMessageID: reconfiguringMessageID))
            sendButton.isEnabled = !isStreaming
            inputField.isEnabled = !isStreaming
            inputField.placeholder = isStreaming ? Constants.streamingPlacerholderText : Constants.loadedPlaceholderText
            
            
        case .loading:
            updateSnapshot(for: .empty)
            inputField.isEnabled = false
            sendButton.isEnabled = false
            inputField.text = ""
            inputField.placeholder = Constants.emptyPlaceholerText
            
        case .error(let message):
            // With streaming errors now handled inline, this case is for other error types
            updateSnapshot(for: .error(message))
            inputField.isEnabled = true
            sendButton.isEnabled = true
            inputField.placeholder = Constants.loadedPlaceholderText
        }
    }
    
    
    private func updateModelSelection() {
        currentlySelectedModel = chatDataManager.selectedModel
        guard OAPlatform.isMacCatalyst,
              let button = navigationItem.rightBarButtonItem else { return }
        button.menu = makeModelSelectionMenu()
    }
    
    private func updateSnapshot(for state: ChatViewState, animatingDifferences: Bool = true) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        
        switch state {
        case .empty:
            snapshot.appendItems([Constants.emptyPlaceholder])
            
        case .chat(_, let messages, let reconfiguringMessageID, _):
            let messageIDs = messages.map { $0.id }
            snapshot.appendItems(messageIDs)
            
            // If a specific item ID needs reconfiguring, tell the snapshot
            if let itemID = reconfiguringMessageID, messageIDs.contains(itemID) {
                snapshot.reconfigureItems([itemID])
            }
            
        case .loading:
            snapshot.appendItems([Constants.emptyPlaceholder])
            
        case .error:
            snapshot.appendItems([Constants.errorPlaceholder])
        }
        
        let shouldAnimate: Bool
        if case .chat(_, let messages, _, _) = state {
            shouldAnimate = animatingDifferences && messages.count <= 100
        } else {
            shouldAnimate = animatingDifferences
        }
        
        self.dataSource.apply(snapshot, animatingDifferences: shouldAnimate) { [weak self] in
            if case .chat(_, let messages, _, _) = state, !messages.isEmpty {
                self?.scrollToBottomIfNeeded()
            }
        }
    }
    
    private func scrollToBottomIfNeeded() {
        guard case .chat(_, let messages, _, _) = chatDataManager.viewState, !messages.isEmpty else { return }
        
        Task { @MainActor in
            let lastIndexPath = IndexPath(item: messages.count - 1, section: 0)
            if self.tableView.numberOfSections > 0 && 
                self.tableView.numberOfRows(inSection: 0) > lastIndexPath.row {
                self.tableView.scrollToRow(at: lastIndexPath, at: .bottom, animated: true)
            }
        }
    }
    
    func loadChat(with id: String) async {
        await self.chatDataManager.saveProvisionalTextInput(self.inputField.text)
        if let chat = await self.chatDataManager.loadChat(with: id) {
            print("Debug: Successfully loaded chat: \(chat.title)")
            self.inputField.text = chat.provisionaryInputText
        } else {
            print("Debug: Failed to load chat with ID: \(id)")
        }
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
        if !OAPlatform.isMacCatalyst {
            self.presentModelSelectionActionSheet()
        }
    }
    
    @objc private func presentModelSelectionActionSheet() {
        let alert = UIAlertController(title: "Choose Model", message: nil, preferredStyle: .actionSheet)
        for model in OAModel.allCases.sorted(by: { $0.displayName < $1.displayName }) {
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
        return UIMenu(title: "Choose Model", children: OAModel.allCases.sorted(by: { $0.displayName < $1.displayName }).map { model in
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
        
        inputContainerBottomConstraint?.constant = -keyboardHeight + view.safeAreaInsets.bottom
        
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
