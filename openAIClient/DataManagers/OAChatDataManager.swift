//
// OAChatDataManager.swift
// openAIClient
//
// Created by Lucas on 29.05.25.
//


import Foundation
@preconcurrency import Combine
import SwiftUI
import UIKit

@MainActor
final class OAChatDataManager {
    private var responseProvider: OAResponseStreamProvider? = nil

//    private let conversation: Conversation?
    private var observationTask: Task<Void, Never>?

    private let coreDataManager: OACoreDataManager

    private var currentChatId: String? = nil
    var messages: [OAChatMessage] = []

    var onMessagesUpdated: ((_ reconfigureItemID: String?) -> Void)?

    @Published
    var selectedModel: OAModel
    
    // Track last save times for periodic streaming saves
    private var lastStreamingSaveTimes: [String: Date] = [:]
    private let streamingSaveInterval: TimeInterval = 1.0 // Save every 1 second during streaming
    
    // Background task management
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    private var activeStreamingMessages: Set<String> = []
    
    // Combine publishers for reactive persistence
    private var persistenceSubject = PassthroughSubject<PersistenceEvent, Never>()
    private var cancellables = Set<AnyCancellable>()
    
    // Final save guarantee
    private var pendingFinalSaves: [String: String] = [:] // messageId -> content

    init(coreDataManager: OACoreDataManager) {
        self.coreDataManager = coreDataManager
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "API_KEY") as? String else {
            self.selectedModel = .gpt41nano
            print("Error retrieving API_KEY")
            return
        }
        let configuration = URLSessionConfiguration.default
        let service = OAOpenAIServiceFactory.service(apiKey: apiKey, configuration: configuration)

        self.selectedModel = .gpt41nano
        self.responseProvider = OAResponseStreamProvider(service: service, model: self.selectedModel)
        
        setupReactivePersistence()
        setupAppLifecycleObservers()
        setupChatDeletionObserver()
     }

    deinit {
        observationTask?.cancel()
        cancellables.removeAll()
        
        // Clean up background task - store value to avoid self capture
        let taskId = backgroundTaskId
        if taskId != .invalid {
            Task { @MainActor in
                UIApplication.shared.endBackgroundTask(taskId)
            }
        }
    }

    func loadLatestChat() {
        if let latestChat = self.coreDataManager.chats.first {
            Task {
                await self.loadChat(with: latestChat.id)
            }
        }
    }

    func updateModel(_ model: OAModel) async {
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
        // Ensure any pending saves are completed before switching chats
        Task {
            await performFinalSaves()
        }

        self.lastStreamingSaveTimes.removeAll()
        self.activeStreamingMessages.removeAll()
        self.pendingFinalSaves.removeAll()

        guard let chatId else {
            self.currentChatId = nil
            // Clear streaming save tracking when changing chats
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
        if let responseMessage = responseProvider.messages.last, responseMessage.role == .assistant {
            let messageId = responseMessage.id.uuidString

            if let existingMessageIndex = self.messages.firstIndex(where: { $0.id == messageId }) {
                // Update existing message
                self.updateExistingMessage(with: messageId,
                                           at: existingMessageIndex,
                                           content: responseMessage.content,
                                           chatId: currentChatId,
                                           isStreaming: responseMessage.isStreaming)
            } else {
                // Create new assistant message only if content is not empty
                if !responseMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.createNewAssistant(message: responseMessage, currentChatId: currentChatId)
                }
            }
        }
    }

    private func createNewAssistant(message: OAResponseStreamProvider.OAResponseMessage, currentChatId: String) {
        print("Creating new assistant message with ID \(message.id)")
        
        // Avoid creating duplicate messages
        if self.messages.contains(where: { $0.id == message.id.uuidString }) {
            print("Warning: Assistant message with ID \(message.id) already exists")
            return
        }
        
        let messageId = message.id.uuidString
        
        let assistantMessage = OAChatMessage(
            id: messageId,
            role: .assistant,
            content: message.content,
            date: message.timestamp
        )
        self.messages.append(assistantMessage)
        
        // Track this as an active streaming message
        activeStreamingMessages.insert(messageId)
        
        // Start background task to protect against termination
        startBackgroundTask()

        // Save initial message to Core Data immediately when streaming starts
        Task(priority: .background) {
            do {
                try await self.coreDataManager.addMessage(assistantMessage, toChatID: currentChatId, isStreaming: true)
                print("✅ Successfully saved initial streaming message \(messageId) to Core Data")
            } catch {
                print("❌ Failed to save initial streaming message \(messageId) to Core Data: \(error)")
            }
        }
        
        // Notify UI for update
        self.onMessagesUpdated?(nil)
    }

    private func updateExistingMessage(with messageId: String, at index: Array.Index, content: String, chatId: String, isStreaming: Bool) {
        // Skip empty content updates during streaming
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedContent.isEmpty && isStreaming {
            return
        }

        var messageToUpdate = self.messages[index]
        messageToUpdate.update(with: content, date: messageToUpdate.date)
        self.messages[index] = messageToUpdate

        print("Message with ID \(messageId) updated locally. Content length: \(content.count), isStreaming: \(isStreaming)")

        // Always track the latest content for final save guarantee
        pendingFinalSaves[messageId] = content
        
        // Determine if we should save to Core Data immediately
        let shouldSave: Bool
        if !isStreaming {
            // Always save when streaming is complete
            shouldSave = true
            // Remove from periodic save tracking
            lastStreamingSaveTimes.removeValue(forKey: messageId)
            activeStreamingMessages.remove(messageId)
            // End background task if no more active streaming messages
            if activeStreamingMessages.isEmpty {
                Task {
                    await endBackgroundTaskAsync()
                }
            }
        } else {
            // Check if enough time has passed for periodic save during streaming
            let lastSaveTime = lastStreamingSaveTimes[messageId] ?? Date.distantPast
            let currentTime = Date.now
            shouldSave = currentTime.timeIntervalSince(lastSaveTime) >= streamingSaveInterval
        }

        if shouldSave {
            // Update last save time for this message
            if isStreaming {
                lastStreamingSaveTimes[messageId] = Date.now
                // Send streaming update event
                persistenceSubject.send(.streamingUpdate(messageId: messageId, content: content))
            } else {
                // Send completion event for final save
                persistenceSubject.send(.messageCompleted(messageId: messageId, content: content))
            }
            
            Task(priority: .background) {
                do {
                    // Try to update first, if that fails, create new message
                    try await self.coreDataManager.updateMessage(
                        with: messageId,
                        chatId: chatId,
                        content: content,
                        date: messageToUpdate.date,
                        isStreaming: isStreaming
                    )
                    print("✅ Successfully updated message \(messageId) in Core Data (streaming: \(isStreaming))")
                } catch {
                    // If update fails (message doesn't exist), create it
                    do {
                        let assistantMessage = OAChatMessage(
                            id: messageId,
                            role: .assistant,
                            content: content,
                            date: messageToUpdate.date
                        )
                        try await self.coreDataManager.addMessage(assistantMessage, toChatID: chatId, isStreaming: isStreaming)
                        print("✅ Successfully created message \(messageId) in Core Data (streaming: \(isStreaming))")
                    } catch {
                        print("❌ Failed to create message \(messageId) in Core Data: \(error)")
                    }
                }
            }
        }

        // Notify UI for updates
        self.onMessagesUpdated?(messageId)
        
        // Track final content for guaranteed save
        if !isStreaming {
            pendingFinalSaves[messageId] = content
            persistenceSubject.send(.messageCompleted(messageId: messageId, content: content))
        }
    }
    
    // MARK: - Reactive Persistence Setup
    
    private func setupReactivePersistence() {
        // Debounce persistence events to avoid excessive saves
        persistenceSubject
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] event in
                Task {
                    await self?.handlePersistenceEvent(event)
                }
            }
            .store(in: &cancellables)
    }
    
    private func handlePersistenceEvent(_ event: PersistenceEvent) async {
        switch event {
        case .messageCompleted(let messageId, let content):
            await ensureMessagePersisted(messageId: messageId, content: content)
        case .streamingUpdate(let messageId, let content):
            await saveStreamingUpdate(messageId: messageId, content: content)
        }
    }
    
    private func ensureMessagePersisted(messageId: String, content: String) async {
        guard let currentChatId = self.currentChatId else { return }
        
        do {
            try await self.coreDataManager.updateMessage(
                with: messageId,
                chatId: currentChatId,
                content: content,
                date: Date.now,
                isStreaming: false
            )
            
            // Remove from pending saves once confirmed
            pendingFinalSaves.removeValue(forKey: messageId)
            activeStreamingMessages.remove(messageId)
            
            print("✅ Final message save confirmed for ID: \(messageId)")
        } catch {
            print("❌ Failed to ensure message persistence for ID: \(messageId), error: \(error)")
        }
    }
    
    private func saveStreamingUpdate(messageId: String, content: String) async {
        guard let currentChatId = self.currentChatId else { return }
        
        do {
            try await self.coreDataManager.updateMessage(
                with: messageId,
                chatId: currentChatId,
                content: content,
                date: Date.now,
                isStreaming: true
            )
            print("✅ Streaming update saved for ID: \(messageId)")
        } catch {
            print("❌ Failed to save streaming update for ID: \(messageId), error: \(error)")
        }
    }
    
    // MARK: - App Lifecycle Handling
    
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleAppWillResignActive()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleAppDidEnterBackground()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleAppWillTerminate()
            }
        }
    }
    
    private func handleAppWillResignActive() async {
        print("🔄 App will resign active - ensuring message persistence")
        await performFinalSaves()
    }
    
    private func handleAppDidEnterBackground() async {
        print("🔄 App entered background - starting background task")
        startBackgroundTask()
        await performFinalSaves()
    }
    
    private func handleAppWillTerminate() async {
        print("🔄 App will terminate - performing emergency saves")
        await performFinalSaves()
    }
    
    // MARK: - Background Task Management
    
    private func startBackgroundTask() {
        guard backgroundTaskId == .invalid else { return }
        
        Task { @MainActor in
            self.backgroundTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.endBackgroundTaskAsync()
                }
            }
        }
    }
    
    @MainActor
    private func endBackgroundTaskAsync() async {
        guard backgroundTaskId != .invalid else { return }
        
        UIApplication.shared.endBackgroundTask(backgroundTaskId)
        backgroundTaskId = .invalid
    }
    
    // MARK: - Final Save Guarantee
    
    private func performFinalSaves() async {
        print("🔄 Performing final saves for \(pendingFinalSaves.count) messages")
        
        let saves = pendingFinalSaves
        pendingFinalSaves.removeAll()
        
        await withTaskGroup(of: Void.self) { group in
            for (messageId, content) in saves {
                group.addTask {
                    await self.ensureMessagePersisted(messageId: messageId, content: content)
                }
            }
        }
        
        // Also save any currently active streaming messages
        let activeMessages = activeStreamingMessages
        activeStreamingMessages.removeAll()
        
        await withTaskGroup(of: Void.self) { group in
            for messageId in activeMessages {
                if let messageIndex = self.messages.firstIndex(where: { $0.id == messageId }) {
                    let content = self.messages[messageIndex].content
                    group.addTask {
                        await self.ensureMessagePersisted(messageId: messageId, content: content)
                    }
                }
            }
        }
        
        print("✅ Final saves completed")
    }
    
    // MARK: - Chat Deletion Observer
    
    private func setupChatDeletionObserver() {
        coreDataManager.$chats
            .receive(on: DispatchQueue.main)
            .sink { [weak self] chats in
                guard let self = self, let currentChatId = self.currentChatId else { return }
                
                // Check if the currently selected chat still exists
                let chatExists = chats.contains { $0.id == currentChatId }
                
                if !chatExists {
                    print("🗑️ Currently selected chat \(currentChatId) was deleted, clearing chat view")
                    self.clearCurrentChat()
                }
            }
            .store(in: &cancellables)
    }
    
    private func clearCurrentChat() {
        self.currentChatId = nil
        self.messages = []
        self.onMessagesUpdated?(nil)
    }
}

// MARK: - Persistence Event Types

private enum PersistenceEvent {
    case messageCompleted(messageId: String, content: String)
    case streamingUpdate(messageId: String, content: String)
}
