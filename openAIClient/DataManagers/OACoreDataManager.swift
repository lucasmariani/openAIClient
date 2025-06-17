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
protocol OACoreDataManagerDelegate: AnyObject, Sendable {
    func coreDataManagerDidUpdateChats(_ chats: [OAChat])
}

// MARK: - Core Data Manager with Swift 6 Strict Concurrency

@CoreDataActor
final class OACoreDataManager {

    // Thread-safe storage for chats - only accessed from CoreDataActor
    private var chats: [OAChat] = []

    // Delegate must be accessed through MainActor boundary
    private weak var _delegate: (any OACoreDataManagerDelegate)?

    // MARK: - Public Access

    /// Returns current chats - safe to call from CoreDataActor
    func getCurrentChats() -> [OAChat] {
        return chats
    }

    /// Sets delegate with proper MainActor isolation
    func setDelegate(_ delegate: (any OACoreDataManagerDelegate)?) {
        _delegate = delegate
    }

    init() {
        Task {
            try? await self.fetchPersistedChats()
        }

        // Listen for CloudKit remote changes
        // Use unowned self to break reference cycle and avoid capture issues
        NotificationCenter.default.addObserver(
            forName: .cloudKitDataChanged,
            object: nil,
            queue: .main
        ) { [unowned self] _ in
            Task {
                await self.handleRemoteChanges()
            }
        }
    }

    func fetchPersistedChats() async throws {
        // Use the new CoreDataActor operation pattern
        let fetchedChats = try await CoreDataActor.performOperation { context in
            let req: NSFetchRequest<Chat> = Chat.fetchRequest()
            req.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            let chats = try context.fetch(req)
            return chats.compactMap { OAChat(chat: $0) }
        }

        // Update local state within CoreDataActor
        let uniqueChats = Dictionary(fetchedChats.map { ($0.id, $0) }, uniquingKeysWith: { latest, _ in latest })
        self.chats = Array(uniqueChats.values).sorted { $0.date > $1.date }

        // Notify delegate on MainActor with proper isolation
        await self.notifyDelegateOfChatUpdate()
    }

    /// Helper to properly transfer delegate calls to MainActor
    private func notifyDelegateOfChatUpdate() async {
        let currentChats = self.chats
        let delegate = self._delegate

        await MainActor.run {
            delegate?.coreDataManagerDidUpdateChats(currentChats)
        }
    }

    func newChat() async throws {
        let chatDate = Date.now
        let formattedTimestamp = Self.formatChatTimestamp(chatDate)

        // Use new CoreDataActor operation pattern
        try await CoreDataActor.performOperation { context in
            let chat = Chat(context: context)
            chat.id = UUID().uuidString
            chat.date = chatDate
            chat.title = "New Chat \(formattedTimestamp)"
            return () // Explicit return for Sendable compliance
        }

        // Refresh chats after creation
        try await fetchPersistedChats()
    }

    nonisolated private static func formatChatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    func deleteChat(with id: String) async throws {
        try await CoreDataActor.performOperation { context in
            let fetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            fetchRequest.fetchLimit = 1

            guard let chatManagedObject = try context.fetch(fetchRequest).first else {
                throw StructuredError.chatNotFound(chatId: id, operation: "deleteChat")
            }

            context.delete(chatManagedObject)
            return () // Explicit return for Sendable compliance
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
        return try await CoreDataActor.performOperation { context in
            let chatFetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            chatFetchRequest.predicate = NSPredicate(format: "id == %@", chatID as CVarArg)
            chatFetchRequest.fetchLimit = 1

            guard let chatMO = try context.fetch(chatFetchRequest).first else {
                throw StructuredError.chatNotFound(chatId: chatID, operation: "fetchMessages")
            }

            // Use a proper fetch request with sort descriptors instead of relationship set
            let messageFetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
            messageFetchRequest.predicate = NSPredicate(format: "chat == %@", chatMO)
            // Sort by date first, then by ID as secondary sort for deterministic ordering
            messageFetchRequest.sortDescriptors = [
                NSSortDescriptor(key: "date", ascending: true)
            ]

            let messageMOs = try context.fetch(messageFetchRequest)

            let sortedMessages = messageMOs.compactMap {
                let message = OAChatMessage(message: $0)
                return message
            }

            return sortedMessages
        }
    }

    func updateMessage(with chatMessage: OAChatMessage, chatId: String, isStreaming: Bool? = nil) async throws {
        try await CoreDataActor.performOperation { context in
            let chatFetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            chatFetchRequest.predicate = NSPredicate(format: "id == %@", chatId as CVarArg)
            chatFetchRequest.fetchLimit = 1

            guard let chatMO = try context.fetch(chatFetchRequest).first else {
                throw StructuredError.chatNotFound(chatId: chatId, operation: "updateMessage")
            }

            // Find the specific message within the chat's messages
            guard let messages = chatMO.messages as? Set<Message>,
                  let messageToUpdate = messages.first(where: { $0.id == chatMessage.id }) else {
                throw StructuredError.messageNotFound(messageId: chatMessage.id, chatId: chatId, operation: "updateMessage")
            }

            // Update the message properties
            messageToUpdate.content = chatMessage.content
            messageToUpdate.date = chatMessage.date

            // Update streaming state if provided
            if let isStreaming = isStreaming {
                messageToUpdate.isStreaming = isStreaming
            }

            // Update the chat's date to reflect the latest message activity
            chatMO.date = chatMessage.date

            return () // Explicit return for Sendable compliance
        }
    }

    func saveMessage(_ message: OAChatMessage, toChatID chatID: String, isStreaming: Bool = false) async throws {
        try await CoreDataActor.performOperation { context in
            // Fetch the Chat Managed Object
            let chatFetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            chatFetchRequest.predicate = NSPredicate(format: "id == %@", chatID as CVarArg)
            chatFetchRequest.fetchLimit = 1

            guard let chatMO = try context.fetch(chatFetchRequest).first else {
                throw StructuredError.chatNotFound(chatId: chatID, operation: "addMessage")
            }

            // Create new Message Managed Object
            let messageMO = Message(context: context)
            messageMO.id = message.id
            messageMO.role = message.role.rawValue
            messageMO.content = message.content
            messageMO.date = message.date
            messageMO.chatId = chatID
            messageMO.isStreaming = isStreaming // i don't think i need to store this in CoreData.

            // Save attachments if they exist
//            for attachment in message.attachments {
//                let attachmentMO = Attachment(context: context)
//                attachmentMO.id = attachment.id
//                attachmentMO.filename = attachment.filename
//                attachmentMO.mimeType = attachment.mimeType
//                attachmentMO.data = attachment.data
//                attachmentMO.thumbnailData = attachment.thumbnailData
//                
//                // Add the attachment to the message's attachments relationship
//                messageMO.addToAttachments(attachmentMO)
//            }

            // Add the new message to the chat's messages relationship
            chatMO.addToMessages(messageMO)

            // Update the chat's main date to the new message's date
            chatMO.date = message.date

            return () // Explicit return for Sendable compliance
        }
    }

    func updateProvisionalInputText(for chatID: String, text: String?) async throws {
        try await CoreDataActor.performOperation { context in
            let fetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", chatID as CVarArg)
            fetchRequest.fetchLimit = 1

            guard let chatMO = try context.fetch(fetchRequest).first else {
                throw StructuredError.chatNotFound(chatId: chatID, operation: "updateProvisionaryInputText")
            }

            chatMO.provisionaryInputText = text
            return () // Explicit return for Sendable compliance
        }
    }

    func updateSelectedModelFor(_ chatId: String?, model: Model) async throws {
        guard let chatId else { return }
        try await CoreDataActor.performOperation { context in
            let fetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", chatId as CVarArg)
            fetchRequest.fetchLimit = 1

            guard let chatMO = try context.fetch(fetchRequest).first else {
                throw StructuredError.chatNotFound(chatId: chatId, operation: "updateSelectedModelFor")
            }

            chatMO.selectedModel = model.value
            return () // Explicit return for Sendable compliance
        }
    }

    func updateChatTitle(_ chatId: String, title: String) async throws {
        try await CoreDataActor.performOperation { context in
            let fetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", chatId as CVarArg)
            fetchRequest.fetchLimit = 1

            guard let chatMO = try context.fetch(fetchRequest).first else {
                throw StructuredError.chatNotFound(chatId: chatId, operation: "updateChatTitle")
            }

            chatMO.title = title
            return () // Explicit return for Sendable compliance
        }
        try await fetchPersistedChats()
    }

    func updatePreviousResponseId(_ chatId: String, previousResponseId: String?) async throws {
        try await CoreDataActor.performOperation { context in
            let fetchRequest: NSFetchRequest<Chat> = Chat.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", chatId as CVarArg)
            fetchRequest.fetchLimit = 1

            guard let chatMO = try context.fetch(fetchRequest).first else {
                throw StructuredError.chatNotFound(chatId: chatId, operation: "updatePreviousResponseId")
            }

            chatMO.previousResponseId = previousResponseId
            return () // Explicit return for Sendable compliance
        }
    }

    // MARK: - Sync Methods

    private func handleRemoteChanges() async {
        do {
            try await self.fetchPersistedChats()
        } catch {
            print("❌ Failed to refresh chats after remote changes: \(error)")
        }
    }
}
