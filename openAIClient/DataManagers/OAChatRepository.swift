//
//  OAChatRepository.swift
//  openAIClient
//
//  Created by Lucas on 6.12.25.
//

import Foundation
import Combine

// MARK: - Chat Events

enum ChatEvent {
    case messageStarted(chatId: String, message: OAChatMessage)
    case messageUpdated(chatId: String, message: OAChatMessage)
    case messageCompleted(chatId: String, message: OAChatMessage)
    case streamingError(chatId: String, error: Error)
    case chatDeleted(chatId: String)
    case chatsUpdated([OAChat])
}

// MARK: - Repository Protocol

@MainActor
protocol ChatRepository {
    // Publishers for reactive updates
    var chatsPublisher: AnyPublisher<[OAChat], Never> { get }
    var eventPublisher: AnyPublisher<ChatEvent, Never> { get }
    
    // Chat management
    func createNewChat() async throws -> OAChat
    func deleteChat(with id: String) async throws
    func getChats() async throws -> [OAChat]
    func getChat(with id: String) async throws -> OAChat?
    
    // Message management
    func getMessages(for chatId: String) async throws -> [OAChatMessage]
    func saveMessage(_ message: OAChatMessage, toChatId chatId: String) async throws
    
    // Streaming
    func streamMessage(content: String, chatId: String, model: OAModel) -> AsyncStream<OAChatMessage>
    
    // Configuration
    func updateChatModel(_ chatId: String, model: OAModel) async throws
    func updateProvisionaryText(_ chatId: String, text: String?) async throws
}

// MARK: - Repository Implementation

@MainActor
final class OAChatRepositoryImpl: ChatRepository {
    
    // MARK: - Dependencies
    
    private let coreDataManager: OACoreDataManager
    private let streamProvider: OAResponseStreamProvider
    
    // MARK: - Publishers
    
    private let eventSubject = PassthroughSubject<ChatEvent, Never>()
    var eventPublisher: AnyPublisher<ChatEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }
    
    var chatsPublisher: AnyPublisher<[OAChat], Never> {
        coreDataManager.$chats.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    init(coreDataManager: OACoreDataManager, streamProvider: OAResponseStreamProvider) {
        self.coreDataManager = coreDataManager
        self.streamProvider = streamProvider
        
        // Forward chats updates as events
        coreDataManager.$chats
            .sink { [weak self] chats in
                self?.eventSubject.send(.chatsUpdated(chats))
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Chat Management
    
    func createNewChat() async throws -> OAChat {
        try await coreDataManager.newChat()
        guard let newChat = coreDataManager.chats.first else {
            throw OACoreDataError.chatNotFound
        }
        return newChat
    }
    
    func deleteChat(with id: String) async throws {
        try await coreDataManager.deleteChat(with: id)
        eventSubject.send(.chatDeleted(chatId: id))
    }
    
    func getChats() async throws -> [OAChat] {
        try await coreDataManager.fetchPersistedChats()
        return coreDataManager.chats
    }
    
    func getChat(with id: String) async throws -> OAChat? {
        return coreDataManager.chats.first(where: { $0.id == id })
    }
    
    // MARK: - Message Management
    
    func getMessages(for chatId: String) async throws -> [OAChatMessage] {
        return try await coreDataManager.fetchMessages(for: chatId)
    }
    
    func saveMessage(_ message: OAChatMessage, toChatId chatId: String) async throws {
        try await coreDataManager.addMessage(message, toChatID: chatId)
    }
    
    
    // MARK: - Streaming
    
    func streamMessage(content: String, chatId: String, model: OAModel) -> AsyncStream<OAChatMessage> {
        return AsyncStream { continuation in
            let task = Task {
                // Start streaming with the provider
                await streamProvider.sendMessage(content)
                
                // Create assistant message placeholder
                let assistantMessage = OAChatMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    content: "",
                    date: Date()
                )
                
                // Notify that streaming started
                eventSubject.send(.messageStarted(chatId: chatId, message: assistantMessage))
                continuation.yield(assistantMessage)
                
                // Save initial message
                do {
                    try await coreDataManager.addMessage(assistantMessage, toChatID: chatId, isStreaming: true)
                } catch {
                    eventSubject.send(.streamingError(chatId: chatId, error: error))
                    continuation.finish()
                    return
                }
                
                // Monitor stream provider for updates
                var lastContent = ""
                
                // Create observation task
                let observationTask = Task {
                    while !Task.isCancelled {
                        withObservationTracking {
                            _ = streamProvider.messages
                        } onChange: {
                            Task { @MainActor in
                                await self.handleStreamUpdate(
                                    assistantMessage: assistantMessage,
                                    chatId: chatId,
                                    lastContent: &lastContent,
                                    continuation: continuation
                                )
                            }
                        }
                        
                        if Task.isCancelled { break }
                        
                        do {
                            try await Task.sleep(for: .milliseconds(50))
                        } catch {
                            break
                        }
                    }
                }
                
                // Wait for streaming to complete
                while streamProvider.isStreaming && !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                
                observationTask.cancel()
                continuation.finish()
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    private func handleStreamUpdate(
        assistantMessage: OAChatMessage,
        chatId: String,
        lastContent: inout String,
        continuation: AsyncStream<OAChatMessage>.Continuation
    ) async {
        guard let responseMessage = streamProvider.messages.last,
              responseMessage.role == .assistant else { return }
        
        let currentContent = responseMessage.content
        
        // Only process if content has changed
        guard currentContent != lastContent else { return }
        lastContent = currentContent
        
        // Create updated message
        let updatedMessage = OAChatMessage(
            id: assistantMessage.id,
            role: .assistant,
            content: currentContent,
            date: responseMessage.timestamp
        )
        
        // Save update to Core Data
        do {
            try await coreDataManager.updateMessage(
                with: assistantMessage.id,
                chatId: chatId,
                content: currentContent,
                date: responseMessage.timestamp,
                isStreaming: responseMessage.isStreaming
            )
            
            if responseMessage.isStreaming {
                eventSubject.send(.messageUpdated(chatId: chatId, message: updatedMessage))
            } else {
                eventSubject.send(.messageCompleted(chatId: chatId, message: updatedMessage))
            }
            
            continuation.yield(updatedMessage)
            
        } catch {
            eventSubject.send(.streamingError(chatId: chatId, error: error))
        }
    }
    
    // MARK: - Configuration
    
    func updateChatModel(_ chatId: String, model: OAModel) async throws {
        try await coreDataManager.updateSelectedModelFor(chatId, model: model)
    }
    
    func updateProvisionaryText(_ chatId: String, text: String?) async throws {
        try await coreDataManager.updateProvisionaryInputText(for: chatId, text: text)
    }
}
