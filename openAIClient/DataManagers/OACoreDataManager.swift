//
//  OACoreDataManager.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import CoreData
import Combine

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
        let fetchedChats = try await backgroundContext.perform {
            let req: NSFetchRequest<Chat> = Chat.fetchRequest()
            req.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            let chats = try self.backgroundContext.fetch(req)
            return chats.compactMap { OAChat(chat: $0) }
        }
        
        await MainActor.run {
            // Deduplicate chats by ID to handle CloudKit sync duplicates
            let uniqueChats = Dictionary(fetchedChats.map { ($0.id, $0) }, uniquingKeysWith: { latest, _ in latest })
            self.chats = Array(uniqueChats.values).sorted { $0.date > $1.date }
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
        }
        // Refresh chats after creation
        try await fetchPersistedChats()
    }

    func deleteChat(with id: String) async throws {
        try await backgroundContext.perform {
            let fetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            fetchRequest.fetchLimit = 1

            guard let chatManagedObject = try self.backgroundContext.fetch(fetchRequest).first else {
                throw OACoreDataError.chatNotFound
            }
            
            self.backgroundContext.delete(chatManagedObject)
            try self.backgroundContext.save()
        }
        // Refresh chats after deletion
        try await fetchPersistedChats()
    }

    func fetchMessages(for chatID: String) async throws -> [OAChatMessage] {
        try await backgroundContext.perform {
            let chatFetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            chatFetchRequest.predicate = NSPredicate(format: "id == %@", chatID as CVarArg)
            chatFetchRequest.fetchLimit = 1

            guard let chatMO = try self.backgroundContext.fetch(chatFetchRequest).first else {
                    throw OACoreDataError.chatNotFound
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

    func updateMessage(with messageId: String, chatId: String, content: String, date: Date, isStreaming: Bool? = nil) async throws {
        try await backgroundContext.perform {
            let chatFetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            chatFetchRequest.predicate = NSPredicate(format: "id == %@", chatId as CVarArg)
            chatFetchRequest.fetchLimit = 1

            guard let chatMO = try self.backgroundContext.fetch(chatFetchRequest).first else {
                throw OACoreDataError.chatNotFound
            }

            // Find the specific message within the chat's messages
            guard let messages = chatMO.messages as? Set<Message>,
                  let messageToUpdate = messages.first(where: { $0.id == messageId }) else {
                throw OACoreDataError.messageNotFound
            }
            
            // Update the message properties
            messageToUpdate.content = content
            messageToUpdate.date = date
            
            // Update streaming state if provided
            if let isStreaming = isStreaming {
                messageToUpdate.isStreaming = isStreaming
            }

            // Update the chat's date to reflect the latest message activity
            chatMO.date = date

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
                throw OACoreDataError.chatNotFound
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
        }
    }

    func updateChatTitle(_ chatId: String, title: String) async throws {
        try await backgroundContext.perform {
            let fetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", chatId as CVarArg)
            fetchRequest.fetchLimit = 1

            guard let chatMO = try self.backgroundContext.fetch(fetchRequest).first else {
                throw OACoreDataError.chatNotFound
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
