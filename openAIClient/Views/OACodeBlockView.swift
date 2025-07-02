//
// OACodeBlockView.swift
// openAIClient
//
// Created by Lucas on 31.05.25.
//

import UIKit
import Highlightr

class OACodeBlockView: UIView {

    private let codeTextView = UITextView()
    private let highlightr = Highlightr()
    private var currentCode: String = ""
    private var currentLanguage: String = "swift"

    init(code: String, language: String = "swift") {
        super.init(frame: .zero)
        self.currentCode = code
        self.currentLanguage = language
        setupHighlightr()
        setupStaticViews()
        configureTextViewContent(with: code, language: language)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupHighlightr() {
        // Choose appropriate theme based on system appearance
        let themeName: String
        if traitCollection.userInterfaceStyle == .dark {
            themeName = "vs2015" // Dark theme with good contrast
        } else {
            themeName = "xcode" // Light theme
        }

        highlightr?.setTheme(to: themeName)
        highlightr?.theme.codeFont = UIFont.monospacedSystemFont(ofSize: 18, weight: .regular)
    }

    private func setupStaticViews() {
        // Use the theme's background color for optimal contrast
        updateBackgroundForTheme()

        layer.cornerRadius = 8
        clipsToBounds = true

        // Add a subtle border
        layer.borderWidth = 1
        updateBorderForTheme()

        codeTextView.isEditable = false
        codeTextView.isScrollEnabled = false
        codeTextView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        codeTextView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(codeTextView)

        NSLayoutConstraint.activate([
            codeTextView.topAnchor.constraint(equalTo: topAnchor),
            codeTextView.bottomAnchor.constraint(equalTo: bottomAnchor),
            codeTextView.leadingAnchor.constraint(equalTo: leadingAnchor),
            codeTextView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    private func updateBackgroundForTheme() {
        let themeBackgroundColor = highlightr?.theme.themeBackgroundColor ??
        (traitCollection.userInterfaceStyle == .dark ? UIColor.black : UIColor.white)
        backgroundColor = themeBackgroundColor
        codeTextView.backgroundColor = themeBackgroundColor
    }

    private func updateBorderForTheme() {
        if traitCollection.userInterfaceStyle == .dark {
            layer.borderColor = UIColor.systemGray4.cgColor
        } else {
            layer.borderColor = UIColor.systemGray3.cgColor
        }
    }

    private func configureTextViewContent(with code: String, language: String) {
        if let highlightedCode = highlightr?.highlight(code, as: language) {
            codeTextView.attributedText = highlightedCode
        } else {
            // Fallback to plain text if highlighting fails
            codeTextView.text = code
            codeTextView.font = UIFont.monospacedSystemFont(ofSize: 18, weight: .regular)
            codeTextView.textColor = .label
        }

        self.invalidateIntrinsicContentSize()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (view: OACodeBlockView, previousTraitCollection: UITraitCollection) in
                self?.handleUserInterfaceStyleChange()
            }
        }
    }

    private func handleUserInterfaceStyleChange() {
        setupHighlightr()
        updateBackgroundForTheme()
        updateBorderForTheme()
        // Re-highlight the current content with new theme
        configureTextViewContent(with: currentCode, language: currentLanguage)
    }
    
    // MARK: - Public Update Methods
    
    /// Update the code block content with new code and/or language
    /// - Parameters:
    ///   - code: The new code content
    ///   - language: The programming language for syntax highlighting
    /// - Returns: `true` if update was successful, `false` if update failed
    func updateContent(code: String, language: String) -> Bool {
        // Normalize language input
        let normalizedLanguage = normalizeLanguage(language)
        
        // Early return if no changes needed
        guard needsContentUpdate(code: code, language: normalizedLanguage) else {
            return true // No update needed, but consider it successful
        }
        
        // Store previous state for potential debugging
        let previousCode = currentCode
        let previousLanguage = currentLanguage
        
        // Update stored state
        currentCode = code
        currentLanguage = normalizedLanguage
        
        // Perform the content update using existing infrastructure
        configureTextViewContent(with: code, language: normalizedLanguage)
        
        // Verify the update was applied successfully
        let updateSuccessful = verifyContentUpdate(expectedCode: code)
        
        if !updateSuccessful {
            // This shouldn't happen with current implementation, but defensive programming
            print("⚠️ OACodeBlockView: Content update verification failed")
            // Restore previous state
            currentCode = previousCode
            currentLanguage = previousLanguage
            configureTextViewContent(with: previousCode, language: previousLanguage)
            return false
        }
        
        return true
    }
    
    /// Optimized method for appending content during streaming
    /// - Parameter additionalCode: Code to append to existing content
    /// - Returns: `true` if append was successful, `false` if fallback needed
    func appendContent(_ additionalCode: String) -> Bool {
        guard !additionalCode.isEmpty else { return true }
        
        let newCode = currentCode + additionalCode
        
        // Try incremental highlighting first for better performance
        if let optimizedResult = tryIncrementalAppend(additionalCode) {
            // Update stored state on successful incremental update
            currentCode = newCode
            return optimizedResult
        }
        
        // Fallback to full update
        return updateContent(code: newCode, language: currentLanguage)
    }
    
    /// Advanced streaming method with performance optimization
    /// - Parameters:
    ///   - additionalCode: Code to append
    ///   - isCompletingCodeBlock: Whether this append completes a code block
    /// - Returns: `true` if append was successful, `false` if fallback needed
    func appendStreamingContent(_ additionalCode: String, isCompletingCodeBlock: Bool = false) -> Bool {
        guard !additionalCode.isEmpty else { return true }
        
        // For completing code blocks, we may want to do a full re-highlight for best results
        if isCompletingCodeBlock {
            let newCode = currentCode + additionalCode
            return updateContent(code: newCode, language: currentLanguage)
        }
        
        // Otherwise use the optimized append
        return appendContent(additionalCode)
    }
    
    /// Check if a content update would change the current state
    /// - Parameters:
    ///   - code: The proposed new code
    ///   - language: The proposed new language
    /// - Returns: `true` if update is needed, `false` if content is already current
    func needsContentUpdate(code: String, language: String) -> Bool {
        let normalizedLanguage = normalizeLanguage(language)
        return code != currentCode || normalizedLanguage != currentLanguage
    }
    
    /// Get current content information for debugging and testing
    var contentInfo: (code: String, language: String) {
        return (currentCode, currentLanguage)
    }
    
    // MARK: - Private Helper Methods
    
    /// Normalize language input for consistent behavior
    private func normalizeLanguage(_ language: String) -> String {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "plaintext" : trimmed.lowercased()
    }
    
    /// Verify that the content update was applied correctly
    private func verifyContentUpdate(expectedCode: String) -> Bool {
        // For attributed text, we check if the string content matches
        if let attributedText = codeTextView.attributedText {
            return attributedText.string == expectedCode
        }
        
        // For plain text fallback
        if let plainText = codeTextView.text {
            return plainText == expectedCode
        }
        
        // If neither is set, something went wrong
        return false
    }
    
    /// Attempt incremental highlighting for append-only updates
    /// - Parameter additionalCode: The code to append
    /// - Returns: `true` if successful, `nil` if should fallback to full update
    private func tryIncrementalAppend(_ additionalCode: String) -> Bool? {
        // Only attempt incremental update if we have existing attributed text
        guard let currentAttributedText = codeTextView.attributedText,
              let highlightr = highlightr else {
            return nil // Fallback to full update
        }
        
        // Attempt to highlight just the new portion
        guard let highlightedNewPortion = highlightr.highlight(additionalCode, as: currentLanguage) else {
            return nil // Highlighting failed, fallback to full update
        }
        
        // Create mutable copy of current text and append the new portion
        let mutableAttributedText = NSMutableAttributedString(attributedString: currentAttributedText)
        mutableAttributedText.append(highlightedNewPortion)
        
        // Apply the update
        codeTextView.attributedText = mutableAttributedText
        
        // Invalidate layout for size changes
        invalidateIntrinsicContentSize()
        
        return true
    }
    
    /// Advanced method for handling streaming with context awareness
    /// - Parameters:
    ///   - newCode: The complete new code content
    ///   - previousLength: Length of the previous code for optimization hints
    /// - Returns: `true` if update successful, `false` if fallback needed
    func updateStreamingCode(_ newCode: String, previousLength: Int) -> Bool {
        // If this looks like an append-only operation, try optimization
        if newCode.count > previousLength && 
           newCode.hasPrefix(currentCode) &&
           currentCode.count == previousLength {
            
            let appendedPortion = String(newCode.dropFirst(previousLength))
            return appendContent(appendedPortion)
        }
        
        // Otherwise do a full update
        return updateContent(code: newCode, language: currentLanguage)
    }
}
