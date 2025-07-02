//
//  MessageContentRenderer.swift
//  openAIClient
//
//  Created by Lucas on 02.07.25.
//

import UIKit

/// Protocol for rendering message content
protocol MessageContentRenderer {
    /// Render the complete message content
    func render(_ content: MessageContent, in container: UIView)
    
    /// Update existing content with new data
    func updateContent(_ content: MessageContent, in container: UIView) -> Bool
    
    /// Clear all content from the container
    func clearContent(in container: UIView)
}

/// Protocol for rendering individual content segments
protocol ContentSegmentRenderer {
    /// The type of content segment this renderer handles
    var segmentType: String { get }
    
    /// Create a new view for the segment
    func createView(for segment: ContentSegment) -> UIView
    
    /// Update an existing view with new segment data
    func updateView(_ view: UIView, with segment: ContentSegment) -> Bool
    
    /// Check if this renderer can handle the given segment
    func canRender(_ segment: ContentSegment) -> Bool
}

/// Base implementation with common functionality
class BaseContentSegmentRenderer: ContentSegmentRenderer {
    let segmentType: String
    
    init(segmentType: String) {
        self.segmentType = segmentType
    }
    
    func createView(for segment: ContentSegment) -> UIView {
        fatalError("Subclasses must implement createView")
    }
    
    func updateView(_ view: UIView, with segment: ContentSegment) -> Bool {
        // Default implementation recreates the view
        return false
    }
    
    func canRender(_ segment: ContentSegment) -> Bool {
        return segment.typeIdentifier == segmentType
    }
}

/// Configuration for content rendering
struct ContentRenderingConfiguration {
    let textColor: UIColor
    let font: UIFont
    let codeFont: UIFont
    let backgroundColor: UIColor
    let cornerRadius: CGFloat
    let padding: UIEdgeInsets
    
    static func configuration(for role: OARole) -> ContentRenderingConfiguration {
        let appearance = MessageAppearance.appearance(for: role)
        return ContentRenderingConfiguration(
            textColor: appearance.textColor,
            font: UIFont.preferredFont(forTextStyle: .body),
            codeFont: UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular),
            backgroundColor: appearance.bubbleColor,
            cornerRadius: 16,
            padding: UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        )
    }
}

/// Manager for coordinating segment renderers
@MainActor
class SegmentRendererRegistry {
    private var renderers: [String: ContentSegmentRenderer] = [:]
    
    static let shared = SegmentRendererRegistry()
    
    private init() {
        registerDefaultRenderers()
    }
    
    func register(_ renderer: ContentSegmentRenderer) {
        renderers[renderer.segmentType] = renderer
    }
    
    func renderer(for segment: ContentSegment) -> ContentSegmentRenderer? {
        return renderers[segment.typeIdentifier]
    }
    
    private func registerDefaultRenderers() {
        // Default renderers will be registered here
        // This will be populated when we implement specific renderers
    }
}