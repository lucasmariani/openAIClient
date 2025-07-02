//
//  MessageContentParserTests.swift
//  openAIClientTests
//
//  Created by Lucas on 02.07.25.
//

import XCTest
@testable import openAIClient

final class MessageContentParserTests: XCTestCase {
    
    var parser: MessageContentParser!
    
    override func setUp() {
        super.setUp()
        parser = MessageContentParser()
    }
    
    override func tearDown() {
        parser = nil
        super.tearDown()
    }
    
    // MARK: - Basic Content Tests
    
    func testParseSimpleText() {
        // Given
        let content = "This is a simple text message."
        
        // When
        let segments = parser.parseContent(content, isStreaming: false)
        
        // Then
        XCTAssertEqual(segments.count, 1)
        guard case .text(let text) = segments[0] else {
            XCTFail("Expected text segment")
            return
        }
        XCTAssertEqual(text, content)
    }
    
    func testParseEmptyContent() {
        // Given
        let content = ""
        
        // When
        let segments = parser.parseContent(content, isStreaming: false)
        
        // Then
        XCTAssertTrue(segments.isEmpty)
    }
    
    // MARK: - Code Block Tests
    
    func testParseCompleteCodeBlock() {
        // Given
        let content = """
        Here is some code:
        ```swift
        let greeting = "Hello, World!"
        print(greeting)
        ```
        And some text after.
        """
        
        // When
        let segments = parser.parseContent(content, isStreaming: false)
        
        // Then
        XCTAssertEqual(segments.count, 3)
        
        guard case .text(let beforeText) = segments[0] else {
            XCTFail("Expected text segment")
            return
        }
        XCTAssertEqual(beforeText, "Here is some code:\n")
        
        guard case .code(let code, let language) = segments[1] else {
            XCTFail("Expected code segment")
            return
        }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "let greeting = \"Hello, World!\"\nprint(greeting)")
        
        guard case .text(let afterText) = segments[2] else {
            XCTFail("Expected text segment")
            return
        }
        XCTAssertEqual(afterText, "\nAnd some text after.")
    }
    
    func testParseMultipleCodeBlocks() {
        // Given
        let content = """
        ```python
        def hello():
            print("Hello")
        ```
        Middle text
        ```javascript
        console.log("Hi");
        ```
        """
        
        // When
        let segments = parser.parseContent(content, isStreaming: false)
        
        // Then
        XCTAssertEqual(segments.count, 3)
        
        guard case .code(let pythonCode, let pythonLang) = segments[0] else {
            XCTFail("Expected code segment")
            return
        }
        XCTAssertEqual(pythonLang, "python")
        XCTAssertTrue(pythonCode.contains("def hello()"))
        
        guard case .text(let middleText) = segments[1] else {
            XCTFail("Expected text segment")
            return
        }
        XCTAssertEqual(middleText, "\nMiddle text\n")
        
        guard case .code(let jsCode, let jsLang) = segments[2] else {
            XCTFail("Expected code segment")
            return
        }
        XCTAssertEqual(jsLang, "javascript")
        XCTAssertTrue(jsCode.contains("console.log"))
    }
    
    // MARK: - Streaming Tests
    
    func testParseStreamingWithIncompleteCodeBlock() {
        // Given
        let content = """
        Here is some code:
        ```swift
        let greeting = "Hello
        """
        
        // When
        let segments = parser.parseContent(content, isStreaming: true)
        
        // Then
        XCTAssertEqual(segments.count, 2)
        
        guard case .text(let text) = segments[0] else {
            XCTFail("Expected text segment")
            return
        }
        XCTAssertEqual(text, "Here is some code:\n")
        
        guard case .partialCode(let code, let language) = segments[1] else {
            XCTFail("Expected partial code segment")
            return
        }
        XCTAssertEqual(language, "swift")
        XCTAssertTrue(code.contains("```swift"))
    }
    
    func testParseStreamingWithOnlyPartialCodeMarker() {
        // Given
        let content = "```sw"
        
        // When
        let segments = parser.parseContent(content, isStreaming: true)
        
        // Then
        XCTAssertEqual(segments.count, 1)
        
        guard case .partialCode(let code, let language) = segments[0] else {
            XCTFail("Expected partial code segment")
            return
        }
        XCTAssertEqual(language, "sw")
        XCTAssertEqual(code, "```sw")
    }
    
    func testParseStreamingTextWithoutCodeBlocks() {
        // Given
        let content = "This is streaming text that might have more content coming..."
        
        // When
        let segments = parser.parseContent(content, isStreaming: true)
        
        // Then
        XCTAssertEqual(segments.count, 1)
        
        guard case .streamingText(let text) = segments[0] else {
            XCTFail("Expected streaming text segment")
            return
        }
        XCTAssertEqual(text, content)
    }
    
    // MARK: - Attachment Tests
    
    func testParseContentWithAttachments() {
        // Given
        let content = "Check out this file:"
        let attachment = OAAttachment(
            filename: "test.pdf",
            data: Data(),
            mimeType: "application/pdf"
        )
        
        // When
        let segments = parser.parseContent(
            content,
            attachments: [attachment],
            isStreaming: false
        )
        
        // Then
        XCTAssertEqual(segments.count, 2)
        
        guard case .attachments(let attachments) = segments[0] else {
            XCTFail("Expected attachments segment")
            return
        }
        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments[0].filename, "test.pdf")
        
        guard case .text(let text) = segments[1] else {
            XCTFail("Expected text segment")
            return
        }
        XCTAssertEqual(text, content)
    }
    
    // MARK: - Image Data Tests
    
    func testParseContentWithGeneratedImage() {
        // Given
        let content = "Here's the generated image:"
        let imageData = Data(repeating: 0xFF, count: 100)
        
        // When
        let segments = parser.parseContent(
            content,
            imageData: imageData,
            isStreaming: false
        )
        
        // Then
        XCTAssertEqual(segments.count, 2)
        
        guard case .text(let text) = segments[0] else {
            XCTFail("Expected text segment")
            return
        }
        XCTAssertEqual(text, content)
        
        guard case .generatedImages(let images) = segments[1] else {
            XCTFail("Expected generated images segment")
            return
        }
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0], imageData)
    }
    
    // MARK: - Complex Content Tests
    
    func testParseComplexMixedContent() {
        // Given
        let content = """
        Here's a complex example:
        ```python
        def calculate(x, y):
            return x + y
        ```
        And now some JavaScript:
        ```javascript
        const result = calculate(5, 3);
        ```
        The end.
        """
        let attachment = OAAttachment(
            filename: "data.json",
            data: Data(),
            mimeType: "application/json"
        )
        let imageData = Data(repeating: 0xAA, count: 50)
        
        // When
        let segments = parser.parseContent(
            content,
            attachments: [attachment],
            imageData: imageData,
            isStreaming: false
        )
        
        // Then
        XCTAssertEqual(segments.count, 7) // attachment + 5 text/code segments + image
        
        guard case .attachments = segments[0] else {
            XCTFail("Expected attachments segment first")
            return
        }
        
        guard case .generatedImages = segments[6] else {
            XCTFail("Expected generated images segment last")
            return
        }
    }
    
    // MARK: - Performance Tests
    
    func testParsePerformanceWithLargeContent() {
        // Given
        let largeContent = String(repeating: "This is a test line. ", count: 1000)
        
        // When/Then
        measure {
            _ = parser.parseContent(largeContent, isStreaming: false)
        }
    }
    
    func testStreamingParsePerformance() {
        // Given
        let streamingContent = """
        Here's some code:
        ```swift
        \(String(repeating: "let value = 42\n", count: 100))
        ```
        """
        
        // When/Then
        measure {
            _ = parser.parseContent(streamingContent, isStreaming: true)
        }
    }
}