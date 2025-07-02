//
//  MessageContent.swift
//  openAIClient
//
//  Created by Lucas on 02.07.25.
//

import Foundation
import UIKit

/// Represents a segment of content within a message
enum ContentSegment: Equatable {
    case text(String)
    case code(String, language: String)
    case streamingText(String) // Text that may contain incomplete code blocks
    case partialCode(String, language: String) // Incomplete code block during streaming
    case attachments([OAAttachment])
    case generatedImages([Data])
    
    /// Unique identifier for the segment type
    var typeIdentifier: String {
        switch self {
        case .text: return "text"
        case .code: return "code"
        case .streamingText: return "streamingText"
        case .partialCode: return "partialCode"
        case .attachments: return "attachments"
        case .generatedImages: return "generatedImages"
        }
    }
    
    /// Check if this segment can be incrementally updated with another segment
    func canIncrementallyUpdate(with other: ContentSegment) -> Bool {
        switch (self, other) {
        case (.text(let oldText), .text(let newText)):
            return newText.hasPrefix(oldText)
        case (.streamingText(let oldText), .streamingText(let newText)):
            return newText.hasPrefix(oldText)
        case (.code(let oldCode, let oldLang), .code(let newCode, let newLang)):
            return oldLang == newLang && newCode.hasPrefix(oldCode)
        case (.partialCode(let oldCode, let oldLang), .partialCode(let newCode, let newLang)):
            return oldLang == newLang && newCode.hasPrefix(oldCode)
        default:
            return false
        }
    }
}

/// Represents the complete content of a message
struct MessageContent: Equatable {
    let segments: [ContentSegment]
    let isStreaming: Bool
    let messageId: String
    let role: OARole
    
    /// Check if content is empty (no visible content)
    var isEmpty: Bool {
        segments.isEmpty || segments.allSatisfy { segment in
            switch segment {
            case .text(let text), .streamingText(let text):
                return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .code(let code, _), .partialCode(let code, _):
                return code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .attachments(let attachments):
                return attachments.isEmpty
            case .generatedImages(let images):
                return images.isEmpty
            }
        }
    }
    
    /// Get a hash representing the content for comparison
    var contentHash: String {
        var components: [String] = []
        components.append("role:\(role.rawValue)")
        components.append("streaming:\(isStreaming)")
        
        for segment in segments {
            switch segment {
            case .text(let text):
                components.append("text:\(text.hashValue)")
            case .code(let code, let language):
                components.append("code:\(language):\(code.hashValue)")
            case .streamingText(let text):
                components.append("streamingText:\(text.hashValue)")
            case .partialCode(let code, let language):
                components.append("partialCode:\(language):\(code.hashValue)")
            case .attachments(let attachments):
                let attachmentHash = attachments.map { "att:\($0.filename):\($0.data.count)" }.joined(separator: ",")
                components.append("attachments:\(attachmentHash)")
            case .generatedImages(let images):
                let imageHash = images.map { "img:\($0.count)" }.joined(separator: ",")
                components.append("images:\(imageHash)")
            }
        }
        
        return components.joined(separator: "|")
    }
}

/// Represents a change in message content
enum ContentChangeType {
    case noChange
    case appendToLastSegment
    case segmentUpdate(index: Int)
    case fullUpdate
}

/// Result of comparing two message contents
struct ContentDiff {
    let changeType: ContentChangeType
    let affectedSegments: Set<Int>
    
    static func compare(old: MessageContent, new: MessageContent) -> ContentDiff {
        // Quick check for no change
        if old == new {
            return ContentDiff(changeType: .noChange, affectedSegments: [])
        }
        
        // Check for simple append case
        if old.segments.count == new.segments.count,
           old.segments.count > 0,
           old.segments.dropLast() == Array(new.segments.dropLast()),
           let oldLast = old.segments.last,
           let newLast = new.segments.last,
           oldLast.canIncrementallyUpdate(with: newLast) {
            return ContentDiff(changeType: .appendToLastSegment, affectedSegments: [old.segments.count - 1])
        }
        
        // Check for single segment update
        if old.segments.count == new.segments.count {
            var affectedIndices = Set<Int>()
            for (index, (oldSegment, newSegment)) in zip(old.segments, new.segments).enumerated() {
                if oldSegment != newSegment {
                    affectedIndices.insert(index)
                }
            }
            
            if affectedIndices.count == 1,
               let index = affectedIndices.first {
                return ContentDiff(changeType: .segmentUpdate(index: index), affectedSegments: affectedIndices)
            }
        }
        
        // Default to full update
        return ContentDiff(changeType: .fullUpdate, affectedSegments: Set(0..<new.segments.count))
    }
}

/// Appearance configuration for a message
struct MessageAppearance: Equatable {
    let bubbleColor: UIColor
    let textColor: UIColor
    let alignment: MessageAlignment
    let maxWidthMultiplier: CGFloat
    
    enum MessageAlignment {
        case leading
        case trailing
    }
    
    static func appearance(for role: OARole) -> MessageAppearance {
        switch role {
        case .user:
            return MessageAppearance(
                bubbleColor: .systemBlue,
                textColor: .white,
                alignment: .trailing,
                maxWidthMultiplier: 0.8
            )
        case .assistant:
            return MessageAppearance(
                bubbleColor: .systemGray5,
                textColor: .label,
                alignment: .leading,
                maxWidthMultiplier: 0.9
            )
        case .system:
            return MessageAppearance(
                bubbleColor: UIColor.systemOrange.withAlphaComponent(0.8),
                textColor: .label,
                alignment: .leading,
                maxWidthMultiplier: 0.9
            )
        }
    }
}