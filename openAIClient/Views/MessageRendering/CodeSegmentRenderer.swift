//
//  CodeSegmentRenderer.swift
//  openAIClient
//
//  Created by Lucas on 02.07.25.
//

import UIKit

/// Renderer for code block segments
final class CodeSegmentRenderer: BaseContentSegmentRenderer {
    init() {
        super.init(segmentType: "code")
    }
    
    override func createView(for segment: ContentSegment) -> UIView {
        guard case .code(let code, let language) = segment else {
            return UIView()
        }
        
        return OACodeBlockView(code: code, language: language)
    }
    
    override func updateView(_ view: UIView, with segment: ContentSegment) -> Bool {
        guard let codeView = view as? OACodeBlockView,
              case .code(let code, let language) = segment else {
            return false
        }
        
        // OACodeBlockView doesn't support in-place updates currently
        // Would need to be refactored to support this
        return false
    }
}

/// Renderer for partial code blocks during streaming
final class PartialCodeSegmentRenderer: BaseContentSegmentRenderer {
    init() {
        super.init(segmentType: "partialCode")
    }
    
    override func createView(for segment: ContentSegment) -> UIView {
        guard case .partialCode(let code, let language) = segment else {
            return UIView()
        }
        
        return OAPartialCodeBlockView(partialCode: code, possibleLanguage: language)
    }
    
    override func updateView(_ view: UIView, with segment: ContentSegment) -> Bool {
        guard let partialCodeView = view as? OAPartialCodeBlockView,
              case .partialCode(let code, let language) = segment else {
            return false
        }
        
        partialCodeView.updateContent(partialCode: code, possibleLanguage: language)
        return true
    }
}