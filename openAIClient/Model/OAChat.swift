//
//  OAChat.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import Foundation

struct OAChat: Codable, Sendable, Hashable {
    let id: String
    let date: Date
    let title: String
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
        self.messages = []
    }
}
