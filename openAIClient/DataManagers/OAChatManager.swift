//
// OAChatManager.swift
// openAIClient
//
// Created by Lucas on 17.06.25.
//

import Foundation
import Observation
import OpenAIForSwift

enum WaitingState {
    case none                   // No waiting or streaming
    case waitingForResponse     // User sent message, waiting for API response or content
    case receivingResponse      // API response is streaming with visible content
}

enum ChatViewState {
    case empty
    case chat(id: String, messages: [OAChatMessage], reconfiguringMessageID: String? = nil, waitingState: WaitingState = .none)
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
    
    // Backward compatibility helpers
    var isStreaming: Bool {
        switch self {
        case .chat(_, _, _, let waitingState):
            return waitingState != .none
        default:
            return false
        }
    }
    
    var isWaitingForResponse: Bool {
        switch self {
        case .chat(_, _, _, .waitingForResponse):
            return true
        default:
            return false
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
    private var messages: [OAChatMessage] = [] // For chat view
    var selectedModel: Model = .gpt41nano // Default model, will be overridden when loading chats
    var viewState: ChatViewState = .loading

    // Web search configuration
    var webSearchRequested: Bool = false
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

    func setUserLocation(_ location: UserLocation?) {
        userLocation = location
    }

    func toggleWebSearchRequested() {
        webSearchRequested.toggle()
    }

    func setWebSearchRequested(_ requested: Bool) {
        webSearchRequested = requested
    }

    @discardableResult
    func loadChat(with chatId: String) async -> OAChat? {
        do {
            // Clear streaming state when switching chats
            streamingCoordinator.clearMessages()

            let allChats = await coreDataManager.getCurrentChats()
            guard let chat = allChats.first(where: { $0.id == chatId }) else {
                clearCurrentChat()
                return nil
            }

            currentChatId = chatId
            messages = try await coreDataManager.fetchMessages(for: chatId)
            let oldModel = selectedModel

            // Use the chat's selected model
            selectedModel = chat.selectedModel

            if let chatId = currentChatId {
                let newViewState = ChatViewState.chat(id: chatId, messages: messages, reconfiguringMessageID: nil, waitingState: .none)
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
            print("Failed to load chat \(chatId): \(error)")
            clearCurrentChat()
            return nil
        }
    }

    func sendMessage(_ chatMessage: OAChatMessage) {
        guard let currentChatId else { return }

        // Optimistically add user message to UI with waiting state
        messages.append(chatMessage)
        let newViewState = ChatViewState.chat(id: currentChatId, messages: messages, reconfiguringMessageID: chatMessage.id, waitingState: .waitingForResponse)
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
                    let streamEvents = streamingCoordinator.sendStreamingMessage(
                        text: chatMessage.content,
                        model: selectedModel,
                        attachments: chatMessage.attachments.map { $0.fileAttachment(from: $0) },
                        previousResponseId: previousResponseId,
                        userLocation: userLocation,
                        webSearchRequested: self.webSearchRequested
                    )

                    for await event in streamEvents {
                        guard !Task.isCancelled else { break }
                        await handleStreamingEvent(event, chatId: currentChatId)
                    }

                    print("🏁 ChatManager: Streaming task completed successfully")
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

    func createNewChat() async throws -> String {
        return try await coreDataManager.newChat()
    }

    /// Creates a new chat and automatically selects it for immediate use
    func createAndSelectNewChat() async throws -> String {
        let newChatId = try await coreDataManager.newChat()

        // Automatically select the newly created chat
        await loadChat(with: newChatId)

        return newChatId
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
                date: message.timestamp,
                imageData: message.imageData
            )

            // Save initial message to Core Data
            do {
                try await coreDataManager.saveMessage(chatMessage, toChatID: chatId, isStreaming: true)
            } catch {
                print("❌ Failed to save initial message to Core Data: \(error)")
            }

            // Update UI state - don't add empty message to array yet, just show waiting indicator
            if chatId == currentChatId {
                let newViewState = ChatViewState.chat(id: chatId, messages: messages, reconfiguringMessageID: nil, waitingState: .waitingForResponse)
                viewState = newViewState
                uiEventContinuation.yield(.viewStateChanged(newViewState))
                print("📊 ChatManager: messageStarted - showing waiting indicator, not adding empty message to UI yet")
            }

        case .messageUpdated(let message):
            print("🟡 ChatManager: Updating message with ID: \(message.responseId) for chat: \(chatId)")

            let responseMessage = OAChatMessage(
                id: message.responseId,
                role: OARole.assistant,
                content: message.content,
                date: message.timestamp,
                imageData: message.imageData
            )

            do {
                try await coreDataManager.updateMessage(with: responseMessage, chatId: chatId, isStreaming: true)
            } catch {
                print("⚠️ Failed to update message \(responseMessage.id) in Core Data: \(error)")
            }

            // Update UI state - add message to array on first content, update thereafter
            if chatId == currentChatId {
                // Check if we have actual content to display
                let hasContent = !responseMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                
                // Check if message already exists in local array
                let messageExists = messages.contains { $0.id == responseMessage.id }
                
                if hasContent && !messageExists {
                    // First time we have content - add message to array and transition to receiving
                    messages.append(responseMessage)
                    let newViewState = ChatViewState.chat(id: chatId, messages: messages, reconfiguringMessageID: responseMessage.id, waitingState: .receivingResponse)
                    viewState = newViewState
                    uiEventContinuation.yield(.viewStateChanged(newViewState))
                    print("📊 ChatManager: First content received - added message to UI and transitioned to receivingResponse")
                } else if hasContent && messageExists {
                    // Message exists and has content - update it
                    updateMessageInLocalArray(responseMessage)
                    let newViewState = ChatViewState.chat(id: chatId, messages: messages, reconfiguringMessageID: responseMessage.id, waitingState: .receivingResponse)
                    viewState = newViewState
                    uiEventContinuation.yield(.viewStateChanged(newViewState))
                    print("📊 ChatManager: Content updated - staying in receivingResponse")
                } else {
                    // No content yet - stay in waiting state
                    let newViewState = ChatViewState.chat(id: chatId, messages: messages, reconfiguringMessageID: nil, waitingState: .waitingForResponse)
                    viewState = newViewState
                    uiEventContinuation.yield(.viewStateChanged(newViewState))
                    print("📊 ChatManager: No content yet - staying in waitingForResponse")
                }
            }

        case .messageCompleted(let message):
            print("🟢 ChatManager: Completing message with ID: \(message.responseId) for chat: \(chatId)")

            let responseMessage = OAChatMessage(
                id: message.responseId,
                role: OARole.assistant,
                content: message.content,
                date: message.timestamp,
                imageData: message.imageData
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
                // Check if message exists in array - if not, add it (edge case handling)
                let messageExists = messages.contains { $0.id == responseMessage.id }
                let shouldReconfigureMessage: String?
                
                if !messageExists {
                    messages.append(responseMessage)
                    shouldReconfigureMessage = responseMessage.id
                    print("📊 ChatManager: messageCompleted - message didn't exist in array, added it")
                } else {
                    // Check if content actually changed from last streaming update
                    let existingMessage = messages.first { $0.id == responseMessage.id }
                    let contentChanged = existingMessage?.content != responseMessage.content
                    
                    updateMessageInLocalArray(responseMessage)
                    
                    // Only trigger reconfiguration if content actually changed
                    shouldReconfigureMessage = contentChanged ? responseMessage.id : nil
                    print("📊 ChatManager: messageCompleted - content changed: \(contentChanged), will reconfigure: \(shouldReconfigureMessage != nil)")
                }
                
                let newViewState = ChatViewState.chat(id: chatId, messages: messages, reconfiguringMessageID: shouldReconfigureMessage, waitingState: .none)
                viewState = newViewState
                uiEventContinuation.yield(.viewStateChanged(newViewState))
                print("📊 ChatManager: messageCompleted. Updated viewState to none waiting state with \(messages.count) messages")

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

        case .imageGenerationInProgress(let itemId):
            print("🎨 ChatManager: Image generation in progress for item: \(itemId)")

        case .imageGenerationGenerating(let itemId, let progress, let totalSteps):
            print("🎨 ChatManager: Image generation progress: \(progress)/\(totalSteps) for item: \(itemId)")

        case .imageGenerationPartialImage(let itemId, let imageData):
            print("🎨 ChatManager: Partial image received for item: \(itemId), size: \(imageData.count) bytes")

        case .imageGenerationCompleted(let itemId, let results):
            print("🎨 ChatManager: Image generation completed for item: \(itemId), \(results.count) images generated")

            // Extract image data from results
            if let newImageData = results.compactMap({ $0.imageData }).first {

                // Find the current assistant message being streamed
                if let lastMessageIndex = messages.lastIndex(where: { $0.role == OARole.assistant }) {
                    // Create updated message with generated images
                    var updatedMessage = messages[lastMessageIndex]
                    updatedMessage.updateGeneratedImage(newImageData)
                    messages[lastMessageIndex] = updatedMessage

                    // Trigger UI update
                    if chatId == currentChatId {
                        let newViewState = ChatViewState.chat(id: chatId, messages: messages, reconfiguringMessageID: updatedMessage.id, waitingState: .none)
                        viewState = newViewState
                        uiEventContinuation.yield(.viewStateChanged(newViewState))
                        print("🎨 ChatManager: Updated UI with generated image")
                    }
                }
            }
            //        case .annotationAdded(_, itemId: let itemId, contentIndex: let contentIndex):
            //            break
            //        case .functionCallArgumentsDelta(callId: let callId, delta: let delta):
            //            break
            //        case .functionCallArgumentsDone(callId: let callId, arguments: let arguments):
            //            break
            //        case .reasoningDelta(delta: let delta):
            //            break
            //        case .reasoningDone(reasoning: let reasoning):
            //            break
        default: break
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

    // MARK: - Errors

    private func handleStreamingError(_ error: StreamError, chatId: String) {
        if chatId == currentChatId {
            let errorString = "Streaming error in chat \(chatId): \(error)"
            print(errorString)

            // Extract user-friendly error message from API errors
            let userErrorMessage = extractUserFriendlyErrorMessage(from: error)

            // Remove any incomplete assistant message that was being streamed
            if let lastMessageIndex = messages.lastIndex(where: { $0.role == OARole.assistant && $0.content.isEmpty }) {
                messages.remove(at: lastMessageIndex)
            }

            // Update viewState to clear waiting state and show error alert
            let newViewState = ChatViewState.chat(id: chatId, messages: messages, reconfiguringMessageID: nil, waitingState: .none)
            viewState = newViewState
            uiEventContinuation.yield(.viewStateChanged(newViewState))
            uiEventContinuation.yield(.showErrorAlert(userErrorMessage))
        }
    }

    private func extractUserFriendlyErrorMessage(from error: StreamError) -> String {
        // Handle streaming errors
        switch error {
        case .serviceFailed(underlying: let error):
            return "Service failed error: \(error.localizedDescription)"
        case .networkError(description: let description, underlying: let error):
            return "Network error: \(description)"
        case .rateLimited:
            return "Rate limit exceeded. Please try again later."
        case .invalidContent(reason: let reason, underlying: let error):
            return "Invalid content in response: \(reason)"
        case .streamCancelled:
            return "Request was cancelled."
        case .maxRetriesExceeded(lastError: let error):
            return "Max retried exceeded. Error: \(error.lastError.localizedDescription). Attempt count: \(error.attempts)"
        case .encodingError(description: let description):
            return "Encoding error: \(description)"
        case .authenticationRequired(statusCode: let statusCode, description: let description, retryAfter: let retryAfter):
            return "Authentication required: \(description)"
        case .authorizationFailed(statusCode: let statusCode, description: let description):
            return "Authentication failed: \(description)"
        case .clientError(statusCode: let statusCode, description: let description, isRetryable: let isRetryable):
            return "Client error: \(description)"
        case .serverError(statusCode: let statusCode, description: let description, retryAfter: let retryAfter):
            return "Server error: \(description)"
        }
    }
}

// MARK: - Chat Title

extension OAChatManager {
    private func generateChatTitle(for chatId: String) async {
        guard let userMessage = messages.first?.content,
              let assistantMessage = messages.last?.content else { return }

        do {
            let titlePrompt = """
                         Based on this conversation, generate a concise, descriptive title (max 6 words):
                         
                         User: \(userMessage)
                         Assistant: \(assistantMessage)
                         
                         Title:
                         """
            let instructions = "Generate a short, descriptive title for this conversation. Respond with only the title, no additional text."

            let responseMessage = try await streamingCoordinator.sendNonStreamingMessage(
                messageText: titlePrompt,
                model: .gpt41nano,
                attachments: [],
                previousResponseId: nil,
                instructions: instructions,
                maxOutputTokens: 20,
                temperature: 0.3,
                webSearchEnabled: false,
                webSearchRequired: false,
                userLocation: nil,
                imageGenerationEnabled: false
            )
            let generatedTitle = responseMessage.content
            try await coreDataManager.updateChatTitle(chatId, title: generatedTitle)
        } catch {
            print("Failed to generate chat title: \(error)")
        }
    }

    private func shouldGenerateTitle() -> Bool {
        // Generate title only if we have exactly 2 messages (1 user + 1 assistant)
        return messages.count == 2 &&
        messages.first?.role == OARole.user &&
        messages.last?.role == OARole.assistant
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
