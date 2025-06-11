//
//  OAChat.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import Foundation
import SwiftOpenAI

struct OAChat: Codable, Sendable, Hashable {
    let id: String
    let date: Date
    let title: String
    let provisionaryInputText: String?
    let selectedModel: SwiftOpenAI.Model
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
        self.selectedModel = SwiftOpenAI.Model(value: chat.selectedModel ?? "gpt-4.1-nano")
        self.messages = []
    }
}
