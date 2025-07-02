//
//  OAChatMessageCell.swift
//  openAIClient
//
//  Created by Lucas on 02.07.25.
//

import UIKit
import Combine

/// Refactored chat message cell using clean architecture
class OAChatMessageCell: UITableViewCell {
    // MARK: - Properties
    private let messageStackView = UIStackView()
    private let bubbleView = MessageBubbleView()
    
    private var viewModel: MessageViewModel?
    private let contentRenderer = CompositeMessageRenderer()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupSubviews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupSubviews() {
        backgroundColor = .clear
        selectionStyle = .none
        
        // Configure main message stack view (positions the bubble)
        messageStackView.axis = .vertical
        messageStackView.backgroundColor = .clear
        messageStackView.translatesAutoresizingMaskIntoConstraints = false
        messageStackView.addArrangedSubview(bubbleView)
        
        contentView.addSubview(messageStackView)
        
        // Constraints
        NSLayoutConstraint.activate([
            messageStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            messageStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            messageStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            messageStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])
    }
    
    // MARK: - Public Methods
    
    /// Configure the cell with a message
    func configure(with message: OAChatMessage, isStreaming: Bool = false) {
        // Create or update view model
        if let existingViewModel = viewModel,
           !existingViewModel.needsUpdate(for: message) && !isStreaming {
            // No update needed
            return
        }
        
        // Cancel previous subscriptions
        cancellables.removeAll()
        
        // Create new view model
        viewModel = MessageViewModel.create(for: message, isStreaming: isStreaming)
        
        // Bind to view model updates
        bindToViewModel()
        
        // Initial render
        if let viewModel = viewModel {
            updateAppearance(viewModel.appearance)
            renderContent(viewModel.content)
        }
    }
    
    /// Update streaming content efficiently
    func updateStreamingContent(_ content: String) {
        viewModel?.updateStreamingContent(content)
    }
    
    /// Finalize content after streaming completes
    func finalizeContent(_ content: String, imageData: Data? = nil) {
        viewModel?.finalizeContent(content, imageData: imageData)
    }
    
    // MARK: - Private Methods
    
    private func bindToViewModel() {
        guard let viewModel = viewModel else { return }
        
        // Bind to content changes
        viewModel.$content
            .removeDuplicates { $0.contentHash == $1.contentHash }
            .sink { [weak self] content in
                self?.handleContentUpdate(content)
            }
            .store(in: &cancellables)
        
        // Bind to appearance changes
        viewModel.$appearance
            .removeDuplicates()
            .sink { [weak self] appearance in
                self?.updateAppearance(appearance)
            }
            .store(in: &cancellables)
    }
    
    private func handleContentUpdate(_ content: MessageContent) {
        // Try incremental update first
        if !contentRenderer.updateContent(content, in: bubbleView) {
            // Fall back to full render if incremental update failed
            renderContent(content)
        }
    }
    
    private func renderContent(_ content: MessageContent) {
        contentRenderer.render(content, in: bubbleView)
    }
    
    private func updateAppearance(_ appearance: MessageAppearance) {
        // Update bubble appearance
        bubbleView.updateAppearance(appearance)
        
        // Update alignment
        bubbleView.updateAlignment(
            appearance.alignment,
            maxWidthMultiplier: appearance.maxWidthMultiplier,
            in: messageStackView
        )
        
        // Update stack view alignment
        switch appearance.alignment {
        case .leading:
            messageStackView.alignment = .leading
        case .trailing:
            messageStackView.alignment = .trailing
        }
    }
    
    // MARK: - Reuse
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        // Cancel subscriptions
        cancellables.removeAll()
        
        // Clear view model
        viewModel = nil
        
        // Clear content
        contentRenderer.clearContent(in: bubbleView)
        bubbleView.prepareForReuse()
    }
}

// MARK: - Convenience Methods
extension OAChatMessageCell {
    /// Configure with simple string message
    func configure(with message: String, role: OARole) {
        let chatMessage = OAChatMessage(
            id: UUID().uuidString,
            role: role,
            content: message,
            imageData: nil
        )
        configure(with: chatMessage)
    }
}

// MARK: - Performance Monitoring
#if DEBUG
extension OAChatMessageCell {
    private func measurePerformance<T>(operation: String, block: () throws -> T) rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        if timeElapsed > 0.016 { // More than 16ms (60fps threshold)
            print("⚠️ Performance: \(operation) took \(String(format: "%.2f", timeElapsed * 1000))ms")
        }
        
        return result
    }
}
#endif
