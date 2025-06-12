//
// OAChatDataManager.swift
// openAIClient
//
// Created by Lucas on 29.05.25.
//

import Foundation
@preconcurrency import Combine
import SwiftUI
import UIKit

@MainActor
final class OAChatDataManager {
    
    // MARK: - Properties
    
    private let repository: ChatRepository
    private var currentChatId: String? = nil
    var messages: [OAChatMessage] = []
    var onMessagesUpdated: ((_ reconfigureItemID: String?) -> Void)?
    
    @Published var selectedModel: OAModel = .gpt41nano
    
    private var cancellables = Set<AnyCancellable>()
    private var streamingTask: Task<Void, Never>?

    // MARK: - Initialization

    init(repository: ChatRepository) {
        self.repository = repository
        setupEventHandling()
    }
    
    convenience init(coreDataManager: OACoreDataManager) {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "API_KEY") as? String else {
            fatalError("Error retrieving API_KEY")
        }
        
        let configuration = URLSessionConfiguration.default
        let service = OAOpenAIServiceFactory.service(apiKey: apiKey, configuration: configuration)
        let streamProvider = OAResponseStreamProvider(service: service, model: .gpt41nano)
        let repository = OAChatRepositoryImpl(coreDataManager: coreDataManager, streamProvider: streamProvider)
        
        self.init(repository: repository)
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
                onMessagesUpdated?(nil)
            }
            
        case .messageUpdated(let chatId, let message):
            if chatId == currentChatId {
                updateMessageInLocalArray(message)
                onMessagesUpdated?(message.id)
            }
            
        case .messageCompleted(let chatId, let message):
            if chatId == currentChatId {
                updateMessageInLocalArray(message)
                onMessagesUpdated?(message.id)
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
        onMessagesUpdated?(nil)
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
            
            onMessagesUpdated?(nil)
            return chat
            
        } catch {
            print("Failed to load chat \(id): \(error)")
            clearCurrentChat()
            return nil
        }
    }

    func getChatTitle(for chatId: String) -> String? {
        Task {
            do {
                let chat = try await repository.getChat(with: chatId)
                return chat?.title
            } catch {
                return nil
            }
        }
        return nil // Temporary - this should be async
    }

    func sendMessage(_ chatMessage: OAChatMessage) {
        guard let currentChatId else { return }

        // Optimistically add user message to UI
        messages.append(chatMessage)
        onMessagesUpdated?(nil)

        Task {
            do {
                // Save user message
                try await repository.saveMessage(chatMessage, toChatId: currentChatId)
                
                // Start streaming assistant response
                streamingTask?.cancel()
                streamingTask = Task {
                    for await assistantMessage in repository.streamMessage(
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
