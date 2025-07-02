//
//  CompositeMessageRenderer.swift
//  openAIClient
//
//  Created by Lucas on 02.07.25.
//

import UIKit

/// Composite renderer that manages multiple segment renderers
@MainActor
final class CompositeMessageRenderer: MessageContentRenderer {
    // MARK: - Properties
    private let registry: SegmentRendererRegistry
    private var segmentViewsCache: [String: [UIView]] = [:] // messageId -> views
    
    // MARK: - Initialization
    init(registry: SegmentRendererRegistry = .shared) {
        self.registry = registry
        registerDefaultRenderers()
    }
    
    // MARK: - MessageContentRenderer
    
    func render(_ content: MessageContent, in container: UIView) {
        guard let bubbleView = container as? MessageBubbleView else {
            print("Warning: Container is not a MessageBubbleView")
            return
        }
        
        // Clear existing content
        clearContent(in: container)
        
        // Create views for each segment
        var segmentViews: [UIView] = []
        
        for segment in content.segments {
            if let renderer = registry.renderer(for: segment) {
                let view = renderer.createView(for: segment)
                segmentViews.append(view)
            } else {
                print("Warning: No renderer found for segment type: \(segment.typeIdentifier)")
            }
        }
        
        // Set content views in bubble
        bubbleView.setContentViews(segmentViews)
        
        // Cache the views for potential updates
        segmentViewsCache[content.messageId] = segmentViews
    }
    
    func updateContent(_ content: MessageContent, in container: UIView) -> Bool {
        guard let bubbleView = container as? MessageBubbleView else {
            return false
        }
        
        // Get cached views
        guard let cachedViews = segmentViewsCache[content.messageId] else {
            // No cached views, perform full render
            render(content, in: container)
            return true
        }
        
        // Compare old and new content
        let oldContent = reconstructContent(from: cachedViews, messageId: content.messageId)
        let diff = ContentDiff.compare(old: oldContent, new: content)
        
        switch diff.changeType {
        case .noChange:
            return true
            
        case .appendToLastSegment:
            // Optimized path for append-only updates
            if let lastIndex = content.segments.indices.last,
               let lastSegment = content.segments.last,
               let renderer = registry.renderer(for: lastSegment),
               lastIndex < cachedViews.count {
                
                let lastView = cachedViews[lastIndex]
                if renderer.updateView(lastView, with: lastSegment) {
                    return true
                }
            }
            // Fall through to full update if incremental update failed
            fallthrough
            
        case .segmentUpdate(let index):
            // Update specific segment
            if index < content.segments.count && index < cachedViews.count {
                let segment = content.segments[index]
                if let renderer = registry.renderer(for: segment) {
                    let oldView = cachedViews[index]
                    
                    // Try to update in place
                    if renderer.updateView(oldView, with: segment) {
                        return true
                    } else {
                        // Replace with new view
                        let newView = renderer.createView(for: segment)
                        bubbleView.updateSegmentView(at: index, with: newView)
                        
                        // Update cache
                        var updatedViews = cachedViews
                        updatedViews[index] = newView
                        segmentViewsCache[content.messageId] = updatedViews
                        return true
                    }
                }
            }
            // Fall through to full update if segment update failed
            fallthrough
            
        case .fullUpdate:
            // Perform full re-render
            render(content, in: container)
            return true
        }
    }
    
    func clearContent(in container: UIView) {
        guard let bubbleView = container as? MessageBubbleView else {
            return
        }
        
        bubbleView.clearContent()
        
        // Clear cache for this container
        // Note: We might want to keep some cache for reuse
        segmentViewsCache.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func registerDefaultRenderers() {
        // Register all default renderers
        registry.register(TextSegmentRenderer())
        registry.register(StreamingTextSegmentRenderer())
        registry.register(CodeSegmentRenderer())
        registry.register(PartialCodeSegmentRenderer())
        registry.register(AttachmentSegmentRenderer())
        registry.register(GeneratedImageSegmentRenderer())
    }
    
    /// Reconstruct content from cached views (for diff calculation)
    private func reconstructContent(from views: [UIView], messageId: String) -> MessageContent {
        // This is a simplified reconstruction - in practice, we might want to
        // store more metadata about the original segments
        var segments: [ContentSegment] = []
        
        for view in views {
            if let textView = view as? UITextView {
                segments.append(.text(textView.text ?? ""))
            } else if view is OACodeBlockView {
                // We can't easily extract the original code/language from the view
                // This is a limitation of the current approach
                segments.append(.code("", language: ""))
            } else if view is OAPartialCodeBlockView {
                segments.append(.partialCode("", language: ""))
            }
            // Add other view type checks as needed
        }
        
        return MessageContent(
            segments: segments,
            isStreaming: false,
            messageId: messageId,
            role: .assistant
        )
    }
}

// MARK: - Performance Optimization
extension CompositeMessageRenderer {
    /// Clear old cache entries to prevent memory growth
    func clearOldCache(keeping messageIds: Set<String>) {
        let keysToRemove = segmentViewsCache.keys.filter { !messageIds.contains($0) }
        keysToRemove.forEach { segmentViewsCache.removeValue(forKey: $0) }
    }
    
    /// Preload renderers for better performance
    func preloadRenderers(for segments: [ContentSegment]) {
        for segment in segments {
            _ = registry.renderer(for: segment)
        }
    }
}