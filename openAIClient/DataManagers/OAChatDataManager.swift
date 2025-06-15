//
// OAChatDataManager.swift
// openAIClient
//
// Created by Lucas on 29.05.25.
//

import Foundation
import Observation

enum ChatViewState {
    case empty
    case chat(id: String, messages: [OAChatMessage], reconfiguringMessageID: String? = nil, isStreaming: Bool = false)
    case loading
    case error(String)
}

@MainActor
@Observable
final class OAChatDataManager {
    
    // MARK: - Properties
    
    private let repository: ChatRepository
    private var currentChatId: String? = nil
    
    // UI State - All UI components should bind to these properties
    var chats: [OAChat] = []           // For sidebar
    var messages: [OAChatMessage] = [] // For chat view
    var selectedModel: OAModel = .gpt41nano
    var viewState: ChatViewState = .loading

    private var eventTask: Task<Void, Never>?
    private var streamingTask: Task<Void, Never>?

    // MARK: - Initialization
    
    init(repository: ChatRepository) {
        self.repository = repository
        setupEventHandling()
        loadInitialChats()
    }
    
    private func loadInitialChats() {
        Task {
            do {
                chats = try await repository.getChats()
                if chats.isEmpty {
                    viewState = .empty
                }
            } catch {
                print("Failed to load initial chats: \(error)")
            }
        }
    }

    // MARK: - Private Methods
    
    private func setupEventHandling() {
        eventTask = Task { @MainActor in
            for await event in repository.eventStream {
                guard !Task.isCancelled else { break }
                handleRepositoryEvent(event)
            }
        }
    }
    
    private func handleRepositoryEvent(_ event: ChatEvent) {
        switch event {
        case .messageStarted(let chatId, let message):
            print("📩 DataManager: messageStarted for chat \(chatId), message \(message.id)")
            if chatId == currentChatId {
                messages.append(message)
                viewState = .chat(id: chatId, messages: messages, reconfiguringMessageID: message.id, isStreaming: true)
                print("📊 DataManager: Updated viewState to streaming with \(messages.count) messages")
            } else {
                print("📩 DataManager: Ignoring messageStarted for different chat (current: \(currentChatId ?? "none"))")
            }
            
        case .messageUpdated(let chatId, let message):
            print("📝 DataManager: messageUpdated for chat \(chatId), message \(message.id), content length: \(message.content.count)")
            if chatId == currentChatId {
                updateMessageInLocalArray(message)
                viewState = .chat(id: chatId, messages: messages, reconfiguringMessageID: message.id, isStreaming: true)
                print("📊 DataManager: Updated viewState to streaming with \(messages.count) messages")
            } else {
                print("📝 DataManager: Ignoring messageUpdated for different chat (current: \(currentChatId ?? "none"))")
            }
            
        case .messageCompleted(let chatId, let message):
            print("✅ DataManager: messageCompleted for chat \(chatId), message \(message.id)")
            if chatId == currentChatId {
                updateMessageInLocalArray(message)
                viewState = .chat(id: chatId, messages: messages, reconfiguringMessageID: message.id, isStreaming: false)
                print("📊 DataManager: Updated viewState to non-streaming with \(messages.count) messages")
                
                // Generate title after first assistant response
                if message.role == .assistant && shouldGenerateTitle() {
                    Task {
                        await generateChatTitle(for: chatId)
                    }
                }
            } else {
                print("✅ DataManager: Ignoring messageCompleted for different chat (current: \(currentChatId ?? "none"))")
            }
            
        case .streamingError(let chatId, let error):
            if chatId == currentChatId {
                let errorString = "Streaming error in chat \(chatId): \(error)"
                print(errorString)
                viewState = .error(errorString)
            }
            
        case .chatDeleted(let chatId):
            if chatId == currentChatId {
                clearCurrentChat()
            }
            
        case .chatsUpdated(let updatedChats):
            chats = updatedChats
            
            // Check if currently selected chat was deleted during sync (e.g., CloudKit remote changes)
            if let currentChatId = currentChatId {
                let stillExists = updatedChats.contains { $0.id == currentChatId }
                if !stillExists {
                    print("📋 DataManager: Currently selected chat \(currentChatId) was deleted during sync, clearing current chat")
                    clearCurrentChat()
                }
            }

        case .chatCreated:
            break
        
        }
    }
    
    private func updateMessageInLocalArray(_ message: OAChatMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            let oldContent = messages[index].content
            messages[index] = message
            print("🔄 DataManager: Updated message at index \(index), content changed: \(oldContent.count) → \(message.content.count) chars")
        } else {
            print("⚠️ DataManager: Could not find message with ID \(message.id) in local array of \(messages.count) messages")
            print("⚠️ DataManager: Available message IDs: \(messages.map { $0.id })")
        }
    }
    
    private func clearCurrentChat() {
        currentChatId = nil
        messages = []
        viewState = .empty
    }
    
    private func shouldGenerateTitle() -> Bool {
        // Generate title only if we have exactly 2 messages (1 user + 1 assistant)
        return messages.count == 2 && 
               messages.first?.role == .user && 
               messages.last?.role == .assistant
    }
    
    private func generateChatTitle(for chatId: String) async {
        guard let userMessage = messages.first?.content,
              let assistantMessage = messages.last?.content else { return }
        
        do {
            try await repository.generateChatTitle(userMessage: userMessage,
                                                   assistantMessage: assistantMessage,
                                                   chatId: chatId)
        } catch {
            print("Failed to generate chat title: \(error)")
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

    func saveProvisionalTextInput(_ inputText: String?) async {
        guard let chatId = currentChatId else { return }
        do {
            try await repository.updateProvisionalText(chatId, text: inputText)
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
            
            if let chatId = currentChatId {
                viewState = .chat(id: chatId, messages: messages, reconfiguringMessageID: nil, isStreaming: false)
            } else {
                viewState = .empty
            }
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
        viewState = .chat(id: currentChatId, messages: messages, reconfiguringMessageID: chatMessage.id, isStreaming: true)

        Task {
            do {
                // Save user message
                try await repository.saveMessage(chatMessage, toChatId: currentChatId)
                
                // Start streaming assistant response
                streamingTask?.cancel()
                streamingTask = Task {
                    for await _ in repository.streamMessageEvents(
                        content: chatMessage.content,
                        chatId: currentChatId,
                        model: selectedModel
                    ) {
                        // Events are handled through the event system via handleRepositoryEvent()
                        // This loop just keeps the task alive until streaming completes
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
    
    // MARK: - Chat Management Methods for UI
    
    func createNewChat() async throws {
        try await repository.createNewChat()
    }
    
    func deleteChat(with id: String) async throws {
        try await repository.deleteChat(with: id)
    }
    
    func deleteChats(with ids: [String]) async throws {
        try await repository.deleteChats(with: ids)
    }
}
