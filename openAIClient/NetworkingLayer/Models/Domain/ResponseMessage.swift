//
//  ResponseMessage.swift
//  openAIClient
//
//  Created by Lucas on 14.06.25.
//

import Foundation

// MARK: - Message Model

public struct ResponseMessage: Identifiable, Sendable {
    public let id = UUID()
    public let role: MessageRole
    public let content: String
    public let timestamp: Date
    public let isStreaming: Bool
    public let responseId: String
    
    public enum MessageRole: String, Sendable {
        case user
        case assistant
    }
    
    // Convenience initializers
    public init(
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        responseId: String
    ) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.responseId = responseId
    }
    
    // Create updated copy with new content
    public func updatedWith(content: String, isStreaming: Bool? = nil) -> ResponseMessage {
        ResponseMessage(
            role: self.role,
            content: content,
            timestamp: Date(),
            isStreaming: isStreaming ?? self.isStreaming,
            responseId: self.responseId
        )
    }
}
