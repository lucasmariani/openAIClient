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
}
