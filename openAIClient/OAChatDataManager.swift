//
// OAChatDataManager.swift
// openAIClient
//
// Created by Lucas on 29.05.25.
//


import Foundation
import OpenAI

@MainActor
final class OAChatDataManager {
    private let conversation: Conversation?
    private var observationTask: Task<Void, Never>?

    private let coreDataManager: OACoreDataManager

    private var currentChatId: String? = nil
    /*private*/ var messages: [OAChatMessage] = []

    var onMessagesUpdated: ((_ reconfigureItemID: String?) -> Void)?

    init(coreDataManager: OACoreDataManager) {
        self.coreDataManager = coreDataManager
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "API_KEY") as? String else {
            conversation = nil
            print("Error retrieving API_KEY")
            return
        }
        conversation = Conversation(authToken: apiKey, using: .gpt41nano)
    }

    deinit {
        observationTask?.cancel()
    }

    func loadChat(with id: String) async {

        guard let chat = self.coreDataManager.chats.first(where: { $0.id == id }) else {
            print("Error: Chat with ID \(id) not found in dataManager.chats")
            self.setCurrentChat(nil)
            self.messages = []
            self.onMessagesUpdated?(nil)
            return
        }
        self.setCurrentChat(chat.id)
        self.messages = [] // Clear any previous messages

        do {
            self.messages = try await self.coreDataManager.fetchMessages(for: chat.id)
            self.onMessagesUpdated?(nil)
        } catch {
            print("Failed to load messages for chat \(chat.id): \(error)")
            // Handle error (e.g., show an alert to the user)
        }
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

            do {
                let textInput = Input(chatMessage.content)
                try await self.conversation?.send(textInput)
            } catch {
                print("Failed to send message: \(error)")
            }
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

            while !Task.isCancelled {
                withObservationTracking {
                    _ = self.conversation?.entries
                } onChange: {
                    Task { [weak self] in
                        guard let self = self else { return }
                        await self.handleConversationUpdate()
                    }
                }

                if Task.isCancelled {
                    break
                }

                do {
                    try await Task.sleep(for: .milliseconds(10))
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

        if let lastEntry = self.conversation?.entries.last, case .response(let response) = lastEntry {
            for item in response.output {
                if case .message(let message) = item, message.role == .assistant {
                    if let existingMessageIndex = self.messages.firstIndex(where: { $0.id == message.id }) {
                        self.updateExistingMessage(with: message.id, at: existingMessageIndex, content: message.text, chatId: currentChatId)
                    } else {
                        // New message
                        print("New assistant message with ID \(message.id)")
                        let assistantMessage = OAChatMessage(
                            id: message.id,
                            role: .assistant,
                            content: message.text,
                            date: Date.now
                        )
                        self.messages.append(assistantMessage)

                        // Persist this new assistant message
                        Task(priority: .background) {
                            do {
                                try await self.coreDataManager.addMessage(assistantMessage, toChatID: currentChatId)
                            } catch {
                                print("Failed to save new assistant message: \(error)")
                            }
                        }
                        // Notify UI for optimistic update (must be on main thread)
                        self.onMessagesUpdated?(nil)
                    }
                }
            }
        }
    }

    private func updateExistingMessage(with messageId: String, at index: Array.Index, content: String, chatId: String) {
        let date = Date.now
        var messageToUpdate = self.messages[index]
        messageToUpdate.update(with: content, date: date)
        self.messages[index] = messageToUpdate

        print("Message with ID \(messageId) updated locally with content: \(content)")

        // 2. Persist to Core Data (can be in a background task)
        Task(priority: .background) {
            do {
                try await self.coreDataManager.updateMessage(
                    with: messageId,
                    chatId: chatId,
                    content: content,
                    date: date
                )
            } catch {
                print("Failed to update message \(messageId) in Core Data: \(error)")
                // TODO: Error handling (e.g., revert local update or notify user)
            }
        }

        // 3. Notify UI (must be on main thread)
        self.onMessagesUpdated?(messageId)
    }
}
