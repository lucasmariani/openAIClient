//
//  OAChatViewController.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import UIKit
import Observation
import UniformTypeIdentifiers
import OpenAIForSwift

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
    private let inputTextView = UITextView()
    private let sendButton = UIButton(type: .system)
    private let attachButton = UIButton(type: .system)
    private let attachmentCollectionView = OAAttachmentCollectionView()
    private let inputContainerView = UIView()
    private let textInputContainerView = UIView()
    
    private var pendingAttachments: [OAAttachment] = []
    
    private var inputContainerBottomConstraint: NSLayoutConstraint?
    
    private var dataSource: UITableViewDiffableDataSource<Int, String>!
    
    private let chatDataManager: OAChatDataManager
    private var currentlySelectedModel: Model?
    
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
        self.inputTextView.delegate = self
        self.tableView.allowsSelection = false
        self.attachmentCollectionView.delegate = self
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
        }
//        else {
            modelButton.target = self
            modelButton.action = #selector(didTapModelButton)
//        }
    }
    
    private func setupSubviews() {
        // Input Container
        inputContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputContainerView)
        
        // Attachment Collection View
        attachmentCollectionView.translatesAutoresizingMaskIntoConstraints = false
        attachmentCollectionView.isHidden = true
        inputContainerView.addSubview(attachmentCollectionView)
        
        // Text Input Container
        textInputContainerView.translatesAutoresizingMaskIntoConstraints = false
        textInputContainerView.layer.cornerRadius = 20
        textInputContainerView.layer.borderWidth = 1
        textInputContainerView.layer.borderColor = UIColor.systemGray4.cgColor
        textInputContainerView.backgroundColor = .systemGray6
        inputContainerView.addSubview(textInputContainerView)
        
        // Attach Button
        attachButton.translatesAutoresizingMaskIntoConstraints = false
        let attachConfig = UIImage.SymbolConfiguration(scale: .medium)
        let attachButtonImage = UIImage(systemName: "plus", withConfiguration: attachConfig)
        attachButton.setImage(attachButtonImage, for: .normal)
        attachButton.tintColor = .systemGray
        attachButton.addTarget(self, action: #selector(didTapAttachButton), for: .touchUpInside)
        textInputContainerView.addSubview(attachButton)
        
        // Input TextView
        inputTextView.translatesAutoresizingMaskIntoConstraints = false
        inputTextView.isScrollEnabled = false
        inputTextView.font = .systemFont(ofSize: 16)
        inputTextView.backgroundColor = .clear
        inputTextView.textContainer.lineFragmentPadding = 0
        inputTextView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textInputContainerView.addSubview(inputTextView)
        
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
        textInputContainerView.addSubview(sendButton)
        
        // TableView
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(OAChatMessageCell.self, forCellReuseIdentifier: Constants.cellId)
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .interactive
        view.addSubview(tableView)
        
        inputContainerBottomConstraint = inputContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        inputContainerBottomConstraint?.isActive = true
        
        // Layout Constraints
        NSLayoutConstraint.activate([
            // Input Container View
            inputContainerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            inputContainerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            
            // Attachment Collection View
            attachmentCollectionView.topAnchor.constraint(equalTo: inputContainerView.topAnchor),
            attachmentCollectionView.leadingAnchor.constraint(equalTo: inputContainerView.leadingAnchor),
            attachmentCollectionView.trailingAnchor.constraint(equalTo: inputContainerView.trailingAnchor),
            
            // Text Input Container
            textInputContainerView.topAnchor.constraint(equalTo: attachmentCollectionView.bottomAnchor),
            textInputContainerView.leadingAnchor.constraint(equalTo: inputContainerView.leadingAnchor, constant: 8),
            textInputContainerView.trailingAnchor.constraint(equalTo: inputContainerView.trailingAnchor, constant: -8),
            textInputContainerView.bottomAnchor.constraint(equalTo: inputContainerView.bottomAnchor, constant: -8),
            
            // Attach Button
            attachButton.leadingAnchor.constraint(equalTo: textInputContainerView.leadingAnchor, constant: 8),
            attachButton.bottomAnchor.constraint(lessThanOrEqualTo: textInputContainerView.bottomAnchor, constant: -8),
            attachButton.widthAnchor.constraint(equalToConstant: 32),
            attachButton.heightAnchor.constraint(equalToConstant: 32),
            attachButton.centerYAnchor.constraint(equalTo: textInputContainerView.centerYAnchor),

            // Input TextView
            inputTextView.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 8),
            inputTextView.topAnchor.constraint(equalTo: textInputContainerView.topAnchor),
            inputTextView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            inputTextView.bottomAnchor.constraint(equalTo: textInputContainerView.bottomAnchor),
            inputTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
            
            // Send Button
            sendButton.trailingAnchor.constraint(equalTo: textInputContainerView.trailingAnchor, constant: -8),
            sendButton.bottomAnchor.constraint(equalTo: textInputContainerView.bottomAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 32),
            sendButton.heightAnchor.constraint(equalToConstant: 32),
            sendButton.centerYAnchor.constraint(equalTo: textInputContainerView.centerYAnchor),

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
                cell.configure(with: message)
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
            inputTextView.isEditable = false
            sendButton.isEnabled = false
            attachButton.isEnabled = false
            inputTextView.text = ""
            
        case .chat(let id, let messages, let reconfiguringMessageID, let isStreaming):
            updateSnapshot(for: .chat(id: id, messages: messages, reconfiguringMessageID: reconfiguringMessageID))
            sendButton.isEnabled = !isStreaming && (!inputTextView.text.isEmpty || !pendingAttachments.isEmpty)
            inputTextView.isEditable = !isStreaming
            attachButton.isEnabled = !isStreaming
            
        case .loading:
            updateSnapshot(for: .empty)
            inputTextView.isEditable = false
            sendButton.isEnabled = false
            attachButton.isEnabled = false
            inputTextView.text = ""
            
        case .error(let message):
            updateSnapshot(for: .error(message))
            inputTextView.isEditable = true
            sendButton.isEnabled = !inputTextView.text.isEmpty || !pendingAttachments.isEmpty
            attachButton.isEnabled = true
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
        await self.chatDataManager.saveProvisionalTextInput(self.inputTextView.text)
        if let chat = await self.chatDataManager.loadChat(with: id) {
            print("Debug: Successfully loaded chat: \(chat.title)")
            self.inputTextView.text = chat.provisionaryInputText ?? ""
        } else {
            print("Debug: Failed to load chat with ID: \(id)")
        }
        
        // Clear attachments when switching chats
        pendingAttachments.removeAll()
        updateAttachmentDisplay()
    }
    
    @objc private func didTapSendButton() {
        let text = inputTextView.text ?? ""
        guard !text.isEmpty || !pendingAttachments.isEmpty else {
            return
        }
        
        // Create the new message object with attachments
        let newMessage = OAChatMessage(
            id: UUID().uuidString,
            role: .user,
            content: text,
            date: Date.now,
            attachments: pendingAttachments
        )
        
        // Clear the input
        self.inputTextView.text = ""
        self.pendingAttachments.removeAll()
        self.updateAttachmentDisplay()
        self.chatDataManager.sendMessage(newMessage)
    }
    
    @objc private func didTapAttachButton() {
        presentDocumentPicker()
    }
    
    private func presentDocumentPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            .image,
            .pdf,
            .text,
            .plainText,
            .data
        ])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }
    
    private func updateAttachmentDisplay() {
        attachmentCollectionView.updateAttachments(pendingAttachments)
        
        // Update send button state
        let hasContent = !(inputTextView.text?.isEmpty ?? true) || !pendingAttachments.isEmpty
        if case .chat(_, _, _, let isStreaming) = chatDataManager.viewState {
            sendButton.isEnabled = !isStreaming && hasContent
        }
    }
    
    @objc private func didTapModelButton() {
        if !OAPlatform.isMacCatalyst {
            self.presentModelSelectionActionSheet()
        }
//        else {
//            self.makeModelSelectionMenu()
//        }
    }
    
    @objc private func presentModelSelectionActionSheet() {
        let alert = UIAlertController(title: "Choose Model", message: nil, preferredStyle: .actionSheet)
        for model in Model.allCases.sorted(by: { $0.displayName < $1.displayName }) {
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
        return UIMenu(title: "Choose Model", children: Model.allCases.sorted(by: { $0.displayName < $1.displayName }).map { model in
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

extension OAChatViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateAttachmentDisplay()
    }
}

@MainActor
extension OAChatViewController: OAAttachmentCollectionViewDelegate {
    func attachmentCollectionView(_ collectionView: OAAttachmentCollectionView, didRemoveAttachmentAt index: Int) {
        pendingAttachments.remove(at: index)
        updateAttachmentDisplay()
    }
}

extension OAChatViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        
        Task {
            do {
                let data = try Data(contentsOf: url)
                let filename = url.lastPathComponent
                let mimeType = url.mimeType
                
                let attachment = OAAttachment(
                    id: UUID().uuidString,
                    filename: filename,
                    mimeType: mimeType,
                    data: data,
                    thumbnailData: OAAttachment(id: "", filename: filename, mimeType: mimeType, data: data).generateThumbnail()
                )
                
                await MainActor.run {
                    self.pendingAttachments.append(attachment)
                    self.updateAttachmentDisplay()
                }
            } catch {
                print("Error loading file: \(error)")
            }
        }
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
