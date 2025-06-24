//
// OAChatManager.swift
// openAIClient
//
// Created by Lucas on 17.06.25.
//

import Foundation
import Observation
import OpenAIForSwift

enum ChatViewState {
    case empty
    case chat(id: String, messages: [OAChatMessage], reconfiguringMessageID: String? = nil, isStreaming: Bool = false)
    case loading
    case error(String)

    var currentChatId: String? {
        switch self {
        case .chat(let id, _, _, _):
            return id
        default:
            return nil
        }
    }
}

// UI Events emitted by ChatManager
enum ChatUIEvent {
    case viewStateChanged(ChatViewState)
    case modelChanged(Model)
    case showErrorAlert(String)
}

@MainActor
@Observable
final class OAChatManager {

    // MARK: - Properties

    private let coreDataManager: OACoreDataManager
    private let streamingCoordinator: StreamingCoordinator
    private var currentChatId: String? = nil

    // UI State - All UI components bind to these properties
    var chats: [OAChat] = []           // For sidebar
    var messages: [OAChatMessage] = [] // For chat view
    var selectedModel: Model = .gpt41nano // Default model, will be overridden when loading chats
    var viewState: ChatViewState = .loading

    // Web search configuration
    var webSearchEnabled: Bool = false
    var userLocation: UserLocation? = nil

    private var streamingTask: Task<Void, Never>?

    // UI Event Stream - for complex state changes
    private let uiEventContinuation: AsyncStream<ChatUIEvent>.Continuation
    let uiEventStream: AsyncStream<ChatUIEvent>

    // MARK: - Initialization

    init(coreDataManager: OACoreDataManager, streamingCoordinator: StreamingCoordinator) {
        self.coreDataManager = coreDataManager
        self.streamingCoordinator = streamingCoordinator

        // Setup UI Event Stream
        let (stream, continuation) = AsyncStream<ChatUIEvent>.makeStream()
        self.uiEventStream = stream
        self.uiEventContinuation = continuation

        setupCoreDataObservation()
        loadInitialChats()
    }

    deinit {
        uiEventContinuation.finish()
    }

    private func setupCoreDataObservation() {
        Task {
            await coreDataManager.setDelegate(self)
        }
    }

    private func loadInitialChats() {
        Task {
            do {
                try await coreDataManager.fetchPersistedChats()
                chats = await coreDataManager.getCurrentChats()
                if chats.isEmpty {
                    viewState = .empty
                    uiEventContinuation.yield(.viewStateChanged(.empty))
                }
            } catch {
                print("Failed to load initial chats: \(error)")
                let errorState = ChatViewState.error("Failed to load chats")
                viewState = errorState
                uiEventContinuation.yield(.viewStateChanged(errorState))
            }
        }
    }

    // MARK: - Public Methods

    func loadLatestChat() {
        Task {
            do {
                try await coreDataManager.fetchPersistedChats()
                let chats = await coreDataManager.getCurrentChats()
                if let latestChat = chats.first {
                    await loadChat(with: latestChat.id)
                }
            } catch {
                print("Failed to load latest chat: \(error)")
            }
        }
    }

    func updateModel(_ model: Model) async {
        // Update the current chat's model
        guard let chatId = currentChatId else {
            print("⚠️ No current chat selected - cannot update model")
            return
        }

        do {
            try await coreDataManager.updateSelectedModelFor(chatId, model: model)
            selectedModel = model
            uiEventContinuation.yield(.modelChanged(model))
            print("✅ Successfully updated model for chat \(chatId) to \(model.displayName)")
        } catch {
            print("❌ Failed to update model for chat: \(error)")
            uiEventContinuation.yield(.showErrorAlert("Failed to update model"))
        }
    }

    func saveProvisionalTextInput(_ inputText: String?) async {
        guard let chatId = currentChatId else { return }
        do {
            try await coreDataManager.updateProvisionalInputText(for: chatId, text: inputText)
        } catch {
            print("Failed to save provisional text: \(error)")
        }
    }

    func toggleWebSearch() {
        webSearchEnabled.toggle()
    }

    func setUserLocation(_ location: UserLocation?) {
        userLocation = location
    }

    func setWebSearchEnabled(_ enabled: Bool) {
        webSearchEnabled = enabled
    }

    @discardableResult
    func loadChat(with id: String) async -> OAChat? {
        do {
            // Clear streaming state when switching chats
            streamingCoordinator.clearMessages()

            let allChats = await coreDataManager.getCurrentChats()
            guard let chat = allChats.first(where: { $0.id == id }) else {
                clearCurrentChat()
                return nil
            }

            currentChatId = id
            messages = try await coreDataManager.fetchMessages(for: id)
            let oldModel = selectedModel

            // Use the chat's selected model
            selectedModel = chat.selectedModel

            if let chatId = currentChatId {
                let newViewState = ChatViewState.chat(id: chatId, messages: messages, reconfiguringMessageID: nil, isStreaming: false)
                viewState = newViewState
                uiEventContinuation.yield(.viewStateChanged(newViewState))
            } else {
                viewState = .empty
                uiEventContinuation.yield(.viewStateChanged(.empty))
            }

            // Emit model change event if model changed
            if oldModel != selectedModel {
                uiEventContinuation.yield(.modelChanged(selectedModel))
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
        let newViewState = ChatViewState.chat(id: currentChatId, messages: messages, reconfiguringMessageID: chatMessage.id, isStreaming: true)
        viewState = newViewState
        uiEventContinuation.yield(.viewStateChanged(newViewState))

        Task {
            do {
                // Save user message
                try await coreDataManager.saveMessage(chatMessage, toChatID: currentChatId)

                // Get current chat's previousResponseId
                let allChats = await coreDataManager.getCurrentChats()
                let currentChat = allChats.first(where: { $0.id == currentChatId })
                let previousResponseId = currentChat?.previousResponseId

                // Clear streaming state to prevent cross-chat pollution
                streamingCoordinator.clearMessages()

                // Start streaming assistant response directly
                streamingTask?.cancel()
                streamingTask = Task { @MainActor in
                    //                    do {
                    let streamEvents = streamingCoordinator.streamMessage(
                        text: chatMessage.content,
                        model: selectedModel,
                        attachments: chatMessage.attachments.map { $0.fileAttachment(from: $0) },
                        previousResponseId: previousResponseId,
                        webSearchEnabled: webSearchEnabled,
                        userLocation: userLocation
                    )

                    for await event in streamEvents {
                        guard !Task.isCancelled else { break }
                        await handleStreamingEvent(event, chatId: currentChatId)
                    }

                    print("🏁 ChatManager: Streaming task completed successfully")
                    //                    } catch {
                    //                        print("❌ ChatManager: Failed to start streaming: \(error)")
                    //                        handleStreamingError(error, chatId: currentChatId)
                    //                    }
                }

            } catch {
                print("Failed to send message: \(error)")
                let errorState = ChatViewState.error("Failed to send message")
                viewState = errorState
                uiEventContinuation.yield(.viewStateChanged(errorState))
            }
        }
    }

    func setCurrentChat(_ chatId: String?) {
        streamingTask?.cancel()
        currentChatId = chatId

        if chatId == nil {
            clearCurrentChat()
        }

        // Clear streaming state to prevent cross-chat conversation pollution
        streamingCoordinator.clearMessages()
    }

    // MARK: - Chat Management Methods

    func createNewChat() async throws {
        try await coreDataManager.newChat()
    }

    func deleteChat(with id: String) async throws {
        try await coreDataManager.deleteChat(with: id)
        if id == currentChatId {
            clearCurrentChat()
        }
    }

    func deleteChats(with ids: [String]) async throws {
        try await coreDataManager.deleteChats(with: ids)
        if let currentChatId = currentChatId, ids.contains(currentChatId) {
            clearCurrentChat()
        }
    }

    // MARK: - Private Methods

    private func clearCurrentChat() {
        currentChatId = nil
        messages = []
        viewState = .empty
        uiEventContinuation.yield(.viewStateChanged(.empty))
    }

    private func handleStreamingEvent(_ event: UIStreamEvent, chatId: String) async {
        switch event {
        case .messageStarted(let message):
            print("🟡 ChatManager: Starting message with ID: \(message.responseId) for chat: \(chatId)")

            let chatMessage = OAChatMessage(
                id: message.responseId,
                role: OARole.assistant,
                content: message.content,
                date: message.timestamp
            )

            // Save initial message to Core Data
            do {
                try await coreDataManager.saveMessage(chatMessage, toChatID: chatId, isStreaming: true)
            } catch {
                print("❌ Failed to save initial message to Core Data: \(error)")
            }

            // Update UI state
            if chatId == currentChatId {
                messages.append(chatMessage)
                let newViewState = ChatViewState.chat(id: chatId, messages: messages, reconfiguringMessageID: chatMessage.id, isStreaming: true)
                viewState = newViewState
                uiEventContinuation.yield(.viewStateChanged(newViewState))
                print("📊 ChatManager: Updated viewState to streaming with \(messages.count) messages")
            }

        case .messageUpdated(let message):
            print("🟡 ChatManager: Updating message with ID: \(message.responseId) for chat: \(chatId)")

            let responseMessage = OAChatMessage(
                id: message.responseId,
                role: OARole.assistant,
                content: message.content,
                date: message.timestamp
            )

            do {
                try await coreDataManager.updateMessage(with: responseMessage, chatId: chatId, isStreaming: true)
            } catch {
                print("⚠️ Failed to update message \(responseMessage.id) in Core Data: \(error)")
            }

            // Update UI state
            if chatId == currentChatId {
                updateMessageInLocalArray(responseMessage)
                let newViewState = ChatViewState.chat(id: chatId, messages: messages, reconfiguringMessageID: responseMessage.id, isStreaming: true)
                viewState = newViewState
                uiEventContinuation.yield(.viewStateChanged(newViewState))
                print("📊 ChatManager: Updated viewState to streaming with \(messages.count) messages")
            }

        case .messageCompleted(let message):
            print("🟢 ChatManager: Completing message with ID: \(message.responseId) for chat: \(chatId)")

            let responseMessage = OAChatMessage(
                id: message.responseId,
                role: OARole.assistant,
                content: message.content,
                date: message.timestamp
            )

            do {
                try await coreDataManager.updateMessage(with: responseMessage, chatId: chatId, isStreaming: false)
                // Save the new previousResponseId to this chat
                try await coreDataManager.updatePreviousResponseId(chatId, previousResponseId: message.responseId)
            } catch {
                print("⚠️ Failed to finalize message \(responseMessage.id) in Core Data: \(error)")
            }

            // Update UI state
            if chatId == currentChatId {
                updateMessageInLocalArray(responseMessage)
                let newViewState = ChatViewState.chat(id: chatId, messages: messages, reconfiguringMessageID: responseMessage.id, isStreaming: false)
                viewState = newViewState
                uiEventContinuation.yield(.viewStateChanged(newViewState))
                print("📊 ChatManager: messageCompleted. Updated viewState to non-streaming with \(messages.count) messages")

                // Generate title after first assistant response
                if responseMessage.role == OARole.assistant && shouldGenerateTitle() {
                    Task {
                        await generateChatTitle(for: chatId)
                    }
                }
            }

        case .toolCallStarted(let toolCall):
            print("🔧 ChatManager: Tool call started: \(toolCall.type) with ID: \(toolCall.id)")
            // Optionally show a loading indicator for tool calls in the UI

        case .toolCallCompleted(let toolCall):
            print("✅ ChatManager: Tool call completed: \(toolCall.type) with ID: \(toolCall.id)")
            // The tool call results will be included in the final message content

        case .streamError(let error):
            handleStreamingError(error, chatId: chatId)
            //TODO: handle these new events.
        case .annotationAdded(_, itemId: let itemId, contentIndex: let contentIndex):
            break
        case .functionCallArgumentsDelta(callId: let callId, delta: let delta):
            break
        case .functionCallArgumentsDone(callId: let callId, arguments: let arguments):
            break
        case .reasoningDelta(delta: let delta):
            break
        case .reasoningDone(reasoning: let reasoning):
            break
        }
    }

    private func handleStreamingError(_ error: Error, chatId: String) {
        if chatId == currentChatId {
            let errorString = "Streaming error in chat \(chatId): \(error)"
            print(errorString)

            // Extract user-friendly error message from API errors
            let userErrorMessage = extractUserFriendlyErrorMessage(from: error)

            // Remove any incomplete assistant message that was being streamed
            if let lastMessageIndex = messages.lastIndex(where: { $0.role == OARole.assistant && $0.content.isEmpty }) {
                messages.remove(at: lastMessageIndex)
            }

            // Update viewState to non-streaming and show error alert
            let newViewState = ChatViewState.chat(id: chatId, messages: messages, reconfiguringMessageID: nil, isStreaming: false)
            viewState = newViewState
            uiEventContinuation.yield(.viewStateChanged(newViewState))
            uiEventContinuation.yield(.showErrorAlert(userErrorMessage))
        }
    }

    private func updateMessageInLocalArray(_ message: OAChatMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            let oldContent = messages[index].content
            messages[index] = message
            print("🔄 ChatManager: Updated message at index \(index), content changed: \(oldContent.count) → \(message.content.count) chars")
        } else {
            print("⚠️ ChatManager: Could not find message with ID \(message.id) in local array of \(messages.count) messages")
            print("⚠️ ChatManager: Available message IDs: \(messages.map { $0.id })")
        }
    }

    private func shouldGenerateTitle() -> Bool {
        // Generate title only if we have exactly 2 messages (1 user + 1 assistant)
        return messages.count == 2 &&
        messages.first?.role == OARole.user &&
        messages.last?.role == OARole.assistant
    }

    private func extractUserFriendlyErrorMessage(from error: Error) -> String {
        // Handle streaming errors
        if let streamingError = error as? StreamingError {
            switch streamingError {
            case .serviceFailed(let underlying):
                return extractUserFriendlyErrorMessage(from: underlying)
            case .networkError(let description):
                return "Network error: \(description)"
            case .rateLimited:
                return "Rate limit exceeded. Please try again later."
            case .invalidContent:
                return "Invalid content in response."
            case .streamCancelled:
                return "Request was cancelled."
            case .maxRetriesExceeded(lastError: let lastError):
                return "Max retried exceeded. Error: \(lastError.localizedDescription)"
            }
        }

        // Handle OpenAI API errors by checking the error description
        let errorDescription = error.localizedDescription

        // Look for OpenAI error response format in the description
        if errorDescription.contains("not supported with") {
            // Extract the specific error from OpenAI API format
            if let range = errorDescription.range(of: "message\":\"([^\"]*)\"", options: .regularExpression) {
                let messageContent = String(errorDescription[errorDescription.index(range.lowerBound, offsetBy: 10)..<errorDescription.index(range.upperBound, offsetBy: -1)])
                return messageContent
            }
        }

        // Parse JSON error responses
        if let data = errorDescription.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorDict = json["error"] as? [String: Any],
           let message = errorDict["message"] as? String {
            return message
        }

        // Fallback to a user-friendly generic message
        return "An error occurred while processing your request. Please try again."
    }

    private func generateChatTitle(for chatId: String) async {
        guard let userMessage = messages.first?.content,
              let assistantMessage = messages.last?.content else { return }

        do {
            let generatedTitle = try await streamingCoordinator.generateTitle(
                userMessage: userMessage,
                assistantMessage: assistantMessage
            )
            try await coreDataManager.updateChatTitle(chatId, title: generatedTitle)
        } catch {
            print("Failed to generate chat title: \(error)")
        }
    }
}

// MARK: - OACoreDataManagerDelegate

extension OAChatManager: OACoreDataManagerDelegate {
    func coreDataManagerDidUpdateChats(_ chats: [OAChat]) {
        self.chats = chats

        // Check if currently selected chat was deleted during sync (e.g., CloudKit remote changes)
        if let currentChatId = currentChatId {
            let stillExists = chats.contains { $0.id == currentChatId }
            if !stillExists {
                print("📋 ChatManager: Currently selected chat \(currentChatId) was deleted during sync, clearing current chat")
                clearCurrentChat()
            }
        }
    }
}
