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
protocol OAChatRepository {
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
    func startStreaming(content: String, chatId: String, model: Model, attachments: [OAAttachment]) async throws

    // Configuration
    func updateChatModel(_ chatId: String, model: Model) async throws
    func updateProvisionalText(_ chatId: String, text: String?) async throws
    func updateChatPreviousResponseId(_ chatId: String, responseId: String?) async throws
    func resetChatConversationContext(_ chatId: String) async throws
    func clearStreamProviderState() async

    // Title generation
    func generateChatTitle(userMessage: String, assistantMessage: String, chatId: String) async throws
}

// MARK: - Repository Implementation

@MainActor
final class OAChatRepositoryImpl: OAChatRepository {

    // MARK: - Dependencies

    let coreDataManager: OACoreDataManager
    private let streamingCoordinator: StreamingCoordinator

    // MARK: - Event Streaming

    private let eventContinuation: AsyncStream<ChatEvent>.Continuation
    let eventStream: AsyncStream<ChatEvent>


    // MARK: - Initialization

    init(coreDataManager: OACoreDataManager, streamingCoordinator: StreamingCoordinator) {
        self.coreDataManager = coreDataManager
        self.streamingCoordinator = streamingCoordinator

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

    func startStreaming(content: String, chatId: String, model: Model, attachments: [OAAttachment] = []) async throws {
        // Get the chat's current previousResponseId
        let currentChat = try await getChat(with: chatId)
        let previousResponseId = currentChat?.previousResponseId
        
        // Get the actual conversation history for this chat
        let chatMessages = try await getMessages(for: chatId)
        let conversationHistory = chatMessages.map { chatMessage in
            ResponseMessage(
                role: chatMessage.role == .user ? .user : .assistant,
                content: chatMessage.content,
                timestamp: chatMessage.date,
                responseId: chatMessage.id
            )
        }
        
        // Clear streaming state to prevent cross-chat pollution
        streamingCoordinator.clearMessages()
        
        // Start streaming task that feeds events into the main eventStream only
        Task { @MainActor in
            let streamEvents = streamingCoordinator.streamMessage(text: content,
                                                                  attachments: attachments,
                                                                  previousResponseId: previousResponseId)
            for await event in streamEvents {
                guard !Task.isCancelled else { break }

                switch event {
                case .messageStarted(let message):
                    print("🟡 ChatRepository Starting message with ID: \(message.id) for chat: \(chatId)")

                    let chatMessage = OAChatMessage(id: message.responseId,
                                                    role: .assistant,
                                                    content: message.content,
                                                    date: message.timestamp)
                    // Save initial message to Core Data
                    do {
                        try await coreDataManager.saveMessage(chatMessage, toChatID: chatId, isStreaming: true)
                    } catch {
                        print("❌ Failed to save initial message to Core Data: \(error)")
                    }

                    // Emit to SINGLE event stream only
                    eventContinuation.yield(.messageStarted(chatId: chatId, message: chatMessage))

                case .messageUpdated(let message):
                    print("🟡 Updating message with ID: \(message.id) for chat: \(chatId)")

                    // Update in Core Data - create a response message for Core Data
                    let responseMessage = OAChatMessage(id: message.responseId,
                                                        role: .assistant,
                                                        content: message.content,
                                                        date: message.timestamp)

                    do {
                        try await coreDataManager.updateMessage(with: responseMessage,
                                                                chatId: chatId,
                                                                isStreaming: true)
                    } catch {
                        // Core Data update failed - log but continue streaming
                        print("⚠️ Failed to update message \(responseMessage.id) in Core Data: \(error)")
                    }

                    // Emit to SINGLE event stream only
                    eventContinuation.yield(.messageUpdated(chatId: chatId, message: responseMessage))

                case .messageCompleted(let message):
                    print("🟢 ChatRepository Completing message with ID: \(message.id) for chat: \(chatId)")

                    // Final update in Core Data - create a response message for Core Data
                    let responseMessage = OAChatMessage(id: message.responseId,
                                                        role: .assistant,
                                                        content: message.content,
                                                        date: message.timestamp)

                    do {
                        try await coreDataManager.updateMessage(with: responseMessage,
                                                                chatId: chatId,
                                                                isStreaming: false)
                    } catch {
                        // Core Data update failed - log but complete streaming anyway
                        print("⚠️ Failed to finalize message \(responseMessage.id) in Core Data: \(error)")
                    }

                    // Save the new previousResponseId to this chat
                    do {
                        try await updateChatPreviousResponseId(chatId, responseId: message.responseId)
                    } catch {
                        print("⚠️ Failed to update chat previousResponseId: \(error)")
                    }

                    // Emit to SINGLE event stream only
                    eventContinuation.yield(.messageCompleted(chatId: chatId, message: responseMessage))

                case .streamError(let streamingError):
                    let structuredError = StructuredError.streamingFailed(
                        chatId: chatId,
                        phase: "streamingCoordinator",
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

    func updateChatModel(_ chatId: String, model: Model) async throws {
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
        streamingCoordinator.clearMessages()
    }

    func generateChatTitle(userMessage: String, assistantMessage: String, chatId: String) async throws {
        let generatedTitle = try await streamingCoordinator.generateTitle(userMessage: userMessage, assistantMessage: assistantMessage)
        try await coreDataManager.updateChatTitle(chatId, title: generatedTitle)
    }
}

// MARK: - OACoreDataManagerDelegate

extension OAChatRepositoryImpl: OACoreDataManagerDelegate {
    func coreDataManagerDidUpdateChats(_ chats: [OAChat]) {
        eventContinuation.yield(.chatsUpdated(chats))
    }
}
