//
//  CodeSegmentRenderer.swift
//  openAIClient
//
//  Created by Lucas on 02.07.25.
//

import UIKit

/// Renderer for code block segments
@MainActor
final class CodeSegmentRenderer: BaseContentSegmentRenderer {
    init() {
        super.init(segmentType: "code")
    }
    
    override func createView(for segment: ContentSegment, role: OARole) -> UIView {
        guard case .code(let code, let language) = segment else {
            return UIView()
        }
        
        return OACodeBlockView(code: code, language: language)
    }
    
    override func updateView(_ view: UIView, with segment: ContentSegment, role: OARole) -> Bool {
        guard let _ = view as? OACodeBlockView,
              case .code(_, _) = segment else {
            return false
        }
        
        // OACodeBlockView doesn't support in-place updates currently
        // Would need to be refactored to support this
        return false
    }
}

/// Renderer for partial code blocks during streaming
@MainActor
final class PartialCodeSegmentRenderer: BaseContentSegmentRenderer {
    init() {
        super.init(segmentType: "partialCode")
    }
    
    override func createView(for segment: ContentSegment, role: OARole) -> UIView {
        guard case .partialCode(let code, let language) = segment else {
            return UIView()
        }
        
        return OAPartialCodeBlockView(partialCode: code, possibleLanguage: language)
    }
    
    override func updateView(_ view: UIView, with segment: ContentSegment, role: OARole) -> Bool {
        guard let partialCodeView = view as? OAPartialCodeBlockView,
              case .partialCode(let code, let language) = segment else {
            return false
        }
        
        partialCodeView.updateContent(partialCode: code, possibleLanguage: language)
        return true
    }
}