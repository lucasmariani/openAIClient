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

class OAChatViewController: UIViewController, CustomChatInputTextViewDelegate {

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
    private let inputTextView = CustomChatInputTextView()
    private let sendButton = UIButton(type: .system)
    private let attachButton = UIButton(type: .system)
    private let attachmentCollectionView = OAAttachmentCollectionView()
    private let inputContainerView = UIView()
    private let textInputContainerView = UIView()
    private let inputStackView = UIStackView()

    // Strong references to navigation bar buttons for reliable state management
    private var modelButton: UIBarButtonItem!
    private var webSearchButton: UIBarButtonItem?

    private var pendingAttachments: [OAAttachment] = []

    private var inputContainerBottomConstraint: NSLayoutConstraint?
    private var textViewHeightConstraint: NSLayoutConstraint?
    private var attachButtonCenterYConstraint: NSLayoutConstraint?
    private var sendButtonCenterYConstraint: NSLayoutConstraint?

    private var dataSource: UITableViewDiffableDataSource<Int, String>!

    private let chatManager: OAChatManager

    private var currentlySelectedModel: Model?

    private var modelMenu: UIMenu?

    private var observationTask: Task<Void, Never>?

    required init(chatManager: OAChatManager) {
        self.chatManager = chatManager
        super.init(nibName: nil, bundle: nil)
        self.currentlySelectedModel = self.chatManager.selectedModel
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        observationTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground
        self.inputTextView.delegate = self
        self.inputTextView.chatInputDelegate = self
        self.tableView.allowsSelection = false
        self.attachmentCollectionView.delegate = self
        self.setupSubviews()
        self.setupDataSource()
        self.setupNavBar()
        self.chatManager.loadLatestChat()

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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    private func updateModelButtonEnableState() {
        // Disable model selection when no chat is loaded
        let hasCurrentChat = chatManager.viewState.currentChatId != nil
        modelButton.isEnabled = hasCurrentChat
    }

    private func updateWebSearchButtonAppearance() {
        self.webSearchButton?.isSelected = self.chatManager.webSearchRequested

        if let webSearchButton {
            if webSearchButton.isSelected {
                webSearchButton.image = UIImage(systemName: "globe.fill")
            } else {
                webSearchButton.image = UIImage(systemName: "globe")
            }
        }
    }

    private func startObservation() {
        observationTask?.cancel()
        observationTask = Task { @MainActor in
            // Use the clean AsyncStream from ChatDataManager
            for await event in chatManager.uiEventStream {
                guard !Task.isCancelled else { break }

                updateModelButtonEnableState()
                switch event {
                case .viewStateChanged(let newState):
                    updateUI(for: newState)
                case .modelChanged(let model):
                    print("📱 Event received: modelChanged(\(model.displayName))")
                    Task { @MainActor in
                        self.currentlySelectedModel = model
                        
                        // Automatically disable web search if new model doesn't support it

                        
                        self.modelButton = UIBarButtonItem(image: UIImage(systemName: "brain.head.profile"), menu: createPersistentMenu())
                        navigationItem.rightBarButtonItems = [self.modelButton]
                        updateWebSearchButtonVisibility()
                    }
                case .showErrorAlert(let errorMessage):
                    showErrorAlert(errorMessage)
                }
            }
        }
    }

    func loadChat(with id: String) async {
        await self.chatManager.saveProvisionalTextInput(self.inputTextView.text)
        if let chat = await self.chatManager.loadChat(with: id) {
            print("Debug: Successfully loaded chat: \(chat.title)")
            self.inputTextView.text = chat.provisionaryInputText ?? ""
        } else {
            print("Debug: Failed to load chat with ID: \(id)")
        }

        // Clear attachments when switching chats
        pendingAttachments.removeAll()
        updateAttachmentDisplay()

    }

    // MARK: UI

    private func createWebSearchButton() -> UIBarButtonItem {
        UIBarButtonItem(
            image: UIImage(systemName: "globe"),
            style: .plain,
            target: self,
            action: #selector(didTapWebSearchButton)
        )
    }

    @MainActor
    private func setupNavBar() {
        self.title = nil
        self.navigationItem.largeTitleDisplayMode = .never

        // Configure model button completely before adding to UI
        self.modelButton = UIBarButtonItem(image: UIImage(systemName: "brain.head.profile"),
                                           menu: createPersistentMenu())
        
        self.webSearchButton = createWebSearchButton()
        
        // Add fully configured buttons to navigation bar
        navigationItem.rightBarButtonItems = [self.modelButton]
        if let webSearchButton {
            navigationItem.rightBarButtonItems?.append(webSearchButton)
        }

        // Update button appearances with current state
        updateWebSearchButtonVisibility()
        updateModelButtonEnableState()
    }

    private func setupSubviews() {
        // Input Container
        inputContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputContainerView)

        // Input Stack View
        inputStackView.translatesAutoresizingMaskIntoConstraints = false
        inputStackView.axis = .vertical
        inputStackView.spacing = 0
        inputStackView.alignment = .fill
        inputStackView.distribution = .fill
        inputContainerView.addSubview(inputStackView)

        // Attachment Collection View
        attachmentCollectionView.translatesAutoresizingMaskIntoConstraints = false
        attachmentCollectionView.isHidden = true

        // Text Input Container
        textInputContainerView.translatesAutoresizingMaskIntoConstraints = false
        textInputContainerView.layer.cornerRadius = 20
        textInputContainerView.layer.borderWidth = 1
        textInputContainerView.layer.borderColor = UIColor.systemGray4.cgColor
        textInputContainerView.backgroundColor = .systemGray6

        // Add both views to stack view
        inputStackView.addArrangedSubview(attachmentCollectionView)
        inputStackView.addArrangedSubview(textInputContainerView)

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
        inputTextView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        inputTextView.showsVerticalScrollIndicator = false
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

            // Input Stack View
            inputStackView.topAnchor.constraint(equalTo: inputContainerView.topAnchor),
            inputStackView.leadingAnchor.constraint(equalTo: inputContainerView.leadingAnchor),
            inputStackView.trailingAnchor.constraint(equalTo: inputContainerView.trailingAnchor),
            inputStackView.bottomAnchor.constraint(equalTo: inputContainerView.bottomAnchor, constant: -8),

            // Text Input Container Margins (within stack view)
            textInputContainerView.leadingAnchor.constraint(equalTo: inputStackView.leadingAnchor),
            textInputContainerView.trailingAnchor.constraint(equalTo: inputStackView.trailingAnchor),

            // Attach Button
            attachButton.leadingAnchor.constraint(equalTo: textInputContainerView.leadingAnchor, constant: 8),
            attachButton.widthAnchor.constraint(equalToConstant: 32),
            attachButton.heightAnchor.constraint(equalToConstant: 32),

            // Input TextView
            inputTextView.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 8),
            inputTextView.topAnchor.constraint(equalTo: textInputContainerView.topAnchor),
            inputTextView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            inputTextView.bottomAnchor.constraint(equalTo: textInputContainerView.bottomAnchor),

            // Send Button
            sendButton.trailingAnchor.constraint(equalTo: textInputContainerView.trailingAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 32),
            sendButton.heightAnchor.constraint(equalToConstant: 32),

            // TableView
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputContainerView.topAnchor)
        ])
        
        // Setup dynamic constraints for text view height and button alignment
        setupDynamicTextViewConstraints()
    }
    
    private func setupDynamicTextViewConstraints() {
        // Set up dynamic height constraint for text view with minimum and maximum
        textViewHeightConstraint = inputTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
        textViewHeightConstraint?.priority = UILayoutPriority(999)
        textViewHeightConstraint?.isActive = true
        
        // Add maximum height constraint to prevent excessive growth
        let maxHeightConstraint = inputTextView.heightAnchor.constraint(lessThanOrEqualToConstant: 120)
        maxHeightConstraint.priority = UILayoutPriority(1000)
        maxHeightConstraint.isActive = true
        
        // Setup initial button alignment
        updateButtonAlignment()
    }
    
    private func updateButtonAlignment() {
        // Remove existing center Y constraints if they exist
        attachButtonCenterYConstraint?.isActive = false
        sendButtonCenterYConstraint?.isActive = false

        // Set up new constraints based on calculated position
        attachButtonCenterYConstraint = attachButton.centerYAnchor.constraint(equalTo: textInputContainerView.centerYAnchor)
        sendButtonCenterYConstraint = sendButton.centerYAnchor.constraint(equalTo: textInputContainerView.centerYAnchor)

        attachButtonCenterYConstraint?.isActive = true
        sendButtonCenterYConstraint?.isActive = true
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

            // Only update text field if transitioning to/from streaming state or if it contains streaming placeholder
            if isStreaming {
                inputTextView.text = "Receiving message..."
                inputTextView.textColor = .systemGray2
            } else if inputTextView.text == "Receiving message..." {
                // Reset text field when streaming ends
                inputTextView.text = ""
                inputTextView.textColor = .label
                // Update send button state after resetting text field
                sendButton.isEnabled = !inputTextView.text.isEmpty || !pendingAttachments.isEmpty
            }

        case .loading:
            updateSnapshot(for: .empty)
            inputTextView.isEditable = false
            sendButton.isEnabled = false
            attachButton.isEnabled = false
            inputTextView.text = ""

        case .error(let message):
            updateSnapshot(for: .error(message))
            inputTextView.isEditable = true
            inputTextView.text = ""
            inputTextView.textColor = .label
            sendButton.isEnabled = !inputTextView.text.isEmpty || !pendingAttachments.isEmpty
            attachButton.isEnabled = true
        }
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
            attachments: pendingAttachments,
            imageData: nil
        )

        // Clear the input
        self.inputTextView.text = ""
        self.pendingAttachments.removeAll()
        self.updateAttachmentDisplay()
        self.chatManager.sendMessage(newMessage)
    }

    @objc private func didTapWebSearchButton() {
        // Only allow toggle if current model supports web search
        guard currentlySelectedModel?.capabilities.supportsWebSearch == true else { return }
        
        chatManager.toggleWebSearchRequested()
        self.updateWebSearchButtonAppearance()
    }

    private func updateWebSearchButtonVisibility() {
        // Check if current model supports web search
        let supportsWebSearch = currentlySelectedModel?.capabilities.supportsWebSearch ?? false

        if supportsWebSearch {
            self.webSearchButton = self.createWebSearchButton()
            if let webSearchButton {
                self.navigationItem.rightBarButtonItems?.append(webSearchButton)
                self.webSearchButton?.tintColor = chatManager.webSearchRequested ? .systemBlue : .label
                self.webSearchButton?.isEnabled = supportsWebSearch
            }
        } else {
            chatManager.setWebSearchRequested(false)
            if let navButtons = self.navigationItem.rightBarButtonItems, navButtons.count > 1 {
                self.navigationItem.rightBarButtonItems?.remove(at: 1)
                self.webSearchButton = nil
            }
        }
    }

    @MainActor
    private func createPersistentMenu() -> UIMenu {
        let actions = Model.allCases.sorted(by: { $0.displayName < $1.displayName }).map { model in
            return UIAction(
                title: model.displayName,
                state: (model == self.currentlySelectedModel) ? .on : .off
            ) { [weak self] action in
                guard let self else { return }
                Task {
                    await self.chatManager.updateModel(model)
                }
            }
        }
        return UIMenu(
            title: "Choose Model",
            image: UIImage(systemName: "brain.head.profile"),
            children: actions
        )
    }

    private func showErrorAlert(_ errorMessage: String) {
        let alert = UIAlertController(
            title: "Error",
            message: errorMessage,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "OK", style: .default))

        present(alert, animated: true)
    }
}

// MARK: Table View

extension OAChatViewController {

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

            if case .chat(_, let messages, _, _) = self.chatManager.viewState,
               let message = messages.first(where: { $0.id == messageID }) {
                cell.configure(with: message)
            } else {
                cell.configure(with: "Message not found", role: .system)
            }
            return cell
        }
        self.tableView.dataSource = self.dataSource
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
        guard case .chat(_, let messages, _, _) = chatManager.viewState, !messages.isEmpty else { return }
        
        Task { @MainActor in
            let lastIndexPath = IndexPath(item: messages.count - 1, section: 0)
            if self.tableView.numberOfSections > 0 &&
                self.tableView.numberOfRows(inSection: 0) > lastIndexPath.row {
                self.tableView.scrollToRow(at: lastIndexPath, at: .bottom, animated: true)
            }
        }
    }
}

// MARK: ATTACHMENTS

extension OAChatViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateAttachmentDisplay()
        updateButtonAlignment()
        
        // Force layout update if needed
        UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut) {
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: - CustomChatInputTextViewDelegate
    
    func customChatInputTextViewDidRequestSend(_ textView: CustomChatInputTextView) {
        didTapSendButton()
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
        if case .chat(_, _, _, let isStreaming) = chatManager.viewState {
            sendButton.isEnabled = !isStreaming && hasContent
        }
    }
}

// MARK: KEYBOARD

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
