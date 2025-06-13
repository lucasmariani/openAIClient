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
//    func streamMessage(content: String, chatId: String, model: OAModel) -> AsyncStream<OAChatMessage>
    func streamMessageEvents(content: String, chatId: String, model: OAModel) -> AsyncStream<ChatEvent>

    // Configuration
    func updateChatModel(_ chatId: String, model: OAModel) async throws
    func updateProvisionaryText(_ chatId: String, text: String?) async throws
    func updateChatTitle(_ chatId: String, title: String) async throws

    // Title generation
    func generateChatTitle(userMessage: String, assistantMessage: String) async throws -> String
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


    // MARK: - Streaming (Legacy - maintained for backward compatibility)

//    func streamMessage(content: String, chatId: String, model: OAModel) -> AsyncStream<OAChatMessage> {
//        return AsyncStream { continuation in
//            let task = Task {
//                for await event in streamMessageEvents(content: content, chatId: chatId, model: model) {
//                    switch event {
//                    case .messageStarted(_, let message), .messageUpdated(_, let message), .messageCompleted(_, let message):
//                        continuation.yield(message)
//                    case .streamingError:
//                        break // Error handling happens in the event system
//                    case .chatDeleted, .chatsUpdated:
//                        break // Not relevant for streaming
//                    }
//                }
//                continuation.finish()
//            }
//            
//            continuation.onTermination = { _ in
//                task.cancel()
//            }
//        }
//    }

    // MARK: - New AsyncSequence-based Streaming

    func streamMessageEvents(content: String, chatId: String, model: OAModel) -> AsyncStream<ChatEvent> {
        return AsyncStream { continuation in
            let task = Task {
                // Start streaming with the provider
                streamProvider.sendMessage(content)

                // Create assistant message placeholder
                let assistantMessage = OAChatMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    content: "",
                    date: Date()
                )

                // Emit started event and publish to event system
                let startedEvent = ChatEvent.messageStarted(chatId: chatId, message: assistantMessage)
                eventSubject.send(startedEvent)
                continuation.yield(startedEvent)

                // Save initial message
                do {
                    try await coreDataManager.addMessage(assistantMessage, toChatID: chatId, isStreaming: true)
                } catch {
                    let errorEvent = ChatEvent.streamingError(chatId: chatId, error: error)
                    eventSubject.send(errorEvent)
                    continuation.yield(errorEvent)
                    continuation.finish()
                    return
                }

                // Set up callbacks for stream events
                streamProvider.onMessageUpdate = { [weak self] responseMessage in
                    Task { @MainActor in
                        guard let self = self else { return }
                        
                        let updatedMessage = OAChatMessage(
                            id: assistantMessage.id,
                            role: .assistant,
                            content: responseMessage.content,
                            date: responseMessage.timestamp
                        )

                        // Update in Core Data
                        do {
                            try await self.coreDataManager.updateMessage(
                                with: assistantMessage.id,
                                chatId: chatId,
                                content: responseMessage.content,
                                date: responseMessage.timestamp,
                                isStreaming: true
                            )
                            
                            let updatedEvent = ChatEvent.messageUpdated(chatId: chatId, message: updatedMessage)
                            self.eventSubject.send(updatedEvent)
                            continuation.yield(updatedEvent)
                        } catch {
                            let errorEvent = ChatEvent.streamingError(chatId: chatId, error: error)
                            self.eventSubject.send(errorEvent)
                            continuation.yield(errorEvent)
                        }
                    }
                }

                streamProvider.onStreamCompleted = { [weak self] responseMessage in
                    Task { @MainActor in
                        guard let self = self else { return }
                        
                        let completedMessage = OAChatMessage(
                            id: assistantMessage.id,
                            role: .assistant,
                            content: responseMessage.content,
                            date: responseMessage.timestamp
                        )

                        // Final update in Core Data
                        do {
                            try await self.coreDataManager.updateMessage(
                                with: assistantMessage.id,
                                chatId: chatId,
                                content: responseMessage.content,
                                date: responseMessage.timestamp,
                                isStreaming: false
                            )
                            
                            let completedEvent = ChatEvent.messageCompleted(chatId: chatId, message: completedMessage)
                            self.eventSubject.send(completedEvent)
                            continuation.yield(completedEvent)
                            continuation.finish()
                        } catch {
                            let errorEvent = ChatEvent.streamingError(chatId: chatId, error: error)
                            self.eventSubject.send(errorEvent)
                            continuation.yield(errorEvent)
                            continuation.finish()
                        }
                    }
                }

                streamProvider.onStreamError = { [weak self] error in
                    Task { @MainActor in
                        let errorEvent = ChatEvent.streamingError(chatId: chatId, error: error)
                        self?.eventSubject.send(errorEvent)
                        continuation.yield(errorEvent)
                        continuation.finish()
                    }
                }

                // Wait for streaming to complete naturally
                // The callbacks will handle completion and finish the continuation
            }

            continuation.onTermination = { [weak self] _ in
                task.cancel()
                // Clean up callbacks to prevent memory leaks
                Task { @MainActor [weak self] in
                    self?.streamProvider.onMessageUpdate = nil
                    self?.streamProvider.onStreamCompleted = nil
                    self?.streamProvider.onStreamError = nil
                }
            }
        }
    }

//    private func handleStreamUpdate(
//        assistantMessage: OAChatMessage,
//        chatId: String,
//        lastContent: inout String,
//        continuation: AsyncStream<OAChatMessage>.Continuation
//    ) async {
//        guard let responseMessage = streamProvider.messages.last,
//              responseMessage.role == .assistant else { return }
//
//        let currentContent = responseMessage.content
//
//        // Only process if content has changed
//        guard currentContent != lastContent else { return }
//        lastContent = currentContent
//
//        // Create updated message
//        let updatedMessage = OAChatMessage(
//            id: assistantMessage.id,
//            role: .assistant,
//            content: currentContent,
//            date: responseMessage.timestamp
//        )
//
//        // Save update to Core Data
//        do {
//            try await coreDataManager.updateMessage(
//                with: assistantMessage.id,
//                chatId: chatId,
//                content: currentContent,
//                date: responseMessage.timestamp,
//                isStreaming: responseMessage.isStreaming
//            )
//
//            if responseMessage.isStreaming {
//                eventSubject.send(.messageUpdated(chatId: chatId, message: updatedMessage))
//            } else {
//                eventSubject.send(.messageCompleted(chatId: chatId, message: updatedMessage))
//            }
//
//            continuation.yield(updatedMessage)
//
//        } catch {
//            eventSubject.send(.streamingError(chatId: chatId, error: error))
//        }
//    }

    // MARK: - Configuration

    func updateChatModel(_ chatId: String, model: OAModel) async throws {
        try await coreDataManager.updateSelectedModelFor(chatId, model: model)
    }

    func updateProvisionaryText(_ chatId: String, text: String?) async throws {
        try await coreDataManager.updateProvisionaryInputText(for: chatId, text: text)
    }

    func updateChatTitle(_ chatId: String, title: String) async throws {
        try await coreDataManager.updateChatTitle(chatId, title: title)
    }

    func generateChatTitle(userMessage: String, assistantMessage: String) async throws -> String {
        return try await streamProvider.generateTitle(userMessage: userMessage, assistantMessage: assistantMessage)
    }
}
