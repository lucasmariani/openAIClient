//
//  TextSegmentRenderer.swift
//  openAIClient
//
//  Created by Lucas on 02.07.25.
//

import UIKit

/// Renderer for text content segments
@MainActor
final class TextSegmentRenderer: BaseContentSegmentRenderer {
    private let attributedStringCache = AttributedStringCache.shared
    
    init() {
        super.init(segmentType: "text")
    }
    
    override func createView(for segment: ContentSegment, role: OARole) -> UIView {
        guard case .text(let text) = segment else {
            return UIView()
        }
        
        let textView = createTextView()
        updateTextViewContent(textView, with: text, role: role, isStreaming: false)
        return textView
    }
    
    override func updateView(_ view: UIView, with segment: ContentSegment, role: OARole) -> Bool {
        guard let textView = view as? UITextView,
              case .text(let text) = segment else {
            return false
        }
        
        updateTextViewContent(textView, with: text, role: role, isStreaming: false)
        return true
    }
    
    private func createTextView() -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }
    
    private func updateTextViewContent(_ textView: UITextView, with text: String, role: OARole, isStreaming: Bool) {
        let attributedString = attributedStringCache.attributedString(from: text, role: role)
        
        // Only update if content actually changed
        if textView.attributedText?.string != attributedString.string {
            textView.attributedText = attributedString
        }
    }
}

/// Renderer for streaming text content segments
@MainActor
final class StreamingTextSegmentRenderer: BaseContentSegmentRenderer {
    private let attributedStringCache = AttributedStringCache.shared
    
    init() {
        super.init(segmentType: "streamingText")
    }
    
    override func createView(for segment: ContentSegment, role: OARole) -> UIView {
        guard case .streamingText(let text) = segment else {
            return UIView()
        }
        
        let textView = createTextView()
        updateTextViewContent(textView, with: text, role: role, messageId: UUID().uuidString)
        return textView
    }
    
    override func updateView(_ view: UIView, with segment: ContentSegment, role: OARole) -> Bool {
        guard let textView = view as? UITextView,
              case .streamingText(let text) = segment else {
            return false
        }
        
        // Get message ID from text view's accessibility identifier
        let messageId = textView.accessibilityIdentifier ?? UUID().uuidString
        
        // Use differential update for streaming
        updateStreamingTextView(textView, with: text, role: role, messageId: messageId)
        return true
    }
    
    private func createTextView() -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }
    
    private func updateTextViewContent(_ textView: UITextView, with text: String, role: OARole, messageId: String) {
        // Store message ID for future updates
        textView.accessibilityIdentifier = messageId
        
        let attributedString = attributedStringCache.attributedStringForStreaming(
            from: text,
            role: role,
            messageId: messageId
        )
        
        textView.attributedText = attributedString
    }
    
    private func updateStreamingTextView(_ textView: UITextView, with text: String, role: OARole, messageId: String) {
        let newAttributedString = attributedStringCache.attributedStringForStreaming(
            from: text,
            role: role,
            messageId: messageId
        )
        
        // Use efficient text storage update for append-only changes
        let textStorage = textView.textStorage
        let oldLength = textStorage.length
        let newLength = newAttributedString.length
        
        if newLength > oldLength && newAttributedString.string.hasPrefix(textStorage.string) {
            // This is an append-only update
            let appendRange = NSRange(location: oldLength, length: 0)
            let newPortion = newAttributedString.attributedSubstring(
                from: NSRange(location: oldLength, length: newLength - oldLength)
            )
            
            textStorage.beginEditing()
            textStorage.replaceCharacters(in: appendRange, with: newPortion)
            textStorage.endEditing()
        } else {
            // Full replacement
            textView.attributedText = newAttributedString
        }
    }
}