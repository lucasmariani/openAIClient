//
//  MessageViewModel.swift
//  openAIClient
//
//  Created by Lucas on 02.07.25.
//

import Foundation
import Combine

/// View model for a single message, handling content and appearance updates
@MainActor
final class MessageViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var content: MessageContent
    @Published private(set) var appearance: MessageAppearance
    
    // MARK: - Private Properties
    private let message: OAChatMessage
    private let contentParser: MessageContentParser
    private var streamingBuffer: String = ""
    private var lastContentHash: String = ""
    
    // MARK: - Initialization
    init(message: OAChatMessage, contentParser: MessageContentParser = MessageContentParser()) {
        self.message = message
        self.contentParser = contentParser
        self.appearance = MessageAppearance.appearance(for: message.role)
        
        // Parse initial content
        let segments = contentParser.parseContent(
            message.content,
            attachments: message.attachments,
            imageData: message.imageData,
            isStreaming: false
        )
        
        self.content = MessageContent(
            segments: segments,
            isStreaming: false,
            messageId: message.id,
            role: message.role
        )
        
        self.lastContentHash = content.contentHash
    }
    
    // MARK: - Public Methods
    
    /// Update content for streaming
    func updateStreamingContent(_ rawContent: String) {
        streamingBuffer = rawContent
        
        let newSegments = contentParser.parseContent(
            rawContent,
            attachments: message.attachments,
            imageData: message.imageData,
            isStreaming: true
        )
        
        let newContent = MessageContent(
            segments: newSegments,
            isStreaming: true,
            messageId: message.id,
            role: message.role
        )
        
        // Only update if content actually changed
        if newContent.contentHash != lastContentHash {
            content = newContent
            lastContentHash = newContent.contentHash
        }
    }
    
    /// Finalize content after streaming completes
    func finalizeContent(_ finalContent: String, imageData: Data? = nil) {
        streamingBuffer = ""
        
        let newSegments = contentParser.parseContent(
            finalContent,
            attachments: message.attachments,
            imageData: imageData ?? message.imageData,
            isStreaming: false
        )
        
        let newContent = MessageContent(
            segments: newSegments,
            isStreaming: false,
            messageId: message.id,
            role: message.role
        )
        
        content = newContent
        lastContentHash = newContent.contentHash
        
        // Clear streaming state in the cache
        AttributedStringCache.shared.clearStreamingState(for: message.id)
    }
    
    /// Update the complete message
    func updateMessage(_ updatedMessage: OAChatMessage) {
        let newSegments = contentParser.parseContent(
            updatedMessage.content,
            attachments: updatedMessage.attachments,
            imageData: updatedMessage.imageData,
            isStreaming: false
        )
        
        let newContent = MessageContent(
            segments: newSegments,
            isStreaming: false,
            messageId: updatedMessage.id,
            role: updatedMessage.role
        )
        
        // Update appearance if role changed
        if updatedMessage.role != message.role {
            appearance = MessageAppearance.appearance(for: updatedMessage.role)
        }
        
        content = newContent
        lastContentHash = newContent.contentHash
    }
    
    /// Get content diff for optimization
    func getContentDiff(from oldContent: MessageContent) -> ContentDiff {
        return ContentDiff.compare(old: oldContent, new: content)
    }
    
    // MARK: - Helper Methods
    
    /// Check if content needs update
    func needsUpdate(for message: OAChatMessage) -> Bool {
        return message.content != self.message.content ||
               message.attachments != self.message.attachments ||
               message.imageData != self.message.imageData ||
               message.role != self.message.role
    }
}

// MARK: - MessageViewModel Factory
extension MessageViewModel {
    /// Factory method to create view models with proper configuration
    static func create(for message: OAChatMessage, isStreaming: Bool = false) -> MessageViewModel {
        let viewModel = MessageViewModel(message: message)
        
        if isStreaming && !message.content.isEmpty {
            viewModel.updateStreamingContent(message.content)
        }
        
        return viewModel
    }
}