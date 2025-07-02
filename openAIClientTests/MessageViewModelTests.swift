//
//  MessageViewModelTests.swift
//  openAIClientTests
//
//  Created by Lucas on 02.07.25.
//

import XCTest
import Combine
@testable import openAIClient

@MainActor
final class MessageViewModelTests: XCTestCase {
    
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        cancellables = []
    }
    
    override func tearDown() {
        cancellables = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitializationWithSimpleMessage() {
        // Given
        let message = OAChatMessage(
            id: "test-1",
            role: .user,
            content: "Hello, world!",
            imageData: nil
        )
        
        // When
        let viewModel = MessageViewModel(message: message)
        
        // Then
        XCTAssertEqual(viewModel.content.messageId, "test-1")
        XCTAssertEqual(viewModel.content.role, .user)
        XCTAssertFalse(viewModel.content.isStreaming)
        XCTAssertEqual(viewModel.content.segments.count, 1)
        
        guard case .text(let text) = viewModel.content.segments[0] else {
            XCTFail("Expected text segment")
            return
        }
        XCTAssertEqual(text, "Hello, world!")
        
        XCTAssertEqual(viewModel.appearance, MessageAppearance.appearance(for: .user))
    }
    
    func testInitializationWithCodeContent() {
        // Given
        let message = OAChatMessage(
            id: "test-2",
            role: .assistant,
            content: "```swift\nprint(\"Hello\")\n```",
            imageData: nil
        )
        
        // When
        let viewModel = MessageViewModel(message: message)
        
        // Then
        XCTAssertEqual(viewModel.content.segments.count, 1)
        guard case .code(let code, let language) = viewModel.content.segments[0] else {
            XCTFail("Expected code segment")
            return
        }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "print(\"Hello\")")
    }
    
    // MARK: - Streaming Update Tests
    
    func testStreamingContentUpdate() {
        // Given
        let message = OAChatMessage(
            id: "test-3",
            role: .assistant,
            content: "",
            imageData: nil
        )
        let viewModel = MessageViewModel(message: message)
        
        var contentUpdates: [MessageContent] = []
        viewModel.$content
            .sink { content in
                contentUpdates.append(content)
            }
            .store(in: &cancellables)
        
        // When
        viewModel.updateStreamingContent("Hello")
        viewModel.updateStreamingContent("Hello, world")
        viewModel.updateStreamingContent("Hello, world!")
        
        // Then
        XCTAssertEqual(contentUpdates.count, 4) // Initial + 3 updates
        XCTAssertTrue(contentUpdates[1].isStreaming)
        XCTAssertTrue(contentUpdates[2].isStreaming)
        XCTAssertTrue(contentUpdates[3].isStreaming)
        
        guard case .streamingText(let finalText) = contentUpdates[3].segments[0] else {
            XCTFail("Expected streaming text segment")
            return
        }
        XCTAssertEqual(finalText, "Hello, world!")
    }
    
    func testStreamingWithPartialCodeBlock() {
        // Given
        let message = OAChatMessage(
            id: "test-4",
            role: .assistant,
            content: "",
            imageData: nil
        )
        let viewModel = MessageViewModel(message: message)
        
        // When
        viewModel.updateStreamingContent("Here's code:\n```swift")
        
        // Then
        XCTAssertEqual(viewModel.content.segments.count, 2)
        
        guard case .text(let text) = viewModel.content.segments[0] else {
            XCTFail("Expected text segment")
            return
        }
        XCTAssertEqual(text, "Here's code:\n")
        
        guard case .partialCode(let code, let language) = viewModel.content.segments[1] else {
            XCTFail("Expected partial code segment")
            return
        }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "```swift")
    }
    
    // MARK: - Finalization Tests
    
    func testFinalizeContent() {
        // Given
        let message = OAChatMessage(
            id: "test-5",
            role: .assistant,
            content: "",
            imageData: nil
        )
        let viewModel = MessageViewModel(message: message)
        
        // When
        viewModel.updateStreamingContent("Streaming...")
        viewModel.finalizeContent("Final content with code:\n```python\nprint('Done')\n```")
        
        // Then
        XCTAssertFalse(viewModel.content.isStreaming)
        XCTAssertEqual(viewModel.content.segments.count, 2)
        
        guard case .text = viewModel.content.segments[0] else {
            XCTFail("Expected text segment")
            return
        }
        
        guard case .code(let code, let language) = viewModel.content.segments[1] else {
            XCTFail("Expected code segment")
            return
        }
        XCTAssertEqual(language, "python")
        XCTAssertEqual(code, "print('Done')")
    }
    
    func testFinalizeWithImageData() {
        // Given
        let message = OAChatMessage(
            id: "test-6",
            role: .assistant,
            content: "",
            imageData: nil
        )
        let viewModel = MessageViewModel(message: message)
        let imageData = Data(repeating: 0xFF, count: 100)
        
        // When
        viewModel.finalizeContent("Here's your image:", imageData: imageData)
        
        // Then
        XCTAssertEqual(viewModel.content.segments.count, 2)
        
        guard case .generatedImages(let images) = viewModel.content.segments[1] else {
            XCTFail("Expected generated images segment")
            return
        }
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0], imageData)
    }
    
    // MARK: - Update Detection Tests
    
    func testNeedsUpdateDetection() {
        // Given
        let originalMessage = OAChatMessage(
            id: "test-7",
            role: .user,
            content: "Original",
            imageData: nil
        )
        let viewModel = MessageViewModel(message: originalMessage)
        
        // When/Then
        let sameMessage = OAChatMessage(
            id: "test-7",
            role: .user,
            content: "Original",
            imageData: nil
        )
        XCTAssertFalse(viewModel.needsUpdate(for: sameMessage))
        
        let changedContent = OAChatMessage(
            id: "test-7",
            role: .user,
            content: "Changed",
            imageData: nil
        )
        XCTAssertTrue(viewModel.needsUpdate(for: changedContent))
        
        let changedRole = OAChatMessage(
            id: "test-7",
            role: .assistant,
            content: "Original",
            imageData: nil
        )
        XCTAssertTrue(viewModel.needsUpdate(for: changedRole))
    }
    
    // MARK: - Content Diff Tests
    
    func testContentDiffNoChange() {
        // Given
        let message = OAChatMessage(
            id: "test-8",
            role: .user,
            content: "Hello",
            imageData: nil
        )
        let viewModel = MessageViewModel(message: message)
        let oldContent = viewModel.content
        
        // When
        let diff = viewModel.getContentDiff(from: oldContent)
        
        // Then
        guard case .noChange = diff.changeType else {
            XCTFail("Expected no change")
            return
        }
        XCTAssertTrue(diff.affectedSegments.isEmpty)
    }
    
    func testContentDiffAppendOnly() {
        // Given
        let message = OAChatMessage(
            id: "test-9",
            role: .assistant,
            content: "Hello",
            imageData: nil
        )
        let viewModel = MessageViewModel(message: message)
        let oldContent = viewModel.content
        
        // When
        viewModel.updateStreamingContent("Hello, world!")
        let diff = viewModel.getContentDiff(from: oldContent)
        
        // Then
        guard case .appendToLastSegment = diff.changeType else {
            XCTFail("Expected append to last segment")
            return
        }
        XCTAssertEqual(diff.affectedSegments, [0])
    }
    
    // MARK: - Performance Tests
    
    func testStreamingUpdatePerformance() {
        // Given
        let message = OAChatMessage(
            id: "test-perf",
            role: .assistant,
            content: "",
            imageData: nil
        )
        let viewModel = MessageViewModel(message: message)
        
        // When/Then
        measure {
            for i in 0..<100 {
                viewModel.updateStreamingContent(String(repeating: "a", count: i * 10))
            }
        }
    }
}