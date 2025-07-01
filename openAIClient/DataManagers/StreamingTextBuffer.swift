//
//  StreamingTextBuffer.swift
//  openAIClient
//
//  Created by Assistant on 2025-07-01.
//

import Foundation

/// A ring buffer implementation optimized for streaming text updates.
/// Reduces memory allocations by reusing buffer space and minimizing string concatenations.
@MainActor
final class StreamingTextBuffer {
    private var buffer: [Character]
    private var head: Int = 0
    private var tail: Int = 0
    private var count: Int = 0
    private let capacity: Int
    
    /// Track the last yielded position for differential updates
    private var lastYieldedPosition: Int = 0
    
    init(capacity: Int = 16384) { // 16KB default capacity
        self.capacity = capacity
        self.buffer = Array(repeating: Character(" "), count: capacity)
    }
    
    /// Appends text to the buffer efficiently
    func append(_ text: String) {
        for char in text {
            if count == capacity {
                // Buffer is full, overwrite oldest character
                buffer[tail] = char
                tail = (tail + 1) % capacity
                head = (head + 1) % capacity
            } else {
                buffer[tail] = char
                tail = (tail + 1) % capacity
                count += 1
            }
        }
    }
    
    /// Returns the complete text in the buffer
    var fullText: String {
        if count == 0 { return "" }
        
        var result = ""
        result.reserveCapacity(count)
        
        var index = head
        for _ in 0..<count {
            result.append(buffer[index])
            index = (index + 1) % capacity
        }
        
        return result
    }
    
    /// Returns only the new text since last yield (for differential updates)
    func yieldNewText() -> String? {
        guard lastYieldedPosition < count else { return nil }
        
        let newTextCount = count - lastYieldedPosition
        var result = ""
        result.reserveCapacity(newTextCount)
        
        var index = (head + lastYieldedPosition) % capacity
        for _ in 0..<newTextCount {
            result.append(buffer[index])
            index = (index + 1) % capacity
        }
        
        lastYieldedPosition = count
        return result
    }
    
    /// Resets the buffer for reuse
    func reset() {
        head = 0
        tail = 0
        count = 0
        lastYieldedPosition = 0
    }
    
    /// Returns the current size of buffered text
    var currentSize: Int { count }
    
    /// Checks if the buffer has reached capacity
    var isFull: Bool { count == capacity }
}

/// Extension for efficient substring operations
extension StreamingTextBuffer {
    /// Extracts the last N characters without creating intermediate strings
    func suffix(_ maxLength: Int) -> String {
        guard count > 0 else { return "" }
        
        let suffixLength = min(maxLength, count)
        var result = ""
        result.reserveCapacity(suffixLength)
        
        var index = (head + count - suffixLength) % capacity
        for _ in 0..<suffixLength {
            result.append(buffer[index])
            index = (index + 1) % capacity
        }
        
        return result
    }
    
    /// Checks if the buffer ends with a specific string (useful for detecting code block markers)
    func hasSuffix(_ suffix: String) -> Bool {
        guard suffix.count <= count else { return false }
        
        let suffixChars = Array(suffix)
        var bufferIndex = (head + count - suffix.count) % capacity
        
        for suffixChar in suffixChars {
            if buffer[bufferIndex] != suffixChar {
                return false
            }
            bufferIndex = (bufferIndex + 1) % capacity
        }
        
        return true
    }
}