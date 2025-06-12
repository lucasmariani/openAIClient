//
//  ResponseStreamProvider.swift
//  openAIClient
//
//  Created by Lucas on 11.06.25.
//

import SwiftUI

@MainActor
@Observable
public class OAResponseStreamProvider {

    public let model: OAModel
    // MARK: - Initialization

    public init(service: OAOpenAIService, model: OAModel) {
        self.service = service
        self.model = model
    }

    // MARK: - Message Model

    public struct OAResponseMessage: Identifiable {
        public let id = UUID()
        public let role: MessageRole
        public var content: String
        public var timestamp: Date
        public var isStreaming = false
        public let responseId: String?

        public enum MessageRole {
            case user
            case assistant
        }
    }

    public var messages: [OAResponseMessage] = []
    public var isStreaming = false
    public var currentStreamingMessage: OAResponseMessage?
    public var error: String?
    
    // Track streaming completion state
    private var isTextComplete = false
    private var isContentPartComplete = false

    // MARK: - Public Methods

    public func sendMessage(_ text: String) {
        // Cancel any existing stream
        streamTask?.cancel()

        // Add user message
        let userMessage = OAResponseMessage(
            role: .user,
            content: text,
            timestamp: Date(),
            responseId: nil)
        messages.append(userMessage)

        // Start streaming response
        streamTask = Task {
            await streamResponse(for: text)
        }
    }

    public func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil

        // Finalize current streaming message
        if var message = currentStreamingMessage {
            message.isStreaming = false
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = message
            }
        }

        currentStreamingMessage = nil
        isStreaming = false
        
        // Reset completion tracking
        isTextComplete = false
        isContentPartComplete = false
    }

    public func clearConversation() {
        stopStreaming()
        messages.removeAll()
        previousResponseId = nil
        error = nil
    }

    private let service: OAOpenAIService
    private var previousResponseId: String?
    private var streamTask: Task<Void, Never>?

    // MARK: - Private Methods

    private func streamResponse(for userInput: String) async {
        isStreaming = true
        error = nil

        // Create streaming message placeholder with timestamp slightly after user message
        let streamingMessage = OAResponseMessage(
            role: .assistant,
            content: "",
            timestamp: Date(),
            isStreaming: true,
            responseId: nil)
        messages.append(streamingMessage)
        currentStreamingMessage = streamingMessage
        
        var accumulatedText = ""
        isTextComplete = false
        isContentPartComplete = false

        do {
            // Build input array with conversation history
            var inputArray: [InputItem] = []

            // Add conversation history (exclude the current streaming placeholder)
            let conversationHistory = messages.dropLast(2) // Only drop the streaming placeholder
            for message in conversationHistory {
                // Skip empty messages and messages that are still streaming
                guard !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !message.isStreaming else { continue }
                
                let content = message.content
                switch message.role {
                case .user:
                    inputArray.append(.message(InputMessage(
                        role: "user",
                        content: .text(content))))
                case .assistant:
                    inputArray.append(.message(InputMessage(
                        role: "assistant",
                        content: .text(content))))
                }
            }

            // Add current user message
            inputArray.append(.message(InputMessage(role: "user", content: .text(userInput))))

            let parameters = OAModelResponseParameter(
                input: .array(inputArray),
                model: self.model,
                instructions: "You are a helpful assistant. Use the conversation history to provide contextual responses.",
                maxOutputTokens: 1000,
                previousResponseId: previousResponseId,
                temperature: 0.7)

            let stream = try await service.responseCreateStream(parameters)

            for try await event in stream {
                guard !Task.isCancelled else {
                    break
                }

                switch event {
                case .responseCreated(let event):
                    // Response created event - we'll get the ID in responseCompleted
                    updateStreamingMessage(with: event.response.createdAt) // response.createdAt
                    break

                case .outputTextDelta(let delta):
                    // Safely handle delta updates and prevent character truncation
                    let deltaText = delta.delta
                    if !deltaText.isEmpty {
                        accumulatedText += deltaText
                        updateStreamingMessage(with: accumulatedText)
                        print("📝 Delta received. Current length: \(accumulatedText.count)")
                    }

                case .outputTextDone(let textDone):
                    // Use the final complete text from outputTextDone - this is authoritative
                    let finalText = textDone.text
                    accumulatedText = finalText // Override with complete text
                    isTextComplete = true
                    updateStreamingMessage(with: finalText)
                    print("✅ Text completion received. Final text length: \(finalText.count)")

                case .contentPartDone(let partDone):
                    // Ensure content part is fully processed
                    if let text = partDone.part.text {
                        accumulatedText = text
                        isContentPartComplete = true
                        updateStreamingMessage(with: text)
                        print("✅ Content part completion received. Text length: \(text.count)")
                    }

                case .responseCompleted(let completed):
                    // Update previous response ID for conversation continuity
                    previousResponseId = completed.response.id

                    // Get final text from the completed response if available, otherwise use accumulated
                    let finalText = completed.response.outputText ?? accumulatedText
                    
                    // Only finalize if text is complete or no text was expected
                    if isTextComplete || isContentPartComplete || accumulatedText.isEmpty {
                        finalizeStreamingMessage(with: finalText, responseId: completed.response.id)
                        print("✅ Response completed. Using final text length: \(finalText.count)")
                    } else {
                        // Fallback: finalize with accumulated text if completion events weren't received
                        print("⚠️ Response completed without text completion events. Using accumulated text.")
                        finalizeStreamingMessage(with: accumulatedText, responseId: completed.response.id)
                    }

                case .responseFailed(let failed):
                    throw APIError.requestFailed(
                        description: failed.response.error?.message ?? "Stream failed")

                case .error(let errorEvent):
                    throw APIError.requestFailed(
                        description: errorEvent.message)

                default:
                    // Handle other events as needed
                    break
                }
            }

        } catch {
            let errorMessage = "Streaming failed: \(error.localizedDescription)"
            self.error = errorMessage
            print("Streaming error: \(errorMessage)")

            // Handle the error gracefully - finalize with partial content if available
            if let _ = currentStreamingMessage, !accumulatedText.isEmpty {
                finalizeStreamingMessage(with: accumulatedText, responseId: "error_\(UUID().uuidString)")
            } else {
                // Remove empty streaming message on error
                if let streamingId = currentStreamingMessage?.id {
                    messages.removeAll { $0.id == streamingId }
                }
            }
        }

        currentStreamingMessage = nil
        isStreaming = false
        
        // Reset completion tracking
        isTextComplete = false
        isContentPartComplete = false
    }

    private func updateStreamingMessage(with content: String) {
        guard
            let messageId = currentStreamingMessage?.id,
            let index = messages.firstIndex(where: { $0.id == messageId })
        else {
            return
        }

        // Update content and ensure we don't lose the last character
        messages[index].content = content
        
        // Update the current streaming message reference
        currentStreamingMessage?.content = content
    }

    private func updateStreamingMessage(with dateString: Int) {
        guard
            let messageId = currentStreamingMessage?.id,
            let index = messages.firstIndex(where: { $0.id == messageId })
        else {
            return
        }
        let date = Date(timeIntervalSince1970: TimeInterval(dateString))
        messages[index].timestamp = date
    }

    private func finalizeStreamingMessage(with content: String, responseId: String) {
        guard
            let messageId = currentStreamingMessage?.id,
            let index = messages.firstIndex(where: { $0.id == messageId })
        else {
            return
        }

        // Update the existing message in place to avoid creating duplicates
        var message = messages[index]
        message.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        message.isStreaming = false
        messages[index] = message
        print("finalizeStreamingMessage CREATED AT: \(message.timestamp)")

    }
}

