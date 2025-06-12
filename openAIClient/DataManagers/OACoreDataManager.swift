//
//  OACoreDataManager.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import CoreData
import Combine
import UIKit

final class OACoreDataManager: @unchecked Sendable {

    @Published private(set) var chats: [OAChat] = []

    private let backgroundContext: NSManagedObjectContext

    private var counter: Int = 0
    
    // Combine publishers for reactive operations
    private let saveCompletionSubject = PassthroughSubject<String, Error>()
    var saveCompletionPublisher: AnyPublisher<String, Error> {
        saveCompletionSubject.eraseToAnyPublisher()
    }

    init() {
        backgroundContext = OACoreDataStack.shared.container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        Task {
            try? await self.fetchPersistedChats()
        }
        
        // Listen for CloudKit remote changes
        NotificationCenter.default.addObserver(
            forName: .cloudKitDataChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleRemoteChanges()
            }
        }
    }

    func fetchPersistedChats() async throws {
        try await backgroundContext.perform {
            let req: NSFetchRequest<Chat> = Chat.fetchRequest()
            req.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            let chats = try self.backgroundContext.fetch(req)
            self.chats = chats.compactMap { OAChat(chat: $0) }
        }
    }

    func newChat() async throws {
        try await backgroundContext.perform {
            self.counter += 1
            let chat = Chat(context: self.backgroundContext)
            chat.id = UUID().uuidString
            chat.date = .now
            chat.title = "Title \(self.counter)"
            try self.backgroundContext.save()
            // After saving, re-fetch or append to ensure the @Published property is updated
            // For simplicity, re-fetching.
            // Consider more granular updates if performance becomes an issue.
            guard let newOAChat = OAChat(chat: chat) else { return }

            // Prepend the new chat to maintain sort order (newest first)
            // and publish the change.
            var updatedChats = self.chats
            updatedChats.insert(newOAChat, at: 0)
            self.chats = updatedChats // This will publish the change
        }
    }

    func deleteChat(with id: String) async throws {
        try await backgroundContext.perform {
            let fetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            fetchRequest.fetchLimit = 1 // Expecting one chat per ID

            if let chatManagedObject = try self.backgroundContext.fetch(fetchRequest).first {
                // Delete from Core Data
                self.backgroundContext.delete(chatManagedObject)
                try self.backgroundContext.save()

                // After successful Core Data deletion, update the @Published array
                var currentChats = self.chats
                currentChats.removeAll { $0.id == id }
                self.chats = currentChats
            } else {
                // Chat not found in Core Data.
                // You might want to throw an error or log this.
                // For robustness, ensure it's removed from the local array if it exists there.
                print("Chat with ID \(id) not found in Core Data. Removing from local array if present.")
                var currentChats = self.chats
                let initialCount = currentChats.count
                currentChats.removeAll { $0.id == id }
                if currentChats.count < initialCount {
                    self.chats = currentChats // Publish if it was indeed in the array
                }
                // Optionally throw an error if not found is critical
                throw OACoreDataError.chatNotFound
            }
        }
    }

    func fetchMessages(for chatID: String) async throws -> [OAChatMessage] {
        try await backgroundContext.perform {
            let chatFetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            chatFetchRequest.predicate = NSPredicate(format: "id == %@", chatID as CVarArg)
            chatFetchRequest.fetchLimit = 1

            guard let chatMO = try self.backgroundContext.fetch(chatFetchRequest).first else {
                print("❌ Chat not found when fetching messages for ID: \(chatID)")
                throw OACoreDataError.chatNotFound
            }

            // Use a proper fetch request with sort descriptors instead of relationship set
            let messageFetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
            messageFetchRequest.predicate = NSPredicate(format: "chat == %@", chatMO)
            // Sort by date first, then by ID as secondary sort for deterministic ordering
            messageFetchRequest.sortDescriptors = [
                NSSortDescriptor(key: "date", ascending: true),
                NSSortDescriptor(key: "id", ascending: true)
            ]

            let messageMOs = try self.backgroundContext.fetch(messageFetchRequest)
            print("🔍 Found \(messageMOs.count) message MOs for chat: \(chatID) (sorted by date)")

            messageMOs.forEach { message in
                print("fetchMessages (coreDataManager) | Date: \(message.date?.timeIntervalSince1970). Role: \(message.role)")
            }

            let sortedMessages = messageMOs.compactMap {
                let message = OAChatMessage(message: $0)
                if message == nil {
                    print("❌ Failed to create OAChatMessage from MO: Role=\(($0.role) ?? "nil"), ID=\($0.id ?? "nil")")
                }
                return message
            }
            
            print("✅ Successfully converted \(sortedMessages.count) messages for chat: \(chatID)")
            return sortedMessages
        }
    }

    func updateMessage(with messageId: String, chatId: String, content: String, date: Date, isStreaming: Bool? = nil) async throws {
        try await backgroundContext.perform {
            let chatFetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            chatFetchRequest.predicate = NSPredicate(format: "id == %@", chatId as CVarArg)
            chatFetchRequest.fetchLimit = 1

            guard let chatMO = try self.backgroundContext.fetch(chatFetchRequest).first else {
                print("❌ Chat not found for message update: \(chatId)")
                throw OACoreDataError.chatNotFound
            }

            // Find the specific message within the chat's messages
            if let messages = chatMO.messages as? Set<Message>,
               let messageToUpdate = messages.first(where: { $0.id == messageId }) {
                
                // Log the update for debugging
                let oldContent = messageToUpdate.content ?? ""
                print("ℹ️ Updating message \(messageId): content length \(oldContent.count) -> \(content.count), streaming: \(isStreaming ?? messageToUpdate.isStreaming)")
                
                // Update the message properties
                messageToUpdate.content = content
                messageToUpdate.date = date
                
                // Update streaming state if provided
                if let isStreaming = isStreaming {
                    messageToUpdate.isStreaming = isStreaming
                }

                // Update the chat's date to reflect the latest message activity
                chatMO.date = date
                print("updateMessage coreDataManager | Date: \(date.timeIntervalSince1970) role: \(messageToUpdate.role)")

                try self.backgroundContext.save()
                
                // Notify completion
                self.saveCompletionSubject.send(messageId)
                print("✅ Message \(messageId) successfully updated and saved")

                // Update the @Published chats array if the chat's date change affects sorting
                if let index = self.chats.firstIndex(where: { $0.id == chatId }) {
                    let oldOAChat = self.chats[index]
                    let updatedOAChat = OAChat(id: oldOAChat.id,
                                               date: date, // Use the updated date
                                               title: oldOAChat.title,
                                               provisionaryInputText: oldOAChat.provisionaryInputText,
                                               selectedModel: oldOAChat.selectedModel,
                                               messages: oldOAChat.messages)
                    self.chats[index] = updatedOAChat
                    self.chats.sort(by: { $0.date > $1.date })
                }

            } else {
                print("❌ Message not found for update: \(messageId) in chat \(chatId)")
                throw OACoreDataError.messageNotFound
            }
        }
    }

    func addMessage(_ message: OAChatMessage, toChatID chatID: String, isStreaming: Bool = false) async throws {
        print("🔵 Adding message to Core Data - Role: \(message.role.rawValue), ID: \(message.id), Content length: \(message.content.count), Streaming: \(isStreaming)")
        try await backgroundContext.perform {
            // 1. Fetch the Chat Managed Object
            let chatFetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            chatFetchRequest.predicate = NSPredicate(format: "id == %@", chatID as CVarArg)
            chatFetchRequest.fetchLimit = 1

            guard let chatMO = try self.backgroundContext.fetch(chatFetchRequest).first else {
                print("❌ Chat not found for ID: \(chatID)")
                throw OACoreDataError.chatNotFound
            }

            // 2. Create new Message Managed Object
            let messageMO = Message(context: self.backgroundContext)
            messageMO.id = message.id
            messageMO.role = message.role.rawValue
            messageMO.content = message.content
            messageMO.date = message.date
            messageMO.chatId = chatID
            messageMO.isStreaming = isStreaming

            print("addMessage coreDataManager | Date: \(message.date.timeIntervalSince1970) role: \(message.role)")

            // 3. Add the new message to the chat's messages relationship
            chatMO.addToMessages(messageMO)

            print("🔵 Created message MO - Role: \(messageMO.role ?? "nil"), ChatID: \(messageMO.chatId ?? "nil"), Streaming: \(messageMO.isStreaming)")

            // 4. Update the chat's main date to the new message's date
            chatMO.date = message.date

            // 5. Save the context with retry logic
            var saveAttempts = 0
            let maxRetries = 3
            
            while saveAttempts < maxRetries {
                do {
                    try self.backgroundContext.save()
                    self.saveCompletionSubject.send(message.id)
                    print("✅ Successfully saved message to Core Data - Role: \(message.role.rawValue) (attempt \(saveAttempts + 1))")
                    break
                } catch {
                    saveAttempts += 1
                    print("⚠️ Save attempt \(saveAttempts) failed for message \(message.id): \(error)")
                    
                    if saveAttempts >= maxRetries {
                        self.saveCompletionSubject.send(completion: .failure(error))
                        throw error
                    }
                    
                    // Brief delay before retry (using Thread.sleep since we're in a sync context)
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }

            // 6. Update the OAChat object in the @Published chats array
            if let index = self.chats.firstIndex(where: { $0.id == chatID }) {
                let oldOAChat = self.chats[index]
                let updatedOAChat = OAChat(id: oldOAChat.id,
                                           date: message.date,
                                           title: oldOAChat.title,
                                           provisionaryInputText: oldOAChat.provisionaryInputText,
                                           selectedModel: oldOAChat.selectedModel,
                                           messages: oldOAChat.messages)

                self.chats[index] = updatedOAChat
                self.chats.sort(by: { $0.date > $1.date })
            }
        }
    }

    func updateProvisionaryInputText(for chatID: String, text: String?) async throws {
        try await backgroundContext.perform {
            let fetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", chatID as CVarArg)
            fetchRequest.fetchLimit = 1

            guard let chatMO = try self.backgroundContext.fetch(fetchRequest).first else {
                throw OACoreDataError.chatNotFound
            }

            chatMO.provisionaryInputText = text
            try self.backgroundContext.save()

            // Update the OAChat in the @Published chats array
            if let index = self.chats.firstIndex(where: { $0.id == chatID }) {
                let oldOAChat = self.chats[index]
                let updatedOAChat = OAChat(id: oldOAChat.id,
                                           date: oldOAChat.date,
                                           title: oldOAChat.title,
                                           provisionaryInputText: text,
                                           selectedModel: oldOAChat.selectedModel,
                                           messages: oldOAChat.messages)
                self.chats[index] = updatedOAChat
            }
        }
    }

    func updateSelectedModelFor(_ chatId: String?, model: OAModel) async throws {
        guard let chatId else { return }
        try await backgroundContext.perform {
            let fetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", chatId as CVarArg)
            fetchRequest.fetchLimit = 1

            guard let chatMO = try self.backgroundContext.fetch(fetchRequest).first else {
                throw OACoreDataError.chatNotFound
            }

            chatMO.selectedModel = model.value
            try self.backgroundContext.save()

            // Update the OAChat in the @Published chats array
            if let index = self.chats.firstIndex(where: { $0.id == chatId }) {
                let oldOAChat = self.chats[index]
                let updatedOAChat = OAChat(id: oldOAChat.id,
                                           date: oldOAChat.date,
                                           title: oldOAChat.title,
                                           provisionaryInputText: oldOAChat.provisionaryInputText,
                                           selectedModel: model,
                                           messages: oldOAChat.messages)
                self.chats[index] = updatedOAChat
            }
        }
    }
    
    // MARK: - Sync Methods
    
    @MainActor
    private func handleRemoteChanges() async {
//        print("🔄 Handling remote CloudKit changes")
        do {
            try await self.fetchPersistedChats()
//            print("✅ Successfully refreshed chats from CloudKit")
        } catch {
            print("❌ Failed to refresh chats after remote changes: \(error)")
        }
    }
    
    func checkForUpdates() async {
        print("🔍 Checking for CloudKit updates")
        do {
            try await self.fetchPersistedChats()
            print("✅ Update check completed")
        } catch {
            print("❌ Failed to check for updates: \(error)")
        }
    }
    
    func refreshMessages(for chatID: String) async throws -> [OAChatMessage] {
        print("🔄 Refreshing messages for chat: \(chatID)")
        return try await self.fetchMessages(for: chatID)
    }
}
