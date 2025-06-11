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

    func configure(with message: String, role: OARole) {
        // Remove previous content
        bubbleStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Configure bubble appearance based on role
        configureBubbleAppearance(for: role)

        // Parse and add new content
        let messageViews = parseMessage(message, role: role)
        messageViews.forEach { bubbleStackView.addArrangedSubview($0) }

        // Configure bubble alignment and width constraints
        configureBubbleAlignment(for: role)
    }

    private func configureBubbleAppearance(for role: OARole) {
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
        // Remove any existing width constraints
        bubbleView.constraints.forEach { constraint in
            if constraint.firstAttribute == .width {
                constraint.isActive = false
            }
        }

        switch role {
        case .user:
            // User messages: align to trailing edge, max 80% width
            messageStackView.alignment = .trailing
            NSLayoutConstraint.activate([
                bubbleView.widthAnchor.constraint(lessThanOrEqualTo: messageStackView.widthAnchor, multiplier: 0.8)
            ])
        case .assistant, .system:
            // Assistant/system messages: align to leading edge, max 90% width
            messageStackView.alignment = .leading
            NSLayoutConstraint.activate([
                bubbleView.widthAnchor.constraint(lessThanOrEqualTo: messageStackView.widthAnchor, multiplier: 0.9)
            ])
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        bubbleStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Remove dynamic width constraints
        bubbleView.constraints.forEach { constraint in
            if constraint.firstAttribute == .width {
                constraint.isActive = false
            }
        }
    }

    @MainActor func parseMessage(_ message: String, role: OARole) -> [UIView] {
        var views: [UIView] = []
        let components = message.components(separatedBy: "```")

        for (index, component) in components.enumerated() {
            if index % 2 == 0 {
                // Regular text
//                let label = UILabel()
//                label.text = component
//                label.numberOfLines = 0
//                label.font = UIFont.systemFont(ofSize: 18)
//
//                // Set text color based on role
//                switch role {
//                case .user:
//                    label.textColor = .white
//                case .assistant, .system:
//                    label.textColor = .label
//                }
//
//                views.append(label)
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

//        if #available(iOS 15.0, *) {
            // Use built-in markdown support


            let attributedString = try? NSAttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))

            if let attributedString {
                let mutableString = NSMutableAttributedString(attributedString: attributedString)

                // Apply role-specific color
                let color: UIColor = {
                    switch role {
                        case .user: return .white
                        case .assistant, .system: return .label
                    }
                }()

                mutableString.addAttribute(
                    .foregroundColor,
                    value: color,
                    range: NSRange(location: 0, length: mutableString.length)
                )

                textView.attributedText = mutableString
            } else {
                // Fallback to plain text
                textView.text = text
                textView.textColor = role == .user ? .white : .label
            }
//        } else {
//            // Use custom markdown parsing for iOS 14 and below
//            let attributedString = parseMarkdown(text, role: role)
//            textView.attributedText = attributedString
//        }

        return textView
    }
}
