//
// OACodeBlockView.swift
// openAIClient
//
// Created by Lucas on 31.05.25.
// 


import UIKit
import Sourceful

class OACodeBlockView: UIView {

    private let codeTextView = SyntaxTextView()

    init(code: String, lexer: Lexer) {
        super.init(frame: .zero)
        setupStaticViews() // Synchronous setup
        Task {
            self.configureTextViewContent(with: code, lexer: lexer)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupStaticViews() {
        backgroundColor = UIColor.systemGray
        layer.cornerRadius = 6
        clipsToBounds = true

//        codeTextView.isEditable = false
//        codeTextView.isScrollEnabled = false // Crucial for dynamic height in a cell
        codeTextView.backgroundColor = .clear

        codeTextView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(codeTextView)

        NSLayoutConstraint.activate([
            codeTextView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            codeTextView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            codeTextView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            codeTextView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])
    }

    private func configureTextViewContent(with code: String, lexer: Sourceful.Lexer) {
        let desiredCodeFontSize: CGFloat = 14 // Adjust this value to your desired font size
        let codeFont = UIFont.monospacedSystemFont(ofSize: desiredCodeFontSize, weight: .regular)

        // Theme for the SyntaxTextView
        // The theme's backgroundColor is for the text area itself.
        let themeBackgroundColor = UIColor.systemGray5 // A distinct background for the code content

        codeTextView.theme = OACustomSourceCodeTheme(
            font: codeFont,
            themeBackgroundColor: themeBackgroundColor
        )

        codeTextView.text = code
        codeTextView.lexer = lexer

        // Inform the layout system that the intrinsic content size might have changed.
        // This should be called on the main thread.
        // Assuming init is called from a @MainActor context (e.g., OAChatMessageCell.parseMessage).
        self.invalidateIntrinsicContentSize()
    }

}

struct OACustomSourceCodeTheme: SourceCodeTheme {
    
    let font: UIFont
    let backgroundColor: UIColor // Background of the text editing area

    var lineNumbersStyle: LineNumbersStyle? = nil
    var gutterStyle: GutterStyle
    var shadow: NSShadow? = nil
    var tabWidth: CGFloat = 4.0
    var kern: CGFloat = 0.0

    init(font: UIFont, themeBackgroundColor: UIColor) {
        self.font = font
        self.backgroundColor = themeBackgroundColor
        // Gutter is not shown if showLineNumbers is false (default for SyntaxTextView)
        // If line numbers were enabled, gutter styling would be more relevant.
        self.gutterStyle = GutterStyle(backgroundColor: themeBackgroundColor, minimumWidth: 0)
    }

    func globalAttributes() -> [NSAttributedString.Key: Any] {
        // Default text color, should be visible on themeBackgroundColor
        return [.font: font, .foregroundColor: UIColor.label]
    }

    func color(for syntaxColorType: Sourceful.SourceCodeTokenType) -> Sourceful.Color {
        switch syntaxColorType {
        case .keyword:
            return UIColor.systemPink
        case .string:
            return UIColor.systemRed
        case .comment:
            return UIColor.systemGreen
        case .number:
            return UIColor.systemOrange
        case .identifier:
            return UIColor.label // Or a more specific color like UIColor.systemTeal
        case .editorPlaceholder:
            return UIColor.systemGray
        case .plain:
            return UIColor.label
        // Add more cases as needed for other token types like .delimiter, etc.
        // You can find all available types in Sourceful.SourceCodeTokenType
        default:
            return UIColor.label // Fallback color
        }
    }

    // This method is for additional attributes beyond color and the global font.
    // Since color is handled by `color(for:)` and font by `globalAttributes()`,
    // this can often be empty.
    func attributes(for token: Sourceful.Token) -> [NSAttributedString.Key: Any] {
        // No additional attributes needed here as color is handled by `color(for:)`
        // and font by `globalAttributes()`.
        return [:]
    }

}
