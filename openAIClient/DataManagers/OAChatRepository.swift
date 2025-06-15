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

    // Streaming - simplified to just start streaming, events flow through main eventStream
    func startStreaming(content: String, chatId: String, model: OAModel, attachments: [OAAttachment]) async throws

    // Configuration
    func updateChatModel(_ chatId: String, model: OAModel) async throws
    func updateProvisionalText(_ chatId: String, text: String?) async throws
    func updateChatPreviousResponseId(_ chatId: String, responseId: String?) async throws
    func resetChatConversationContext(_ chatId: String) async throws
    func clearStreamProviderState() async

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
        // Using Task to properly cross actor boundaries
        Task {
            await coreDataManager.setDelegate(self)
        }
    }

    deinit {
        eventContinuation.finish()
    }

    // MARK: - Simplified Single-Stream Architecture

    func startStreaming(content: String, chatId: String, model: OAModel, attachments: [OAAttachment] = []) async throws {
        // Get the chat's current previousResponseId
        let currentChat = try await getChat(with: chatId)
        let previousResponseId = currentChat?.previousResponseId
        
        // Get the actual conversation history for this chat
        let chatMessages = try await getMessages(for: chatId)
        let conversationHistory = chatMessages.map { chatMessage in
            OAResponseMessage(
                role: chatMessage.role == .user ? .user : .assistant,
                content: chatMessage.content,
                timestamp: chatMessage.date,
                responseId: chatMessage.id
            )
        }
        
        // Clear stream provider state to prevent cross-chat pollution
        streamProvider.clearMessages()
        
        // Start streaming task that feeds events into the main eventStream only
        Task { @MainActor in
            let streamEvents = streamProvider.streamEvents(for: content, attachments: attachments, previousResponseId: previousResponseId, conversationHistory: conversationHistory)
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

                    print("🟡 ChatRepository Starting message with ID: \(responseMessage.responseId) for chat: \(chatId)")

                    // Save initial message to Core Data
                    do {
                        try await coreDataManager.saveMessage(assistantMessage, toChatID: chatId, isStreaming: true)
                    } catch {
                        print("❌ Failed to save initial message to Core Data: \(error)")
                    }

                    // Emit to SINGLE event stream only
                    eventContinuation.yield(.messageStarted(chatId: chatId, message: assistantMessage))

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

                    // Emit to SINGLE event stream only
                    eventContinuation.yield(.messageUpdated(chatId: chatId, message: updatedMessage))

                case .messageCompleted(let responseMessage):
                    print("🟢 ChatRepository Completing message with ID: \(responseMessage.responseId) for chat: \(chatId)")

                    // Final update in Core Data
                    do {
                        try await coreDataManager.updateMessage(with: responseMessage,
                                                                chatId: chatId,
                                                                isStreaming: false)
                    } catch {
                        // Core Data update failed - log but complete streaming anyway
                        print("⚠️ Failed to finalize message \(responseMessage.responseId) in Core Data: \(error)")
                    }
                    
                    // Save the new previousResponseId to this chat
                    do {
                        try await updateChatPreviousResponseId(chatId, responseId: responseMessage.responseId)
                    } catch {
                        print("⚠️ Failed to update chat previousResponseId: \(error)")
                    }

                    let completedMessage = OAChatMessage(
                        id: responseMessage.responseId,
                        role: .assistant,
                        content: responseMessage.content,
                        date: responseMessage.timestamp
                    )

                    // Emit to SINGLE event stream only
                    eventContinuation.yield(.messageCompleted(chatId: chatId, message: completedMessage))

                case .streamError(let streamingError):
                    let structuredError = StructuredError.streamingFailed(
                        chatId: chatId,
                        phase: "streamProvider",
                        underlyingError: streamingError
                    )

                    // Emit to SINGLE event stream only
                    eventContinuation.yield(.streamingError(chatId: chatId, error: structuredError))
                }
            }
        }
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
        return await coreDataManager.getCurrentChats()
    }

    func getChat(with id: String) async throws -> OAChat? {
        let chats = await coreDataManager.getCurrentChats()
        return chats.first(where: { $0.id == id })
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
    
    func updateChatPreviousResponseId(_ chatId: String, responseId: String?) async throws {
        try await coreDataManager.updatePreviousResponseId(chatId, previousResponseId: responseId)
    }
    
    func resetChatConversationContext(_ chatId: String) async throws {
        try await updateChatPreviousResponseId(chatId, responseId: nil)
    }
    
    func clearStreamProviderState() async {
        streamProvider.clearMessages()
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
