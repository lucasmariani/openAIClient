//
//  OAChatMessage.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import Foundation
import OpenAIForSwift

enum OARole: String, Codable, Sendable {
    case user, assistant, system
}

struct OAChatMessage: Codable, Sendable, Hashable { // Ensure it's Hashable if used in Sets or as DiffableDataSource item
    let id: String
    let role: OARole
    private(set) var content: String
    private(set) var date: Date
    let attachments: [OAAttachment]
    private(set) var imageData: Data?

    init(id: String, role: OARole, content: String, date: Date = .now, attachments: [OAAttachment] = [], imageData: Data?) {
        self.id = id
        self.role = role
        self.content = content
        self.date = date
        self.attachments = attachments
        self.imageData = imageData
    }

    init?(message: Message) { // 'Message' is the Core Data entity
        guard let id = message.id,
              let roleString = message.role, // Assuming 'role' is String in Core Data
              let role = OARole(rawValue: roleString),
              let content = message.content,
              let date = message.date,
              let imageData = message.imageData else {
            return nil
        }
        self.id = id
        self.role = role
        self.content = content
        self.date = date
        self.imageData = imageData

        // Convert Core Data attachments to OAAttachment array
        let attachmentSet = message.attachments as? Set<Attachment> ?? Set<Attachment>()
        self.attachments = attachmentSet.compactMap { OAAttachment(attachment: $0) }
        
        // Initialize generatedImages as empty for existing messages
        // TODO: Add Core Data support for storing generated images
    }

    mutating func update(with content: String, date: Date) {
        self.content = content
        self.date = date
    }

    mutating func updateGeneratedImage(_ imageData: Data) {
        self.imageData = imageData
    }
}
