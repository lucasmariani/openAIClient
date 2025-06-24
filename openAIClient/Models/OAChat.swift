//
//  OAChat.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import Foundation
import OpenAIForSwift

struct OAChat: Codable, Sendable, Hashable {
    let id: String
    let date: Date
    let title: String
    let provisionaryInputText: String?
    let selectedModel: Model
    let previousResponseId: String?
    let messages: Set<OAChatMessage>
}

extension OAChat {
    init?(chat: Chat) {
        guard let id = chat.id,
              let date = chat.date
        else { return nil }
        self.id = id
        self.date = date
        self.title = chat.title ?? "No title"
        self.provisionaryInputText = chat.provisionaryInputText
        // Handle migration: use gpt-4.1-nano as default for existing chats without selectedModel
        self.selectedModel = Model(value: chat.selectedModel ?? Model.gpt41nano.value)
        self.previousResponseId = chat.previousResponseId
        self.messages = []
    }
}
