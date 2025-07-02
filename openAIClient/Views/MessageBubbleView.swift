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
        contentStackView.backgroundColor = .clear
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
        // Use a more reliable method to detect white color since UIColor equality is unreliable
        tag = isWhiteColor(appearance.textColor) ? OARole.user.hashValue : OARole.assistant.hashValue
        
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
    
    /// Add content views from segments using differential updates
    func setContentViews(_ views: [UIView]) {
        // Fast path: if views are identical, do nothing
        if views.count == segmentViews.count && 
           zip(views, segmentViews).allSatisfy({ areViewsEquivalent($0, $1) }) {
            return
        }
        
        // Special case: first time setup or empty views
        if segmentViews.isEmpty {
            segmentViews = views
            views.forEach { view in
                contentStackView.addArrangedSubview(view)
                configureView(view)
            }
            return
        }
        
        // Perform differential update to minimize UI disruption
        performDifferentialUpdate(to: views)
    }
    
    /// Update a specific segment view efficiently
    func updateSegmentView(at index: Int, with newView: UIView) {
        guard index < segmentViews.count else { return }
        
        let oldView = segmentViews[index]
        
        // Try in-place update first
        if canUpdateInPlace(oldView, with: newView) {
            updateViewInPlace(oldView, with: newView)
        } else {
            // Replace the view
            contentStackView.insertArrangedSubview(newView, at: index)
            oldView.removeFromSuperview()
            segmentViews[index] = newView
            configureView(newView)
        }
    }
    
    /// Clear all content - only use when completely resetting content
    /// WARNING: This causes UI flashing during streaming - prefer setContentViews() instead
    func clearContent() {
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        segmentViews.removeAll()
    }
    
    /// Get current segment views
    func getSegmentViews() -> [UIView] {
        return segmentViews
    }
    
    // MARK: - Private Methods
    
    private func performDifferentialUpdate(to newViews: [UIView]) {
        let oldViews = segmentViews
        var finalViews: [UIView] = []

        // Strategy: Try to reuse existing views when possible, minimize creation/destruction
        
        // Track which old views we've used for reuse
        var unusedOldViews = Array(oldViews)
        
        // Process each new view position
        for (newIndex, newView) in newViews.enumerated() {
            var viewToUse: UIView?
            
            // First, check if we can reuse the view at the same position
            if newIndex < oldViews.count {
                let oldViewAtPosition = oldViews[newIndex]
                if canUpdateInPlace(oldViewAtPosition, with: newView) {
                    updateViewInPlace(oldViewAtPosition, with: newView)
                    viewToUse = oldViewAtPosition
                    unusedOldViews.removeAll { $0 === oldViewAtPosition }
                }
            }
            
            // If no same-position reuse, try to find any compatible view
            if viewToUse == nil {
                if let compatibleIndex = unusedOldViews.firstIndex(where: { canUpdateInPlace($0, with: newView) }) {
                    let compatibleView = unusedOldViews.remove(at: compatibleIndex)
                    updateViewInPlace(compatibleView, with: newView)
                    
                    // Move it to the correct position
                    moveViewToPosition(compatibleView, at: newIndex)
                    viewToUse = compatibleView
                }
            }
            
            // If no reusable view found, use the new view
            if viewToUse == nil {
                insertViewAtPosition(newView, at: newIndex)
                configureView(newView)
                viewToUse = newView
            }
            
            finalViews.append(viewToUse!)
        }
        
        // Remove any old views that weren't reused
        unusedOldViews.forEach { view in
            view.removeFromSuperview()
        }
        
        // Update our tracking
        segmentViews = finalViews
    }
    
    private func canUpdateInPlace(_ oldView: UIView, with newView: UIView) -> Bool {
        // Check if views are compatible for in-place updates
        let oldType = type(of: oldView)
        let newType = type(of: newView)
        
        // Must be exactly the same type
        guard oldType == newType else { return false }
        
        // For UITextView, we can always update the content
        if oldView is UITextView && newView is UITextView {
            return true
        }
        
        // For other view types, be conservative for now
        // In the future, we could add more sophisticated checks
        return false
    }
    
    private func updateViewInPlace(_ oldView: UIView, with newView: UIView) {
        // Update oldView's content to match newView
        if let oldTextView = oldView as? UITextView,
           let newTextView = newView as? UITextView {
            
            // Only update if content actually changed
            if !areTextViewsEqual(oldTextView, newTextView) {
                oldTextView.attributedText = newTextView.attributedText
                oldTextView.accessibilityIdentifier = newTextView.accessibilityIdentifier
            }
        }
        
        // Update any other properties that might have changed
        configureView(oldView)
    }
    
    private func moveViewToPosition(_ view: UIView, at index: Int) {
        // Remove and re-insert at correct position
        view.removeFromSuperview()
        insertViewAtPosition(view, at: index)
    }
    
    private func insertViewAtPosition(_ view: UIView, at index: Int) {
        // Insert view at specific position in stack
        if index >= contentStackView.arrangedSubviews.count {
            contentStackView.addArrangedSubview(view)
        } else {
            contentStackView.insertArrangedSubview(view, at: index)
        }
    }
    
    private func configureView(_ view: UIView) {
        // Configure view properties
        if let textView = view as? UITextView {
            textView.tag = tag
        }
    }
    
    private func areViewsEquivalent(_ view1: UIView, _ view2: UIView) -> Bool {
        // Check if two views have equivalent content
        guard type(of: view1) == type(of: view2) else { return false }
        
        if let textView1 = view1 as? UITextView,
           let textView2 = view2 as? UITextView {
            return areTextViewsEqual(textView1, textView2)
        }
        
        // For other view types, use reference equality for now
        return view1 === view2
    }
    
    private func areTextViewsEqual(_ textView1: UITextView, _ textView2: UITextView) -> Bool {
        // Compare attributed text content
        let text1 = textView1.attributedText
        let text2 = textView2.attributedText
        
        if text1 == nil && text2 == nil { return true }
        if text1 == nil || text2 == nil { return false }
        
        return text1!.isEqual(to: text2!)
    }
    
    private func updateTextViewTags(in view: UIView, tag: Int) {
        if let textView = view as? UITextView {
            textView.tag = tag
        }
        
        for subview in view.subviews {
            updateTextViewTags(in: subview, tag: tag)
        }
    }
    
    /// Reliably detect if a color is white by checking RGB components
    private func isWhiteColor(_ color: UIColor) -> Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        // Try to get RGB components
        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            // Check if all RGB components are 1.0 (white)
            return red >= 0.99 && green >= 0.99 && blue >= 0.99
        }
        
        // Fallback: check if it's the system white color
        return color == UIColor.white || color == UIColor.systemBackground
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
