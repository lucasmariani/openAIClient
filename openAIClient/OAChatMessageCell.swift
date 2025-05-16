//
// OAChatMessageCell.swift
// openAIClient
//
// Created by Lucas on 31.05.25.
// 


import UIKit

class OAChatMessageCell: UITableViewCell {
    private let messageStackView = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupStackView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupStackView() {
        messageStackView.axis = .vertical
        messageStackView.spacing = 8
        messageStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(messageStackView)

        NSLayoutConstraint.activate([
            messageStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            messageStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            messageStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            messageStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])
    }

    func configure(with message: String, role: OARole) {
        // Remove previous views
        messageStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        messageStackView.axis = .vertical
        messageStackView.alignment = role == .user ? .leading : .trailing

        // Parse and add new views
        let messageViews = parseMessage(message, role: role)
        messageViews.forEach { messageStackView.addArrangedSubview($0) }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.messageStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    @MainActor func parseMessage(_ message: String, role: OARole) -> [UIView] {
        var views: [UIView] = []
        let components = message.components(separatedBy: "```")

        for (index, component) in components.enumerated() {
            if index % 2 == 0 {
                // Regular text
                let label = UILabel()
                label.text = component
                label.numberOfLines = 0
                label.font = UIFont.systemFont(ofSize: 16)
                views.append(label)
            } else {
                // Code block
                let codeView = OACodeBlockView(code: component, language: .swift)
                views.append(codeView)
            }
        }
        return views
    }

}
