//
//  DifferentialMarkdownParser.swift
//  openAIClient
//
//  Created by Lucas on 01.07.25.
//

import Foundation
import UIKit

/// Performs differential parsing of markdown content to minimize re-parsing during streaming
@MainActor
final class DifferentialMarkdownParser {
    
    // Token types for differential parsing
    enum TokenType: Equatable {
        case plainText(String)
        case codeBlockStart(language: String)
        case codeBlockContent(String)
        case codeBlockEnd
        case inlineCode(String)
        case bold(String)
        case italic(String)
        case link(text: String, url: String)
        case bulletListItem(String)
        case numberedListItem(number: Int, content: String)
        case heading(level: Int, content: String)
        case lineBreak
    }
    
    // Parsing state for streaming content
    struct ParsingState {
        var tokens: [TokenType] = []
        var pendingContent: String = ""
        var isInCodeBlock: Bool = false
        var codeBlockLanguage: String = ""
        var lastProcessedIndex: String.Index
        
        init(content: String = "") {
            lastProcessedIndex = content.startIndex
        }
    }
    
    private var parsingStates: [String: ParsingState] = [:] // messageId -> state
    
    // Pre-compiled regex patterns
    private static let codeBlockStartRegex = try! NSRegularExpression(
        pattern: "^```([a-zA-Z0-9]*)$",
        options: [.anchorsMatchLines]
    )
    
    private static let headingRegex = try! NSRegularExpression(
        pattern: "^(#{1,6})\\s+(.+)$",
        options: [.anchorsMatchLines]
    )
    
    private static let boldRegex = try! NSRegularExpression(
        pattern: "\\*\\*(.+?)\\*\\*",
        options: []
    )
    
    private static let italicRegex = try! NSRegularExpression(
        pattern: "\\*(.+?)\\*",
        options: []
    )
    
    private static let inlineCodeRegex = try! NSRegularExpression(
        pattern: "`([^`]+)`",
        options: []
    )
    
    private static let linkRegex = try! NSRegularExpression(
        pattern: "\\[([^\\]]+)\\]\\(([^\\)]+)\\)",
        options: []
    )
    
    private static let bulletListRegex = try! NSRegularExpression(
        pattern: "^[\\*\\-\\+]\\s+(.+)$",
        options: [.anchorsMatchLines]
    )
    
    private static let numberedListRegex = try! NSRegularExpression(
        pattern: "^(\\d+)\\.\\s+(.+)$",
        options: [.anchorsMatchLines]
    )
    
    /// Parse markdown content differentially, only processing new content
    func parseDifferentially(content: String, for messageId: String) -> [TokenType] {
        // Get or create parsing state
        var state = parsingStates[messageId] ?? ParsingState(content: content)
        
        // If content is shorter than last processed, reset (user might have edited)
        if state.lastProcessedIndex > content.endIndex {
            state = ParsingState(content: content)
            state.tokens = []
            state.pendingContent = ""
        }
        
        // Only process new content that was added since last parse
        let oldContent = String(content.prefix(upTo: state.lastProcessedIndex))
        let newContent = String(content.suffix(from: state.lastProcessedIndex))
        
        // If no new content, return existing tokens
        guard !newContent.isEmpty else {
            return state.tokens
        }
        
        // Process only new content line by line
        let newLines = newContent.components(separatedBy: .newlines)
        
        // If we have pending content from last parse, we need to update the last token
        if !state.pendingContent.isEmpty && !newLines.isEmpty {
            // Remove the last incomplete token and replace with complete version
            if case .plainText(_) = state.tokens.last {
                state.tokens.removeLast()
            }
            
            // Process the now-complete line
            let completeLine = state.pendingContent + newLines[0]
            processLine(completeLine, state: &state, isComplete: true)
            state.pendingContent = ""
            
            // Process remaining new lines (skip first since we just handled it)
            for (index, line) in newLines.dropFirst().enumerated() {
                let isLastLine = index == newLines.count - 2 // -2 because we dropped first
                
                if isLastLine && !line.isEmpty && !content.hasSuffix("\n") {
                    processLine(line, state: &state, isComplete: false)
                    state.pendingContent = line
                } else {
                    processLine(line, state: &state, isComplete: true)
                }
            }
        } else {
            // No pending content, process new lines normally
            for (index, line) in newLines.enumerated() {
                let isLastLine = index == newLines.count - 1
                
                if isLastLine && !line.isEmpty && !content.hasSuffix("\n") {
                    processLine(line, state: &state, isComplete: false)
                    state.pendingContent = line
                } else {
                    processLine(line, state: &state, isComplete: true)
                }
            }
        }
        
        // Update last processed index
        state.lastProcessedIndex = content.endIndex
        
        // Save state for next differential parse
        parsingStates[messageId] = state
        
        return state.tokens
    }
    
    private func processLine(_ line: String, state: inout ParsingState, isComplete: Bool) {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        
        // Handle code blocks specially
        if state.isInCodeBlock {
            if trimmedLine == "```" {
                state.tokens.append(.codeBlockEnd)
                state.isInCodeBlock = false
                state.codeBlockLanguage = ""
            } else {
                // Accumulate code content
                if case .codeBlockContent(let existingCode) = state.tokens.last {
                    // Append to existing code content
                    state.tokens[state.tokens.count - 1] = .codeBlockContent(existingCode + "\n" + line)
                } else {
                    state.tokens.append(.codeBlockContent(line))
                }
            }
            return
        }
        
        // Check for code block start
        if let match = Self.codeBlockStartRegex.firstMatch(
            in: line,
            options: [],
            range: NSRange(location: 0, length: line.count)
        ) {
            let languageRange = match.range(at: 1)
            let language = (line as NSString).substring(with: languageRange)
            state.tokens.append(.codeBlockStart(language: language.isEmpty ? "swift" : language))
            state.isInCodeBlock = true
            state.codeBlockLanguage = language
            return
        }
        
        // Only process complete lines for other markdown elements
        guard isComplete else {
            // For incomplete lines during streaming, treat as plain text
            if !trimmedLine.isEmpty {
                state.tokens.append(.plainText(parseInlineElements(line)))
            }
            return
        }
        
        // Empty line = line break
        if trimmedLine.isEmpty {
            state.tokens.append(.lineBreak)
            return
        }
        
        // Check for headings
        if let match = Self.headingRegex.firstMatch(
            in: line,
            options: [],
            range: NSRange(location: 0, length: line.count)
        ) {
            let levelRange = match.range(at: 1)
            let contentRange = match.range(at: 2)
            let level = (line as NSString).substring(with: levelRange).count
            let content = (line as NSString).substring(with: contentRange)
            state.tokens.append(.heading(level: level, content: content))
            return
        }
        
        // Check for bullet lists
        if let match = Self.bulletListRegex.firstMatch(
            in: line,
            options: [],
            range: NSRange(location: 0, length: line.count)
        ) {
            let contentRange = match.range(at: 1)
            let content = (line as NSString).substring(with: contentRange)
            state.tokens.append(.bulletListItem(parseInlineElements(content)))
            return
        }
        
        // Check for numbered lists
        if let match = Self.numberedListRegex.firstMatch(
            in: line,
            options: [],
            range: NSRange(location: 0, length: line.count)
        ) {
            let numberRange = match.range(at: 1)
            let contentRange = match.range(at: 2)
            let number = Int((line as NSString).substring(with: numberRange)) ?? 1
            let content = (line as NSString).substring(with: contentRange)
            state.tokens.append(.numberedListItem(number: number, content: parseInlineElements(content)))
            return
        }
        
        // Plain text with inline formatting
        state.tokens.append(.plainText(parseInlineElements(line)))
    }
    
    private func parseInlineElements(_ text: String) -> String {
        // For now, return plain text
        // In a full implementation, this would parse inline elements like bold, italic, links
        return text
    }
    
    /// Clear parsing state for a message (e.g., when streaming completes)
    func clearState(for messageId: String) {
        parsingStates.removeValue(forKey: messageId)
    }
    
    /// Convert tokens to attributed string
    func attributedString(from tokens: [TokenType], role: OARole) -> NSAttributedString {
        let result = NSMutableAttributedString()
        
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: role == .user ? UIColor.white : UIColor.label
        ]
        
        for token in tokens {
            switch token {
            case .plainText(let text):
                result.append(NSAttributedString(string: text, attributes: baseAttributes))
                
            case .codeBlockStart(let language):
                // Add language identifier
                var attrs = baseAttributes
                attrs[.font] = UIFont.monospacedSystemFont(ofSize: 12, weight: .medium)
                attrs[.foregroundColor] = UIColor.secondaryLabel
                result.append(NSAttributedString(string: language + "\n", attributes: attrs))
                
            case .codeBlockContent(let code):
                var attrs = baseAttributes
                attrs[.font] = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
                attrs[.backgroundColor] = UIColor.systemGray6
                result.append(NSAttributedString(string: code, attributes: attrs))
                
            case .codeBlockEnd:
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                
            case .inlineCode(let code):
                var attrs = baseAttributes
                attrs[.font] = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
                attrs[.backgroundColor] = UIColor.systemGray6.withAlphaComponent(0.5)
                result.append(NSAttributedString(string: code, attributes: attrs))
                
            case .bold(let text):
                var attrs = baseAttributes
                attrs[.font] = UIFont.preferredFont(forTextStyle: .body).bold()
                result.append(NSAttributedString(string: text, attributes: attrs))
                
            case .italic(let text):
                var attrs = baseAttributes
                attrs[.font] = UIFont.preferredFont(forTextStyle: .body).italic()
                result.append(NSAttributedString(string: text, attributes: attrs))
                
            case .link(let text, let url):
                var attrs = baseAttributes
                attrs[.foregroundColor] = UIColor.systemBlue
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attrs[.link] = url
                result.append(NSAttributedString(string: text, attributes: attrs))
                
            case .bulletListItem(let content):
                result.append(NSAttributedString(string: "• " + content + "\n", attributes: baseAttributes))
                
            case .numberedListItem(let number, let content):
                result.append(NSAttributedString(string: "\(number). " + content + "\n", attributes: baseAttributes))
                
            case .heading(let level, let content):
                var attrs = baseAttributes
                let fontSize: CGFloat = 28 - CGFloat(level * 2)
                attrs[.font] = UIFont.boldSystemFont(ofSize: fontSize)
                result.append(NSAttributedString(string: content + "\n\n", attributes: attrs))
                
            case .lineBreak:
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
            }
        }
        
        return result
    }
}

// MARK: - UIFont Extensions

private extension UIFont {
    func bold() -> UIFont {
        return UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold)!, size: pointSize)
    }
    
    func italic() -> UIFont {
        return UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitItalic)!, size: pointSize)
    }
}
