//
//  OACoreDataManager.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import CoreData
import Combine
import SwiftOpenAI

final class OACoreDataManager: @unchecked Sendable {

    @Published private(set) var chats: [OAChat] = []

    private let backgroundContext: NSManagedObjectContext

    private var counter: Int = 0

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

            // Assuming 'messages' is the relationship name on your 'Chat' entity
            // and it yields a Set of 'Message' (your Core Data Message entity)
            guard let messageMOs = chatMO.messages as? Set<Message> else {
                print("⚠️ No messages found or relationship not set up for chat: \(chatID)")
                return [] // No messages or relationship not set up as expected
            }

            print("🔍 Found \(messageMOs.count) message MOs for chat: \(chatID)")
            for messageMO in messageMOs {
                print("  - Message: Role=\(messageMO.role ?? "nil"), ID=\(messageMO.id ?? "nil"), Content length=\(messageMO.content?.count ?? 0)")
            }

            let unsortedMessages = messageMOs.compactMap { 
                let message = OAChatMessage(message: $0)
                if message == nil {
                    print("❌ Failed to create OAChatMessage from MO: Role=\(($0.role) ?? "nil"), ID=\($0.id ?? "nil")")
                }
                return message
            }
            print("✅ Successfully converted \(unsortedMessages.count) messages for chat: \(chatID)")
            return unsortedMessages.sorted(by: { $0.date < $1.date })
        }
    }

    func updateMessage(with messageId: String, chatId: String, content: String, date: Date) async throws {
            try await backgroundContext.perform {
                let chatFetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
                chatFetchRequest.predicate = NSPredicate(format: "id == %@", chatId as CVarArg)
                chatFetchRequest.fetchLimit = 1

                guard let chatMO = try self.backgroundContext.fetch(chatFetchRequest).first else {
                    throw OACoreDataError.chatNotFound
                }

                // Find the specific message within the chat's messages
                if let messages = chatMO.messages as? Set<Message>,
                   let messageToUpdate = messages.first(where: { $0.id == messageId }) {
                    // Update the message properties
                    messageToUpdate.content = content
                    messageToUpdate.date = date
                    // Update any other properties as needed

                    // Update the chat's date to reflect the latest message activity
                    chatMO.date = date

                    try self.backgroundContext.save()

                    // Optionally, update the @Published chats array if the chat's date change affects sorting
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
                    throw OACoreDataError.messageNotFound
                }
            }
        }

    func addMessage(_ message: OAChatMessage, toChatID chatID: String) async throws {
        print("🔵 Adding message to Core Data - Role: \(message.role.rawValue), ID: \(message.id), Content length: \(message.content.count)")
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
            messageMO.chatId = chatID // Set the chatId attribute
            // messageMO.chat = chatMO // This relationship is typically set by adding to the collection

            // 3. Add the new message to the chat's messages relationship
            // Replace "messages" if your relationship name is different.
            // This assumes Core Data generated an accessor like `addToMessages`.
            // If not, use: chatMO.mutableSetValue(forKey: "messages").add(messageMO)
            chatMO.addToMessages(messageMO)

            print("🔵 Created message MO - Role: \(messageMO.role ?? "nil"), ChatID: \(messageMO.chatId ?? "nil")")

            // 4. Update the chat's main date to the new message's date
            // This is useful for sorting chats by last activity.
            chatMO.date = message.date

            // 5. Save the context
            try self.backgroundContext.save()
            print("✅ Successfully saved message to Core Data - Role: \(message.role.rawValue)")

            // 6. Update the OAChat object in the @Published chats array
            // This ensures the sidebar reflects the new activity date and re-sorts if necessary.
            if let index = self.chats.firstIndex(where: { $0.id == chatID }) {
                let oldOAChat = self.chats[index]
                // Create a new OAChat instance with the updated date.
                // The 'messages' set within this OAChat instance remains empty as per lazy-loading design.
                let updatedOAChat = OAChat(id: oldOAChat.id,
                                           date: message.date, // Use the new message's date
                                           title: oldOAChat.title,
                                           provisionaryInputText: oldOAChat.provisionaryInputText,
                                           selectedModel: oldOAChat.selectedModel,
                                           messages: oldOAChat.messages) // Keep existing (empty) messages set

                self.chats[index] = updatedOAChat

                // Re-sort the chats array to maintain order (e.g., newest first by date)
                // This matches the sorting in fetchPersistedChats and newChat.
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

    func updateSelectedModelFor(_ chatId: String?, model: SwiftOpenAI.Model) async throws {
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
        print("🔄 Handling remote CloudKit changes")
        do {
            try await fetchPersistedChats()
            print("✅ Successfully refreshed chats from CloudKit")
        } catch {
            print("❌ Failed to refresh chats after remote changes: \(error)")
        }
    }
    
    func checkForUpdates() async {
        print("🔍 Checking for CloudKit updates")
        do {
            try await fetchPersistedChats()
            print("✅ Update check completed")
        } catch {
            print("❌ Failed to check for updates: \(error)")
        }
    }
    
    func refreshMessages(for chatID: String) async throws -> [OAChatMessage] {
        print("🔄 Refreshing messages for chat: \(chatID)")
        return try await fetchMessages(for: chatID)
    }
}
