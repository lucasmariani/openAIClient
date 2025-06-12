//
//  ResponseStreamProvider.swift
//  openAIClient
//
//  Created by Lucas on 11.06.25.
//

import SwiftOpenAI
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
        public let timestamp: Date
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

        // Create streaming message placeholder
        let streamingMessage = OAResponseMessage(
            role: .assistant,
            content: "",
            timestamp: Date(),
            isStreaming: true,
            responseId: nil)
        messages.append(streamingMessage)
        currentStreamingMessage = streamingMessage
        
        var accumulatedText = ""

        do {
            // Build input array with conversation history
            var inputArray: [InputItem] = []

            // Add conversation history (exclude the current streaming placeholder)
            let conversationHistory = messages.dropLast() // Only drop the streaming placeholder
            for message in conversationHistory {
                // Skip empty messages and messages that are still streaming
                guard !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !message.isStreaming else { continue }
                
                let content = message.content
                switch message.role {
                case .user:
                    inputArray.append(.message(InputMessage(role: "user", content: .text(content))))
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
                previousResponseId: previousResponseId, temperature: 0.7)

            let stream = try await service.responseCreateStream(parameters)

            for try await event in stream {
                guard !Task.isCancelled else {
                    break
                }

                switch event {
                case .responseCreated:
                    // Response created event - we'll get the ID in responseCompleted
                    break

                case .outputTextDelta(let delta):
                    // Safely handle delta updates and prevent character truncation
                    let deltaText = delta.delta
                    if !deltaText.isEmpty {
                        accumulatedText += deltaText
                        updateStreamingMessage(with: accumulatedText)
                    }

                case .responseCompleted(let completed):
                    // Update previous response ID for conversation continuity
                    previousResponseId = completed.response.id

                    // Finalize the message
                    finalizeStreamingMessage(
                        with: accumulatedText,
                        responseId: completed.response.id)

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
            if let streamingMessage = currentStreamingMessage, !accumulatedText.isEmpty {
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
    }
}

