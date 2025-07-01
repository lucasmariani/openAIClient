//
//  OAPartialCodeBlockView.swift
//  openAIClient
//
//  Created by Assistant on 2025-07-01.
//

import UIKit

/// A view for displaying partial/incomplete code blocks during streaming with visual indicators
class OAPartialCodeBlockView: UIView {
    
    private let headerView = UIView()
    private let languageLabel = UILabel()
    private let streamingIndicator = UIActivityIndicatorView(style: .medium)
    private let textView = UITextView()
    private let incompleteLabel = UILabel()
    
    private var code: String = ""
    private var language: String = ""
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(partialCode: String, possibleLanguage: String) {
        super.init(frame: .zero)
        self.code = partialCode
        self.language = possibleLanguage
        setupViews()
        updateContent()
    }
    
    private func setupViews() {
        backgroundColor = UIColor.systemGray6
        layer.cornerRadius = 8
        clipsToBounds = true
        
        // Header setup
        headerView.backgroundColor = UIColor.systemGray5
        headerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerView)
        
        // Language label
        languageLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        languageLabel.textColor = .secondaryLabel
        languageLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(languageLabel)
        
        // Streaming indicator
        streamingIndicator.color = .systemOrange
        streamingIndicator.translatesAutoresizingMaskIntoConstraints = false
        streamingIndicator.startAnimating()
        headerView.addSubview(streamingIndicator)
        
        // Text view for code
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        
        // Incomplete indicator label
        incompleteLabel.text = "⚠️ Streaming code block..."
        incompleteLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        incompleteLabel.textColor = .systemOrange
        incompleteLabel.textAlignment = .center
        incompleteLabel.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.1)
        incompleteLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(incompleteLabel)
        
        // Constraints
        NSLayoutConstraint.activate([
            // Header
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 30),
            
            // Language label
            languageLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            languageLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            // Streaming indicator
            streamingIndicator.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            streamingIndicator.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            // Text view
            textView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: incompleteLabel.topAnchor),
            
            // Incomplete label
            incompleteLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            incompleteLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            incompleteLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            incompleteLabel.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    func updateContent(partialCode: String? = nil, possibleLanguage: String? = nil) {
        if let partialCode = partialCode {
            self.code = partialCode
        }
        if let possibleLanguage = possibleLanguage {
            self.language = possibleLanguage
        }
        
        // Update language label
        languageLabel.text = language.isEmpty ? "code" : language
        
        // Update text view with code
        textView.text = code
        
        // Apply theme
        applyTheme()
    }
    
    private func applyTheme() {
        let isDarkMode = traitCollection.userInterfaceStyle == .dark
        
        if isDarkMode {
            backgroundColor = UIColor(white: 0.1, alpha: 1.0)
            headerView.backgroundColor = UIColor(white: 0.15, alpha: 1.0)
            textView.textColor = .white
        } else {
            backgroundColor = UIColor.systemGray6
            headerView.backgroundColor = UIColor.systemGray5
            textView.textColor = .black
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            applyTheme()
        }
    }
    
    /// Converts this partial view to a complete code block view
    func convertToCompleteCodeBlock() -> OACodeBlockView {
        // Extract the actual code content (removing the opening ```)
        var cleanCode = code
        if cleanCode.hasPrefix("```") {
            cleanCode = String(cleanCode.dropFirst(3))
            // Also remove the language identifier if present
            if let newlineIndex = cleanCode.firstIndex(of: "\n") {
                let possibleLang = String(cleanCode[..<newlineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !possibleLang.isEmpty {
                    self.language = possibleLang
                    cleanCode = String(cleanCode[cleanCode.index(after: newlineIndex)...])
                }
            }
        }
        
        return OACodeBlockView(code: cleanCode, language: language.isEmpty ? "swift" : language)
    }
}