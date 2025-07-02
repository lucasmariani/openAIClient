//
//  MessageContentParser.swift
//  openAIClient
//
//  Created by Lucas on 02.07.25.
//

import Foundation

/// Parses message content into segments for rendering
final class MessageContentParser {
    // MARK: - Properties
    
    // Pre-compiled regex patterns for better performance
    private static let completeCodeBlockRegex: NSRegularExpression = {
        let pattern = "```([a-zA-Z0-9]*)\n(.*?)\n```"
        return try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    }()
    
    private static let incompleteCodeBlockRegex: NSRegularExpression = {
        let pattern = "```[a-zA-Z0-9]*(?:\n.*)?$"
        return try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    }()
    
    // MARK: - Public Methods
    
    /// Parse content into segments
    func parseContent(
        _ content: String,
        attachments: [OAAttachment] = [],
        imageData: Data? = nil,
        isStreaming: Bool = false
    ) -> [ContentSegment] {
        var segments: [ContentSegment] = []
        
        // Add attachments first if any
        if !attachments.isEmpty {
            segments.append(.attachments(attachments))
        }
        
        // Parse text content
        if !content.isEmpty {
            if isStreaming {
                segments.append(contentsOf: parseStreamingContent(content))
            } else {
                segments.append(contentsOf: parseCompletedContent(content))
            }
        }
        
        // Add generated images if any
        if let imageData = imageData {
            segments.append(.generatedImages([imageData]))
        }
        
        return segments
    }
    
    // MARK: - Private Methods
    
    /// Parse streaming content (may contain incomplete code blocks)
    private func parseStreamingContent(_ content: String) -> [ContentSegment] {
        var segments: [ContentSegment] = []
        
        let nsContent = content as NSString
        let range = NSRange(location: 0, length: content.count)
        
        var lastProcessedLocation = 0
        var hasCompleteCodeBlocks = false
        
        // Find all complete code blocks
        Self.completeCodeBlockRegex.enumerateMatches(in: content, options: [], range: range) { match, _, _ in
            guard let match = match else { return }
            hasCompleteCodeBlocks = true
            
            // Add text before this code block
            if match.range.location > lastProcessedLocation {
                let beforeRange = NSRange(location: lastProcessedLocation, length: match.range.location - lastProcessedLocation)
                let beforeText = nsContent.substring(with: beforeRange)
                if !beforeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.text(beforeText))
                }
            }
            
            // Add the complete code block
            let languageRange = match.range(at: 1)
            let codeRange = match.range(at: 2)
            let language = nsContent.substring(with: languageRange)
            let code = nsContent.substring(with: codeRange)
            segments.append(.code(code, language: language.isEmpty ? "swift" : language))
            
            lastProcessedLocation = match.range.location + match.range.length
        }
        
        // Handle remaining text (which may contain incomplete code blocks)
        if lastProcessedLocation < content.count {
            let remainingText = nsContent.substring(from: lastProcessedLocation)
            if !remainingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(contentsOf: parseRemainingStreamingText(remainingText))
            }
        } else if !hasCompleteCodeBlocks && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // No complete code blocks found, check for partial code block
            segments.append(contentsOf: parseRemainingStreamingText(content))
        }
        
        return segments
    }
    
    /// Parse remaining text that may contain incomplete code blocks
    private func parseRemainingStreamingText(_ text: String) -> [ContentSegment] {
        var segments: [ContentSegment] = []
        
        let incompleteRange = NSRange(location: 0, length: text.count)
        if let incompleteMatch = Self.incompleteCodeBlockRegex.firstMatch(in: text, options: [], range: incompleteRange) {
            // Split into text before the incomplete code block and the partial code
            let beforeCodeRange = NSRange(location: 0, length: incompleteMatch.range.location)
            if beforeCodeRange.length > 0 {
                let beforeText = (text as NSString).substring(with: beforeCodeRange)
                if !beforeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.text(beforeText))
                }
            }
            
            // Extract partial code block
            let partialCode = (text as NSString).substring(with: incompleteMatch.range)
            let language = extractLanguageFromPartialBlock(partialCode)
            segments.append(.partialCode(partialCode, language: language))
        } else {
            // No incomplete code block, treat as streaming text
            segments.append(.streamingText(text))
        }
        
        return segments
    }
    
    /// Parse completed content (all code blocks are complete)
    private func parseCompletedContent(_ content: String) -> [ContentSegment] {
        var segments: [ContentSegment] = []
        let components = content.components(separatedBy: "```")
        
        for (index, component) in components.enumerated() {
            if index % 2 == 0 {
                // Regular text
                if !component.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.text(component))
                }
            } else {
                // Code block - detect language from first line
                let lines = component.components(separatedBy: .newlines)
                let language = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "swift"
                let code = lines.dropFirst().joined(separator: "\n")
                segments.append(.code(code, language: language))
            }
        }
        
        return segments
    }
    
    /// Extract language from a partial code block
    private func extractLanguageFromPartialBlock(_ partialCode: String) -> String {
        guard partialCode.hasPrefix("```") else { return "" }
        
        let afterMarker = String(partialCode.dropFirst(3))
        if let newlineIndex = afterMarker.firstIndex(of: "\n") {
            return String(afterMarker[..<newlineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // No newline yet, everything after ``` is potential language
            return afterMarker.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

// MARK: - Content Analysis
extension MessageContentParser {
    /// Analyze content to determine optimal parsing strategy
    func analyzeContent(_ content: String) -> ContentAnalysis {
        let hasCodeBlocks = content.contains("```")
        let lineCount = content.components(separatedBy: .newlines).count
        let characterCount = content.count
        
        return ContentAnalysis(
            hasCodeBlocks: hasCodeBlocks,
            lineCount: lineCount,
            characterCount: characterCount,
            estimatedComplexity: hasCodeBlocks ? .high : (lineCount > 50 ? .medium : .low)
        )
    }
    
    struct ContentAnalysis {
        let hasCodeBlocks: Bool
        let lineCount: Int
        let characterCount: Int
        let estimatedComplexity: Complexity
        
        enum Complexity {
            case low
            case medium
            case high
        }
    }
}