//
//  OAChatMessageCell.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import UIKit

class OAChatMessageCell: UITableViewCell {
    
    private let messageStackView = UIStackView()
    private let bubbleView = UIView()
    private let bubbleStackView = UIStackView()
    
    // State tracking for differential updates
    private var currentMessageHash: String?
    private var currentRole: OARole?
    private var currentWidthConstraint: NSLayoutConstraint?
    
    // Content segment tracking for incremental updates
    private var currentContentSegments: [ContentSegment] = []
    
    // Pre-compiled regex patterns for better performance
    private static let completeCodeBlockRegex: NSRegularExpression = {
        let pattern = "```([a-zA-Z0-9]*)\n(.*?)\n```"
        return try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    }()
    
    private static let incompleteCodeBlockRegex: NSRegularExpression = {
        let pattern = "```[a-zA-Z0-9]*(?:\n.*)?$"
        return try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    }()
    
    // Content segment types for granular updates
    private enum ContentSegment: Equatable {
        case attachments([OAAttachment])
        case text(String)
        case code(String, language: String)
        case streamingText(String) // Text that may contain incomplete code blocks
        case partialCode(String, language: String) // Incomplete code block during streaming
        case generatedImages([Data])
        
        static func == (lhs: ContentSegment, rhs: ContentSegment) -> Bool {
            switch (lhs, rhs) {
            case (.attachments(let a), .attachments(let b)):
                return a.count == b.count && zip(a, b).allSatisfy { $0.filename == $1.filename && $0.data == $1.data }
            case (.text(let a), .text(let b)):
                return a == b
            case (.code(let a, let langA), .code(let b, let langB)):
                return a == b && langA == langB
            case (.streamingText(let a), .streamingText(let b)):
                return a == b
            case (.partialCode(let a, let langA), .partialCode(let b, let langB)):
                return a == b && langA == langB
            case (.generatedImages(let a), .generatedImages(let b)):
                return a == b
            default:
                return false
            }
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupSubviews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupSubviews() {
        backgroundColor = .clear
        selectionStyle = .none
        
        // Configure bubble view
        bubbleView.layer.cornerRadius = 16
        bubbleView.clipsToBounds = true
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure bubble stack view (contains the actual content)
        bubbleStackView.axis = .vertical
        bubbleStackView.spacing = 8
        bubbleStackView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(bubbleStackView)
        
        // Configure main message stack view (positions the bubble)
        messageStackView.axis = .vertical
        messageStackView.translatesAutoresizingMaskIntoConstraints = false
        messageStackView.addArrangedSubview(bubbleView)
        
        contentView.addSubview(messageStackView)
        
        // Constraints
        NSLayoutConstraint.activate([
            // Message stack view constraints
            messageStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            messageStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            messageStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            messageStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // Bubble stack view constraints (content inside bubble)
            bubbleStackView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 12),
            bubbleStackView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -12),
            bubbleStackView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            bubbleStackView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12)
        ])
    }
    
    func configure(with message: OAChatMessage, isStreaming: Bool = false) {
//        print("DEBUG configure(with message called, isStreaming: \(isStreaming)")
        
        // Always update appearance first (handles role color changes)
        configureBubbleAppearance(for: message.role)
        
        // Parse content into segments for incremental comparison
        let newContentSegments = parseContentIntoSegments(for: message, isStreaming: isStreaming)
        let changeType = detectIncrementalChange(from: currentContentSegments, to: newContentSegments)
        
        switch changeType {
        case .noChange:
            break

        case .appendToLastText:
//            print("DEBUG detected append-only text change - updating in place")
            if let lastView = bubbleStackView.arrangedSubviews.last as? UITextView,
               case .text(let newText) = newContentSegments.last {
                updateTextView(lastView, with: newText, role: message.role)
            } else {
                // Fallback to full recreation if we can't find the text view
                performFullContentUpdate(for: message)
            }
            
        case .appendToLastStreamingText:
//            print("DEBUG detected append-only streaming text change - updating in place")
            if let lastView = bubbleStackView.arrangedSubviews.last as? UITextView,
               case .streamingText(let newText) = newContentSegments.last {
                updateTextView(lastView, with: newText, role: message.role)
            } else if let lastView = bubbleStackView.arrangedSubviews.last as? OAPartialCodeBlockView,
                      case .partialCode(let newCode, let newLang) = newContentSegments.last {
                // Update partial code block in place
                lastView.updateContent(partialCode: newCode, possibleLanguage: newLang)
            } else {
                // Fallback to full recreation if we can't find the appropriate view
                performFullContentUpdate(for: message)
            }
            
        case .fullRecreation:
//            print("DEBUG performing full content recreation")
            currentContentSegments = newContentSegments
            performFullContentUpdate(for: message)
        }
        
        // Update stored segments and hash
        currentContentSegments = newContentSegments
        currentMessageHash = createContentHash(for: message)
        
        // Configure bubble alignment (only updates if role changed)
        configureBubbleAlignment(for: message.role)
    }
    
    private func updateTextView(_ textView: UITextView, with text: String, role: OARole) {
        // Use cached attributed string for better performance
        let newAttributedString = AttributedStringCache.shared.attributedString(from: text, role: role)
        
        // Use textStorage for efficient updates when possible
        let textStorage = textView.textStorage
        
        // Calculate the difference between old and new text
        let oldLength = textStorage.length
        let newLength = newAttributedString.length
        
        // For append-only updates during streaming, we can be more efficient
        if newLength > oldLength {
            // Extract just the new portion
            let oldText = textStorage.string
            let newText = newAttributedString.string
            
            if newText.hasPrefix(oldText) {
                // This is an append-only update - just add the new content
                let appendRange = NSRange(location: oldLength, length: 0)
                let newPortion = newAttributedString.attributedSubstring(
                    from: NSRange(location: oldLength, length: newLength - oldLength)
                )
                
                textStorage.beginEditing()
                textStorage.replaceCharacters(in: appendRange, with: newPortion)
                textStorage.endEditing()
                return
            }
        }
        
        // Fallback to full replacement for other cases
        textView.attributedText = newAttributedString
    }
    
    private func performFullContentUpdate(for message: OAChatMessage) {
//        print("DEBUG removing all arrangedSubviews for full update")
        // Remove previous content
        bubbleStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Create views from the new content segments
        for segment in currentContentSegments {
            switch segment {
            case .attachments(let attachments):
                let attachmentView = createAttachmentView(for: attachments)
                bubbleStackView.addArrangedSubview(attachmentView)
                
            case .text(let text), .streamingText(let text):
                let textView = createFormattedTextView(from: text, role: message.role)
                bubbleStackView.addArrangedSubview(textView)
                
            case .code(let code, let language):
                let codeView = OACodeBlockView(code: code, language: language)
                bubbleStackView.addArrangedSubview(codeView)
                
            case .partialCode(let code, let language):
                let partialCodeView = OAPartialCodeBlockView(partialCode: code, possibleLanguage: language)
                bubbleStackView.addArrangedSubview(partialCodeView)
                
            case .generatedImages(let imageDatas):
                let generatedImagesView = createGeneratedImagesView(from: imageDatas)
                bubbleStackView.addArrangedSubview(generatedImagesView)
            }
        }
    }
    
    func configure(with message: String, role: OARole) {
        let chatMessage = OAChatMessage(id: UUID().uuidString, role: role, content: message, imageData: nil)
        configure(with: chatMessage)
    }
    
    private func configureBubbleAppearance(for role: OARole) {
        // Only update appearance if role changed (avoids redundant color updates)
        guard currentRole != role else { return }
        
        switch role {
        case .user:
            bubbleView.backgroundColor = UIColor.systemBlue
            // User messages will have white text
        case .assistant:
            bubbleView.backgroundColor = UIColor.systemGray5
            // Assistant messages will have default text color
        case .system:
            bubbleView.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.8)
            // System messages will have default text color
        }
    }
    
    private func configureBubbleAlignment(for role: OARole) {
        // Only update if role actually changed
        guard currentRole != role else { return }
        
        // Remove existing width constraint if any
        currentWidthConstraint?.isActive = false
        
        switch role {
        case .user:
            // User messages: align to trailing edge, max 80% width
            messageStackView.alignment = .trailing
            currentWidthConstraint = bubbleView.widthAnchor.constraint(lessThanOrEqualTo: messageStackView.widthAnchor, multiplier: 0.8)
        case .assistant, .system:
            // Assistant/system messages: align to leading edge, max 90% width
            messageStackView.alignment = .leading
            currentWidthConstraint = bubbleView.widthAnchor.constraint(lessThanOrEqualTo: messageStackView.widthAnchor, multiplier: 0.9)
        }
        
        // Activate the new constraint
        currentWidthConstraint?.isActive = true
        currentRole = role
    }
    
    private func createContentHash(for message: OAChatMessage) -> String {
//        print("DEBUG new content hash created")
        var hashComponents: [String] = []
        
        // Include role
        hashComponents.append("role:\(message.role.rawValue)")
        
        // Include content
        hashComponents.append("content:\(message.content)")
        
        // Include attachments hash
        let attachmentHashes = message.attachments.map { attachment in
            "attachment:\(attachment.filename):\(attachment.data.count)"
        }
        hashComponents.append(contentsOf: attachmentHashes)
        
        // Include image data hash
        if let imageData = message.imageData {
            hashComponents.append("imageData:\(imageData.count)")
        }
        
        return hashComponents.joined(separator: "|")
    }
    
    private func parseContentIntoSegments(for message: OAChatMessage, isStreaming: Bool = false) -> [ContentSegment] {
        var segments: [ContentSegment] = []
        
        // Add attachments first if any
        if !message.attachments.isEmpty {
            segments.append(.attachments(message.attachments))
        }
        
        // Parse text content with streaming awareness
        if !message.content.isEmpty {
            if isStreaming {
                segments.append(contentsOf: parseStreamingContent(message.content))
            } else {
                segments.append(contentsOf: parseCompletedContent(message.content))
            }
        }
        
        // Add generated images if any
        if let imageData = message.imageData {
            segments.append(.generatedImages([imageData]))
        }
        
        return segments
    }
    
    private func parseStreamingContent(_ content: String) -> [ContentSegment] {
        // During streaming, only recognize complete code blocks to maintain stable structure
        var segments: [ContentSegment] = []
        
        // Use pre-compiled regex for better performance
        let nsContent = content as NSString
        let range = NSRange(location: 0, length: content.count)
        
        var lastProcessedLocation = 0
        var hasCompleteCodeBlocks = false
        
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
                // Check if remaining text contains an incomplete code block
                let incompleteRange = NSRange(location: 0, length: remainingText.count)
                if let incompleteMatch = Self.incompleteCodeBlockRegex.firstMatch(in: remainingText, options: [], range: incompleteRange) {
                    // Split into text before the incomplete code block and the partial code
                    let beforeCodeRange = NSRange(location: 0, length: incompleteMatch.range.location)
                    if beforeCodeRange.length > 0 {
                        let beforeText = (remainingText as NSString).substring(with: beforeCodeRange)
                        if !beforeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            segments.append(.text(beforeText))
                        }
                    }
                    
                    // Extract partial code block
                    let partialCode = (remainingText as NSString).substring(with: incompleteMatch.range)
                    var language = ""
                    
                    // Try to extract language from the partial block
                    if partialCode.hasPrefix("```") {
                        let afterMarker = String(partialCode.dropFirst(3))
                        if let newlineIndex = afterMarker.firstIndex(of: "\n") {
                            language = String(afterMarker[..<newlineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                        } else {
                            // No newline yet, everything after ``` is potential language
                            language = afterMarker.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    
                    segments.append(.partialCode(partialCode, language: language))
                } else {
                    // No incomplete code block, treat as streaming text
                    segments.append(.streamingText(remainingText))
                }
            }
        } else if !hasCompleteCodeBlocks && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // No complete code blocks found, check for partial code block
            let range = NSRange(location: 0, length: content.count)
            if let incompleteMatch = Self.incompleteCodeBlockRegex.firstMatch(in: content, options: [], range: range) {
                // Content starts with an incomplete code block
                let beforeCodeRange = NSRange(location: 0, length: incompleteMatch.range.location)
                if beforeCodeRange.length > 0 {
                    let beforeText = nsContent.substring(with: beforeCodeRange)
                    if !beforeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        segments.append(.text(beforeText))
                    }
                }
                
                let partialCode = nsContent.substring(with: incompleteMatch.range)
                var language = ""
                if partialCode.hasPrefix("```") {
                    let afterMarker = String(partialCode.dropFirst(3))
                    if let newlineIndex = afterMarker.firstIndex(of: "\n") {
                        language = String(afterMarker[..<newlineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        language = afterMarker.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                
                segments.append(.partialCode(partialCode, language: language))
            } else {
                // No code blocks at all, treat as streaming text
                segments.append(.streamingText(content))
            }
        }
        
        return segments
    }
    
    private func parseCompletedContent(_ content: String) -> [ContentSegment] {
        // For completed messages, use the original parsing logic
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
    
    private func detectIncrementalChange(from oldSegments: [ContentSegment], to newSegments: [ContentSegment]) -> IncrementalChangeType {
        // Check for simple append-only case (most common during streaming)
        if oldSegments.count == newSegments.count,
           oldSegments.count > 0,
           oldSegments.dropLast().elementsEqual(newSegments.dropLast()) {
            
            let oldLast = oldSegments.last!
            let newLast = newSegments.last!
            
            // Check if last segment is text and we're just appending
            if case .text(let oldText) = oldLast,
               case .text(let newText) = newLast,
               newText.hasPrefix(oldText) {
                return .appendToLastText
            }
            
            // Check if last segment is streaming text and we're just appending
            if case .streamingText(let oldText) = oldLast,
               case .streamingText(let newText) = newLast,
               newText.hasPrefix(oldText) {
                return .appendToLastStreamingText
            }
            
            // Check if last segment is partial code and we're just appending
            if case .partialCode(let oldCode, _) = oldLast,
               case .partialCode(let newCode, _) = newLast,
               newCode.hasPrefix(oldCode) {
                return .appendToLastStreamingText
            }
        }
        
        // Check for complete structure equality
        if oldSegments == newSegments {
            return .noChange
        }
        
        // For now, fall back to full recreation for complex changes
        return .fullRecreation
    }
    
    private enum IncrementalChangeType {
        case noChange
        case appendToLastText
        case appendToLastStreamingText
        case fullRecreation
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
//        print("DEBUG prepareForReuse called")
        bubbleStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Remove dynamic width constraints
        currentWidthConstraint?.isActive = false
        currentWidthConstraint = nil
        
        // Clear state tracking
        currentMessageHash = nil
        currentRole = nil
        currentContentSegments = []
    }
    
    @MainActor func parseMessage(_ message: String, role: OARole) -> [UIView] {
        var views: [UIView] = []
        let components = message.components(separatedBy: "```")
        
        for (index, component) in components.enumerated() {
            if index % 2 == 0 {
                // Regular text
                let textView = createFormattedTextView(from: component, role: role)
                if !component.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    views.append(textView)
                }
            } else {
                // Code block - detect language from first line
                let lines = component.components(separatedBy: .newlines)
                let language = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "swift"
                let code = lines.dropFirst().joined(separator: "\n")
                
                let codeView = OACodeBlockView(code: code, language: language)
                views.append(codeView)
            }
        }
        return views
    }
    
    private func createFormattedTextView(from text: String, role: OARole) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        
        // Use cached attributed string for better performance
        let attributedString = AttributedStringCache.shared.attributedString(from: text, role: role)
        textView.attributedText = attributedString
        
        return textView
    }
    
    private func createAttachmentView(for attachments: [OAAttachment]) -> UIView {
        let containerView = UIView()
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        for attachment in attachments {
            let attachmentItemView = createSingleAttachmentView(for: attachment)
            stackView.addArrangedSubview(attachmentItemView)
        }
        
        containerView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])
        
        return containerView
    }
    
    private func createSingleAttachmentView(for attachment: OAAttachment) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)
        containerView.layer.cornerRadius = 8
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = UIColor.systemGray4.cgColor
        
        if attachment.isImage {
            return createImageAttachmentView(for: attachment, in: containerView)
        } else {
            return createDocumentAttachmentView(for: attachment, in: containerView)
        }
    }
    
    private func createImageAttachmentView(for attachment: OAAttachment, in containerView: UIView) -> UIView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        if let image = UIImage(data: attachment.data) {
            imageView.image = image
        }
        
        containerView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: 200),
            imageView.widthAnchor.constraint(lessThanOrEqualToConstant: 200)
        ])
        
        return containerView
    }
    
    private func createDocumentAttachmentView(for attachment: OAAttachment, in containerView: UIView) -> UIView {
        let iconImageView = UIImageView()
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.image = UIImage(systemName: "doc.fill")
        iconImageView.tintColor = .systemBlue
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        
        let nameLabel = UILabel()
        nameLabel.text = attachment.filename
        nameLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        nameLabel.numberOfLines = 2
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let sizeLabel = UILabel()
        sizeLabel.text = attachment.sizeString
        sizeLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        sizeLabel.textColor = .secondaryLabel
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(iconImageView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(sizeLabel)
        
        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            iconImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 32),
            iconImageView.heightAnchor.constraint(equalToConstant: 32),
            
            nameLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            
            sizeLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            sizeLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            sizeLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            sizeLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8)
        ])
        
        return containerView
    }
    
    private func createGeneratedImagesView(from imageDataArray: [Data]) -> UIView {
        let containerView = UIView()
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        for imageData in imageDataArray {
            if let image = UIImage(data: imageData) {
                let imageView = createGeneratedImageView(with: image)
                stackView.addArrangedSubview(imageView)
            }
        }
        
        containerView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])
        
        return containerView
    }
    
    private func createGeneratedImageView(with image: UIImage) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.1)
        containerView.layer.cornerRadius = 12
        containerView.clipsToBounds = true
        
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: 300),
            imageView.widthAnchor.constraint(lessThanOrEqualToConstant: 300)
        ])
        
        return containerView
    }
}
