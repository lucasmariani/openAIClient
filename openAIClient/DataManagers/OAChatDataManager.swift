//
// OAChatDataManager.swift
// openAIClient
//
// Created by Lucas on 29.05.25.
//


import Foundation
import SwiftOpenAI
import Combine
import SwiftUI

@MainActor
final class OAChatDataManager {
    private var responseProvider: ResponseStreamProvider? = nil

//    private let conversation: Conversation?
    private var observationTask: Task<Void, Never>?

    private let coreDataManager: OACoreDataManager

    private var currentChatId: String? = nil
    var messages: [OAChatMessage] = []

    var onMessagesUpdated: ((_ reconfigureItemID: String?) -> Void)?

    @Published
    var selectedModel: SwiftOpenAI.Model

    init(coreDataManager: OACoreDataManager) {
        self.coreDataManager = coreDataManager
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "API_KEY") as? String else {
            self.selectedModel = .gpt41nano
            print("Error retrieving API_KEY")
            return
        }
        let configuration = URLSessionConfiguration.default
        let service = OpenAIServiceFactory.service(apiKey: apiKey, configuration: configuration)

        self.selectedModel = .gpt41nano
        self.responseProvider = ResponseStreamProvider(service: service, model: self.selectedModel)
     }

    deinit {
        observationTask?.cancel()
    }

    func loadLatestChat() {
        if let latestChat = self.coreDataManager.chats.first {
            Task {
                await self.loadChat(with: latestChat.id)
            }
        }
    }

    func updateModel(_ model: SwiftOpenAI.Model) async {
        try? await self.coreDataManager.updateSelectedModelFor(self.currentChatId, model: model)
        self.selectedModel = model
//        conversation?.updateConfig { config in
//            config.model = model
//        }
    }

    func saveProvisionaryTextInput(_ inputText: String?) async {
        guard let chatId = self.currentChatId, let inputText else { return }
        do {
            try? await self.coreDataManager.updateProvisionaryInputText(for: chatId, text: inputText)
        }
    }

    @discardableResult
    func loadChat(with id: String) async -> OAChat? {
        guard let chat = self.coreDataManager.chats.first(where: { $0.id == id }) else {
            print("Error: Chat with ID \(id) not found in dataManager.chats")
            self.setCurrentChat(nil)
            self.messages = []
            self.onMessagesUpdated?(nil)
            return nil
        }
        self.setCurrentChat(chat.id)
        self.messages = [] // Clear any previous messages

        do {
            // Check for updates from CloudKit before loading messages
            print("🔄 Checking for new messages when opening chat: \(id)")
            self.messages = try await self.coreDataManager.refreshMessages(for: chat.id)
            self.onMessagesUpdated?(nil)
        } catch {
            print("Failed to load messages for chat \(chat.id): \(error)")
            // Handle error (e.g., show an alert to the user)
        }

        await self.updateModel(chat.selectedModel)
        return chat
    }

    func getChatTitle(for chatId: String) -> String? {
        guard let chat = self.coreDataManager.chats.first(where: { $0.id == chatId }) else {
            return nil
        }
        return chat.title
    }

    func sendMessage(_ chatMessage: OAChatMessage) {
        guard let currentChatId else { return }

        self.messages.append(chatMessage)
        self.onMessagesUpdated?(nil) // General refresh (new user message)

        Task {
            do {
                try await coreDataManager.addMessage(chatMessage, toChatID: currentChatId)
            } catch {
                print("Failed to save message: \(error)")
                // TODO: Show an alert to the user about the failure.
            }

            self.responseProvider?.sendMessage(chatMessage.content)
        }
    }

    func setCurrentChat(_ chatId: String?) {
        guard let chatId else {
            self.currentChatId = nil
            return
        }

        self.currentChatId = chatId
        self.setupConversationObserver()
    }

    private func setupConversationObserver() {
        self.observationTask?.cancel()

        self.observationTask = Task { [weak self] in
            guard let self else { return }
            
            var lastMessageCount = 0
            var lastMessageContent = ""

            while !Task.isCancelled {
                withObservationTracking {
                    _ = self.responseProvider?.messages
                } onChange: {
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        
                        // Throttle updates to prevent excessive UI refreshes
                        let currentMessageCount = self.responseProvider?.messages.count ?? 0
                        let currentLastContent = self.responseProvider?.messages.last?.content ?? ""

                        let messageCountChanged = currentMessageCount != lastMessageCount
                        let contentChanged = currentLastContent != lastMessageContent


                        if messageCountChanged || contentChanged {
                            lastMessageCount = currentMessageCount
                            lastMessageContent = currentLastContent
                            await self.handleConversationUpdate()
                        }
                    }
                }

                if Task.isCancelled {
                    break
                }

                do {
                    // Slightly longer sleep to reduce CPU usage during streaming
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    break
                }
            }
        }
    }

    private func handleConversationUpdate() async {
        guard let currentChatId = self.currentChatId else {
            print("Error: currentChatId is nil in handleConversationUpdate.")
            return
        }

        guard let responseProvider = self.responseProvider else { return }
        
        // Get the last assistant message from the response provider
        if let message = responseProvider.messages.last, message.role == .assistant {
            let messageId = message.id.uuidString
            
            if let existingMessageIndex = self.messages.firstIndex(where: { $0.id == messageId }) {
                // Update existing message
                self.updateExistingMessage(with: messageId,
                                           at: existingMessageIndex,
                                           content: message.content,
                                           chatId: currentChatId,
                                           isStreaming: message.isStreaming)
            } else {
                // Create new assistant message only if content is not empty
                if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.createNewAssistant(message: message, currentChatId: currentChatId)
                }
            }
        }
    }

    private func createNewAssistant(message: ResponseStreamProvider.ResponseMessage, currentChatId: String) {
        print("Creating new assistant message with ID \(message.id)")
        
        // Avoid creating duplicate messages
        if self.messages.contains(where: { $0.id == message.id.uuidString }) {
            print("Warning: Assistant message with ID \(message.id) already exists")
            return
        }
        
        let assistantMessage = OAChatMessage(
            id: message.id.uuidString,
            role: .assistant,
            content: message.content,
            date: Date.now
        )
        self.messages.append(assistantMessage)

        // Don't save to Core Data yet - wait until streaming completes
        
        // Notify UI for update
        self.onMessagesUpdated?(nil)
    }

    private func updateExistingMessage(with messageId: String, at index: Array.Index, content: String, chatId: String, isStreaming: Bool) {
        // Skip empty content updates during streaming
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedContent.isEmpty && isStreaming {
            return
        }

        let date = Date.now
        var messageToUpdate = self.messages[index]
        messageToUpdate.update(with: content, date: date)
        self.messages[index] = messageToUpdate

        print("Message with ID \(messageId) updated locally. Content length: \(content.count), isStreaming: \(isStreaming)")

        // Persist to Core Data only when streaming is complete
        if !isStreaming {
            Task(priority: .background) {
                do {
                    // Try to update first, if that fails, create new message
                    try await self.coreDataManager.updateMessage(
                        with: messageId,
                        chatId: chatId,
                        content: content,
                        date: date
                    )
                    print("Successfully updated message \(messageId) in Core Data")
                } catch {
                    // If update fails (message doesn't exist), create it
                    do {
                        let assistantMessage = OAChatMessage(
                            id: messageId,
                            role: .assistant,
                            content: content,
                            date: date
                        )
                        try await self.coreDataManager.addMessage(assistantMessage, toChatID: chatId)
                        print("Successfully created message \(messageId) in Core Data")
                    } catch {
                        print("Failed to create message \(messageId) in Core Data: \(error)")
                    }
                }
            }
        }

        // Notify UI for updates
        self.onMessagesUpdated?(messageId)
    }
}
