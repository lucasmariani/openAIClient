//
//  OACoreDataManager.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import CoreData
import Observation

// MARK: - Core Data Change Delegate

@MainActor
protocol OACoreDataManagerDelegate: AnyObject {
    func coreDataManagerDidUpdateChats(_ chats: [OAChat])
}

final class OACoreDataManager: @unchecked Sendable {

    private var chats: [OAChat] = []
    weak var delegate: OACoreDataManagerDelegate?
    
    // MARK: - Public Access
    
    func getCurrentChats() -> [OAChat] {
        return chats
    }

    private let backgroundContext: NSManagedObjectContext

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
        // Use modern background task pattern
        let fetchedChats = try await OACoreDataStack.shared.performBackgroundTask { context in
            let req: NSFetchRequest<Chat> = Chat.fetchRequest()
            req.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            let chats = try context.fetch(req)
            return chats.compactMap { OAChat(chat: $0) }
        }
        
        await MainActor.run {
            // Deduplicate chats by ID to handle CloudKit sync duplicates
            let uniqueChats = Dictionary(fetchedChats.map { ($0.id, $0) }, uniquingKeysWith: { latest, _ in latest })
            self.chats = Array(uniqueChats.values).sorted { $0.date > $1.date }
            self.delegate?.coreDataManagerDidUpdateChats(self.chats)
        }
    }

    func newChat() async throws {
        let chatDate = Date.now
        
        // Use modern background task pattern with automatic save
        try await OACoreDataStack.shared.performBackgroundTask { context in
            let chat = Chat(context: context)
            chat.id = UUID().uuidString
            chat.date = chatDate
            chat.title = "New Chat \(Self.formatChatTimestamp(chatDate))"
            // Save is handled automatically by performBackgroundTask
        }
        
        // Refresh chats after creation
        try await fetchPersistedChats()
    }
    
    private static func formatChatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    func deleteChat(with id: String) async throws {
        try await backgroundContext.perform {
            let fetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            fetchRequest.fetchLimit = 1

            guard let chatManagedObject = try self.backgroundContext.fetch(fetchRequest).first else {
                throw StructuredError.chatNotFound(chatId: id, operation: "deleteChat")
            }
            
            self.backgroundContext.delete(chatManagedObject)
            try self.backgroundContext.save()
        }
        // Refresh chats after deletion
        try await fetchPersistedChats()
    }
    
    func deleteChats(with ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        
        // Use modern batch delete for better performance
        let deletedObjectIDs = try await OACoreDataStack.shared.performBatchDelete(
            entity: Chat.self,
            predicateFormat: "id IN %@",
            arguments: [ids]
        )
        
        print("✅ Batch deleted \(deletedObjectIDs.count) chats")
        
        // Refresh chats after batch deletion
        try await fetchPersistedChats()
    }

    func fetchMessages(for chatID: String) async throws -> [OAChatMessage] {
        try await backgroundContext.perform {
            let chatFetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            chatFetchRequest.predicate = NSPredicate(format: "id == %@", chatID as CVarArg)
            chatFetchRequest.fetchLimit = 1

            guard let chatMO = try self.backgroundContext.fetch(chatFetchRequest).first else {
                    throw StructuredError.chatNotFound(chatId: chatID, operation: "fetchMessages")
            }

            // Use a proper fetch request with sort descriptors instead of relationship set
            let messageFetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
            messageFetchRequest.predicate = NSPredicate(format: "chat == %@", chatMO)
            // Sort by date first, then by ID as secondary sort for deterministic ordering
            messageFetchRequest.sortDescriptors = [
                NSSortDescriptor(key: "date", ascending: true)
            ]

            let messageMOs = try self.backgroundContext.fetch(messageFetchRequest)

            let sortedMessages = messageMOs.compactMap {
                let message = OAChatMessage(message: $0)
                return message
            }
            
            return sortedMessages
        }
    }

    func updateMessage(with chatMessage: OAResponseMessage, chatId: String, isStreaming: Bool? = nil) async throws {
        try await backgroundContext.perform {
            let chatFetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            chatFetchRequest.predicate = NSPredicate(format: "id == %@", chatId as CVarArg)
            chatFetchRequest.fetchLimit = 1

            guard let chatMO = try self.backgroundContext.fetch(chatFetchRequest).first else {
                throw StructuredError.chatNotFound(chatId: chatId, operation: "updateMessage")
            }

            // Find the specific message within the chat's messages
            guard let messages = chatMO.messages as? Set<Message>,
                  let messageToUpdate = messages.first(where: { $0.id == chatMessage.responseId }) else {
                throw StructuredError.messageNotFound(messageId: chatMessage.responseId, chatId: chatId, operation: "updateMessage")
            }

            // Update the message properties
            messageToUpdate.content = chatMessage.content
            messageToUpdate.date = chatMessage.timestamp

            // Update streaming state if provided
            if let isStreaming = isStreaming {
                messageToUpdate.isStreaming = isStreaming
            }

            // Update the chat's date to reflect the latest message activity
            chatMO.date = chatMessage.timestamp

            try self.backgroundContext.save()
        }
    }

    func addMessage(_ message: OAChatMessage, toChatID chatID: String, isStreaming: Bool = false) async throws {
        try await backgroundContext.perform {
            // Fetch the Chat Managed Object
            let chatFetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            chatFetchRequest.predicate = NSPredicate(format: "id == %@", chatID as CVarArg)
            chatFetchRequest.fetchLimit = 1

            guard let chatMO = try self.backgroundContext.fetch(chatFetchRequest).first else {
                throw StructuredError.chatNotFound(chatId: chatID, operation: "addMessage")
            }

            // Create new Message Managed Object
            let messageMO = Message(context: self.backgroundContext)
            messageMO.id = message.id
            messageMO.role = message.role.rawValue
            messageMO.content = message.content
            messageMO.date = message.date
            messageMO.chatId = chatID
            messageMO.isStreaming = isStreaming // i don't think i need to store this in CoreData.

            // Add the new message to the chat's messages relationship
            chatMO.addToMessages(messageMO)

            // Update the chat's main date to the new message's date
            chatMO.date = message.date

            try self.backgroundContext.save()
        }
    }

    func updateProvisionalInputText(for chatID: String, text: String?) async throws {
        try await backgroundContext.perform {
            let fetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", chatID as CVarArg)
            fetchRequest.fetchLimit = 1

            guard let chatMO = try self.backgroundContext.fetch(fetchRequest).first else {
                throw StructuredError.chatNotFound(chatId: chatID, operation: "updateProvisionaryInputText")
            }

            chatMO.provisionaryInputText = text
            try self.backgroundContext.save()
        }
    }

    func updateSelectedModelFor(_ chatId: String?, model: OAModel) async throws {
        guard let chatId else { return }
        try await backgroundContext.perform {
            let fetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", chatId as CVarArg)
            fetchRequest.fetchLimit = 1

            guard let chatMO = try self.backgroundContext.fetch(fetchRequest).first else {
                throw StructuredError.chatNotFound(chatId: chatId, operation: "updateSelectedModelFor")
            }

            chatMO.selectedModel = model.value
            try self.backgroundContext.save()
        }
    }

    func updateChatTitle(_ chatId: String, title: String) async throws {
        try await backgroundContext.perform {
            let fetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", chatId as CVarArg)
            fetchRequest.fetchLimit = 1

            guard let chatMO = try self.backgroundContext.fetch(fetchRequest).first else {
                throw StructuredError.chatNotFound(chatId: chatId, operation: "updateChatTitle")
            }

            chatMO.title = title
            try self.backgroundContext.save()
        }
        try await fetchPersistedChats()
    }
    
    // MARK: - Sync Methods
    
    @MainActor
    private func handleRemoteChanges() async {
        do {
            try await self.fetchPersistedChats()
        } catch {
            print("❌ Failed to refresh chats after remote changes: \(error)")
        }
    }
}
