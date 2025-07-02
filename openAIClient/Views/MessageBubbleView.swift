//
//  MessageBubbleView.swift
//  openAIClient
//
//  Created by Lucas on 02.07.25.
//

import UIKit

/// Container view for message content with bubble styling
final class MessageBubbleView: UIView {
    // MARK: - Properties
    private let contentStackView = UIStackView()
    private var currentAppearance: MessageAppearance?
    private var widthConstraint: NSLayoutConstraint?
    private var alignmentConstraints: [NSLayoutConstraint] = []
    
    // Track current segment views for efficient updates
    private var segmentViews: [UIView] = []
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupView() {
        // Configure self
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        
        // Configure content stack view
        contentStackView.axis = .vertical
        contentStackView.spacing = 8
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(contentStackView)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            contentStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            contentStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])
    }
    
    // MARK: - Public Methods
    
    /// Update appearance based on message role
    func updateAppearance(_ appearance: MessageAppearance) {
        // Only update if appearance changed
        guard currentAppearance != appearance else { return }
        
        currentAppearance = appearance
        
        // Update bubble styling
        backgroundColor = appearance.bubbleColor
        layer.cornerRadius = 16
        
        // Update role tag for child views
        tag = appearance.textColor == .white ? OARole.user.rawValue : OARole.assistant.rawValue
        
        // Propagate tag to all text views for proper coloring
        updateTextViewTags(in: contentStackView, tag: tag)
    }
    
    /// Update alignment constraints
    func updateAlignment(_ alignment: MessageAppearance.MessageAlignment, maxWidthMultiplier: CGFloat, in containerView: UIView) {
        // Remove existing constraints
        alignmentConstraints.forEach { $0.isActive = false }
        alignmentConstraints.removeAll()
        
        widthConstraint?.isActive = false
        
        // Create new constraints based on alignment
        switch alignment {
        case .leading:
            alignmentConstraints = [
                leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor)
            ]
        case .trailing:
            alignmentConstraints = [
                leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor),
                trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
            ]
        }
        
        // Add width constraint
        widthConstraint = widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, multiplier: maxWidthMultiplier)
        widthConstraint?.isActive = true
        
        // Activate alignment constraints
        NSLayoutConstraint.activate(alignmentConstraints)
    }
    
    /// Add content views from segments
    func setContentViews(_ views: [UIView]) {
        // Clear existing views
        clearContent()
        
        // Add new views
        segmentViews = views
        views.forEach { view in
            contentStackView.addArrangedSubview(view)
            
            // Ensure text views have proper tag for coloring
            if let textView = view as? UITextView {
                textView.tag = tag
            }
        }
    }
    
    /// Update a specific segment view
    func updateSegmentView(at index: Int, with newView: UIView) {
        guard index < segmentViews.count else { return }
        
        let oldView = segmentViews[index]
        contentStackView.insertArrangedSubview(newView, at: index)
        oldView.removeFromSuperview()
        
        segmentViews[index] = newView
        
        // Ensure text views have proper tag
        if let textView = newView as? UITextView {
            textView.tag = tag
        }
    }
    
    /// Clear all content
    func clearContent() {
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        segmentViews.removeAll()
    }
    
    /// Get current segment views
    func getSegmentViews() -> [UIView] {
        return segmentViews
    }
    
    // MARK: - Private Methods
    
    private func updateTextViewTags(in view: UIView, tag: Int) {
        if let textView = view as? UITextView {
            textView.tag = tag
        }
        
        for subview in view.subviews {
            updateTextViewTags(in: subview, tag: tag)
        }
    }
}

// MARK: - Reuse Support
extension MessageBubbleView {
    /// Prepare for reuse in table view cells
    func prepareForReuse() {
        clearContent()
        currentAppearance = nil
        
        // Reset constraints
        alignmentConstraints.forEach { $0.isActive = false }
        alignmentConstraints.removeAll()
        widthConstraint?.isActive = false
        widthConstraint = nil
    }
}