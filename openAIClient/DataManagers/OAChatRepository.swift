//
//  OAChatRepository.swift
//  openAIClient
//
//  Created by Lucas on 6.12.25.
//

import Foundation
import Observation

// MARK: - Chat Events

enum ChatEvent {
    case messageStarted(chatId: String, message: OAChatMessage)
    case messageUpdated(chatId: String, message: OAChatMessage)
    case messageCompleted(chatId: String, message: OAChatMessage)
    case streamingError(chatId: String, error: Error)
    case chatDeleted(chatId: String)
    case chatsUpdated([OAChat])
    case chatCreated
}


// MARK: - Repository Protocol

@MainActor
protocol ChatRepository {
    // @Observable data manager for modern observation patterns
    var coreDataManager: OACoreDataManager { get }
    
    // Event stream for real-time events
    var eventStream: AsyncStream<ChatEvent> { get }

    // Chat management
    func createNewChat() async throws
    func deleteChat(with id: String) async throws
    func deleteChats(with ids: [String]) async throws
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
    func updateProvisionalText(_ chatId: String, text: String?) async throws

    // Title generation
    func generateChatTitle(userMessage: String, assistantMessage: String, chatId: String) async throws
}

// MARK: - Repository Implementation

@MainActor
final class OAChatRepositoryImpl: ChatRepository {

    // MARK: - Dependencies

    let coreDataManager: OACoreDataManager
    private let streamProvider: OAResponseStreamProvider

    // MARK: - Event Streaming

    private let eventContinuation: AsyncStream<ChatEvent>.Continuation
    let eventStream: AsyncStream<ChatEvent>


    // MARK: - Initialization

    init(coreDataManager: OACoreDataManager, streamProvider: OAResponseStreamProvider) {
        self.coreDataManager = coreDataManager
        self.streamProvider = streamProvider
        
        let (stream, continuation) = AsyncStream<ChatEvent>.makeStream()
        self.eventStream = stream
        self.eventContinuation = continuation
        
        // Set self as delegate to receive chat update notifications
        coreDataManager.delegate = self
    }

    // MARK: - Enhanced AsyncSequence-based Streaming

    func streamMessageEvents(content: String, chatId: String, model: OAModel) -> AsyncStream<ChatEvent> {
        return AsyncStream { continuation in
            let task = Task { @MainActor in
                // Use the enhanced streaming API from the provider
                let streamEvents = streamProvider.streamEvents(for: content)

                for await event in streamEvents {
                    guard !Task.isCancelled else { break }

                    switch event {
                    case .messageStarted(let responseMessage):
                        // Convert to our chat message format
                        let assistantMessage = OAChatMessage(
                            id: responseMessage.responseId,
                            role: .assistant,
                            content: responseMessage.content,
                            date: responseMessage.timestamp
                        )

                        print("🟡 Starting message with ID: \(responseMessage.responseId) for chat: \(chatId)")

                        // Save initial message to Core Data
                        do {
                            try await coreDataManager.saveMessage(assistantMessage, toChatID: chatId, isStreaming: true)
                        } catch {
                            print("❌ Failed to save initial message to Core Data: \(error)")
                        }
                        let startedEvent = ChatEvent.messageStarted(chatId: chatId, message: assistantMessage)
                        eventContinuation.yield(startedEvent)

                    case .messageUpdated(let responseMessage):
                        print("🟡 Updating message with ID: \(responseMessage.responseId) for chat: \(chatId)")

                        // Update in Core Data
                        do {
                            try await coreDataManager.updateMessage(with: responseMessage,
                                                                    chatId: chatId,
                                                                    isStreaming: true)
                        } catch {
                            // Core Data update failed - log but continue streaming
                            print("⚠️ Failed to update message \(responseMessage.responseId) in Core Data: \(error)")
                        }

                        let updatedMessage = OAChatMessage(
                            id: responseMessage.responseId,
                            role: .assistant,
                            content: responseMessage.content,
                            date: responseMessage.timestamp
                        )
                        // Always emit the UI update event, regardless of Core Data success
                        let updatedEvent = ChatEvent.messageUpdated(chatId: chatId, message: updatedMessage)
                        eventContinuation.yield(updatedEvent)

                    case .messageCompleted(let responseMessage):
                        print("🟢 Completing message with ID: \(responseMessage.responseId) for chat: \(chatId)")

                        // Final update in Core Data
                        do {
                            try await coreDataManager.updateMessage(with: responseMessage,
                                                                    chatId: chatId,
                                                                    isStreaming: false)
                        } catch {
                            // Core Data update failed - log but complete streaming anyway
                            print("⚠️ Failed to finalize message \(responseMessage.responseId) in Core Data: \(error)")
                        }

                        let completedMessage = OAChatMessage(
                            id: responseMessage.responseId,
                            role: .assistant,
                            content: responseMessage.content,
                            date: responseMessage.timestamp
                        )

                        // Always complete the stream successfully with the final message
                        let completedEvent = ChatEvent.messageCompleted(chatId: chatId, message: completedMessage)
                        eventContinuation.yield(completedEvent)
                        continuation.finish()

                    case .streamError(let streamingError):
                        let structuredError = StructuredError.streamingFailed(
                            chatId: chatId,
                            phase: "streamProvider",
                            underlyingError: streamingError
                        )
                        let errorEvent = ChatEvent.streamingError(chatId: chatId, error: structuredError)
                        eventContinuation.yield(errorEvent)
                        continuation.finish()
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    deinit {
        eventContinuation.finish()
    }

    // MARK: - Chat Management

    func createNewChat() async throws {
        try await coreDataManager.newChat()
        eventContinuation.yield(.chatCreated)
    }

    func deleteChat(with id: String) async throws {
        try await coreDataManager.deleteChat(with: id)
        eventContinuation.yield(.chatDeleted(chatId: id))
    }
    
    func deleteChats(with ids: [String]) async throws {
        try await coreDataManager.deleteChats(with: ids)
        // Send individual delete events for each chat
        for id in ids {
            eventContinuation.yield(.chatDeleted(chatId: id))
        }
    }

    func getChats() async throws -> [OAChat] {
        try await coreDataManager.fetchPersistedChats()
        return coreDataManager.getCurrentChats()
    }

    func getChat(with id: String) async throws -> OAChat? {
        return coreDataManager.getCurrentChats().first(where: { $0.id == id })
    }

    // MARK: - Message Management

    func getMessages(for chatId: String) async throws -> [OAChatMessage] {
        return try await coreDataManager.fetchMessages(for: chatId)
    }

    func saveMessage(_ message: OAChatMessage, toChatId chatId: String) async throws {
        try await coreDataManager.saveMessage(message, toChatID: chatId)
    }

    // MARK: - Configuration

    func updateChatModel(_ chatId: String, model: OAModel) async throws {
        try await coreDataManager.updateSelectedModelFor(chatId, model: model)
    }

    func updateProvisionalText(_ chatId: String, text: String?) async throws {
        try await coreDataManager.updateProvisionalInputText(for: chatId, text: text)
    }

    func generateChatTitle(userMessage: String, assistantMessage: String, chatId: String) async throws {
        let generatedTitle = try await streamProvider.generateTitle(userMessage: userMessage, assistantMessage: assistantMessage)
        try await coreDataManager.updateChatTitle(chatId, title: generatedTitle)
    }
}

// MARK: - OACoreDataManagerDelegate

extension OAChatRepositoryImpl: OACoreDataManagerDelegate {
    func coreDataManagerDidUpdateChats(_ chats: [OAChat]) {
        eventContinuation.yield(.chatsUpdated(chats))
    }
}
