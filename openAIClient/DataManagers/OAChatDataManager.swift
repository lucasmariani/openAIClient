//
// OAChatDataManager.swift
// openAIClient
//
// Created by Lucas on 29.05.25.
//

import Foundation
@preconcurrency import Combine

enum ChatViewState {
    case empty
    case chat(id: String, messages: [OAChatMessage], reconfiguringMessageID: String? = nil)
    case loading(chatId: String)
    case error(String)
}

@MainActor
final class OAChatDataManager {
    
    // MARK: - Properties
    
    private let repository: ChatRepository
    private var currentChatId: String? = nil
    var messages: [OAChatMessage] = []
    
    @Published var selectedModel: OAModel = .gpt41nano
    @Published var viewState: ChatViewState = .empty
    
    private var cancellables = Set<AnyCancellable>()
    private var streamingTask: Task<Void, Never>?

    // MARK: - Initialization
    
    init(repository: ChatRepository) {
        self.repository = repository
        setupEventHandling()
    }
    
    deinit {
        streamingTask?.cancel()
        cancellables.removeAll()
    }

    // MARK: - Private Methods
    
    private func setupEventHandling() {
        repository.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleRepositoryEvent(event)
            }
            .store(in: &cancellables)
    }
    
    private func handleRepositoryEvent(_ event: ChatEvent) {
        switch event {
        case .messageStarted(let chatId, let message):
            if chatId == currentChatId {
                messages.append(message)
                updateViewState()
            }
            
        case .messageUpdated(let chatId, let message):
            if chatId == currentChatId {
                updateMessageInLocalArray(message)
                updateViewState(reconfiguringMessageID: message.id)
            }
            
        case .messageCompleted(let chatId, let message):
            if chatId == currentChatId {
                updateMessageInLocalArray(message)
                updateViewState(reconfiguringMessageID: message.id)
            }
            
        case .streamingError(let chatId, let error):
            if chatId == currentChatId {
                print("Streaming error in chat \(chatId): \(error)")
            }
            
        case .chatDeleted(let chatId):
            if chatId == currentChatId {
                clearCurrentChat()
            }
            
        case .chatsUpdated:
            // This is handled by the sidebar directly through the repository
            break
        }
    }
    
    private func updateMessageInLocalArray(_ message: OAChatMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        }
    }
    
    private func clearCurrentChat() {
        currentChatId = nil
        messages = []
        viewState = .empty
    }
    
    private func updateViewState(reconfiguringMessageID: String? = nil) {
        if let chatId = currentChatId {
            viewState = .chat(id: chatId, messages: messages, reconfiguringMessageID: reconfiguringMessageID)
        } else {
            viewState = .empty
        }
    }

    // MARK: - Public Methods

    func loadLatestChat() {
        Task {
            do {
                let chats = try await repository.getChats()
                if let latestChat = chats.first {
                    await loadChat(with: latestChat.id)
                }
            } catch {
                print("Failed to load latest chat: \(error)")
            }
        }
    }

    func updateModel(_ model: OAModel) async {
        guard let chatId = currentChatId else { return }
        do {
            try await repository.updateChatModel(chatId, model: model)
            selectedModel = model
        } catch {
            print("Failed to update model: \(error)")
        }
    }

    func saveProvisionaryTextInput(_ inputText: String?) async {
        guard let chatId = currentChatId else { return }
        do {
            try await repository.updateProvisionaryText(chatId, text: inputText)
        } catch {
            print("Failed to save provisionary text: \(error)")
        }
    }

    @discardableResult
    func loadChat(with id: String) async -> OAChat? {
        do {
            guard let chat = try await repository.getChat(with: id) else {
                clearCurrentChat()
                return nil
            }
            
            currentChatId = id
            messages = try await repository.getMessages(for: id)
            selectedModel = chat.selectedModel
            
            updateViewState()
            return chat
            
        } catch {
            print("Failed to load chat \(id): \(error)")
            clearCurrentChat()
            return nil
        }
    }


    func sendMessage(_ chatMessage: OAChatMessage) {
        guard let currentChatId else { return }

        // Optimistically add user message to UI
        messages.append(chatMessage)
        updateViewState()

        Task {
            do {
                // Save user message
                try await repository.saveMessage(chatMessage, toChatId: currentChatId)
                
                // Start streaming assistant response
                streamingTask?.cancel()
                streamingTask = Task {
                    for await _ in repository.streamMessage(
                        content: chatMessage.content,
                        chatId: currentChatId,
                        model: selectedModel
                    ) {
                        // Updates are handled through the event system
                        // No need to manually update here
                    }
                }
                
            } catch {
                print("Failed to send message: \(error)")
            }
        }
    }

    func setCurrentChat(_ chatId: String?) {
        streamingTask?.cancel()
        currentChatId = chatId
        
        if chatId == nil {
            clearCurrentChat()
        }
    }
}
