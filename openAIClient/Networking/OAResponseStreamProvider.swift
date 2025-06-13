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

    // MARK: - Properties
    
    public let model: OAModel
    private let service: OAOpenAIService
    private var previousResponseId: String?
    private var streamTask: Task<Void, Never>?
    
    // Simple observable properties for tracking current stream
    public var messages: [OAResponseMessage] = []
//    public var isStreaming = false
    public var error: String?

    // MARK: - Initialization

    public init(service: OAOpenAIService, model: OAModel) {
        self.service = service
        self.model = model
    }

    // MARK: - Public Methods

    public func sendMessage(_ text: String) {
        // Cancel any existing stream
        streamTask?.cancel()
        clearMessages()
        
        // Add user message
        let userMessage = OAResponseMessage(
            role: .user,
            content: text,
            timestamp: Date(),
            responseId: nil
        )
        messages.append(userMessage)

        // Start streaming response
        streamTask = Task {
            await streamResponse(for: text)
        }
    }

    public func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
//        isStreaming = false
    }

    public func clearMessages() {
        stopStreaming()
        messages.removeAll()
        error = nil
    }

    public func generateTitle(userMessage: String, assistantMessage: String) async throws -> String {
        let titlePrompt = """
        Based on this conversation, generate a concise, descriptive title (max 6 words):
        
        User: \(userMessage)
        Assistant: \(assistantMessage)
        
        Title:
        """
        
        let parameters = OAModelResponseParameter(
            input: .array([.message(InputMessage(role: "user", content: .text(titlePrompt)))]),
            model: .gpt41nano,
            instructions: "Generate a short, descriptive title for this conversation. Respond with only the title, no additional text.",
            maxOutputTokens: 20,
            previousResponseId: nil,
            temperature: 0.3
        )
        
        guard let defaultService = service as? OADefaultOpenAIService else {
            // Fallback to simple title generation
            let words = userMessage.components(separatedBy: .whitespaces).prefix(4)
            return words.joined(separator: " ")
        }
        
        do {
            let response = try await Task.detached {
                try await defaultService.responseCreate(parameters)
            }.value
            let generatedTitle = response.outputText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "New Chat"
            return generatedTitle.isEmpty ? "New Chat" : generatedTitle
        } catch {
            print("Failed to generate title via OpenAI: \(error)")
            // Fallback to simple title generation
            let words = userMessage.components(separatedBy: .whitespaces).prefix(4)
            return words.joined(separator: " ")
        }
    }

    // MARK: - Private Methods

    private func streamResponse(for userInput: String) async {
//        isStreaming = true
        error = nil

        // Create streaming message placeholder
        let streamingMessage = OAResponseMessage(
            role: .assistant,
            content: "",
            timestamp: Date(),
            isStreaming: true,
            responseId: nil
        )
        messages.append(streamingMessage)
        
        var accumulatedText = ""

        do {
            // Build input array with conversation history (excluding current streaming placeholder)
            var inputArray: [InputItem] = []
            
            // Add conversation history (exclude the streaming placeholder)
            let conversationHistory = messages.dropLast()
            for message in conversationHistory {
                guard !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !message.isStreaming else { continue }
                
                let content = message.content
                switch message.role {
                case .user:
                    inputArray.append(.message(InputMessage(role: "user", content: .text(content))))
                case .assistant:
                    inputArray.append(.message(InputMessage(role: "assistant", content: .text(content))))
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
                temperature: 0.7
            )

            let stream = try await service.responseCreateStream(parameters)

            for try await event in stream {
                guard !Task.isCancelled else { break }

                switch event {
                case .responseCreated:
                    break
                    
                case .outputTextDelta(let delta):
                    let deltaText = delta.delta
                    if !deltaText.isEmpty {
                        accumulatedText += deltaText
                        updateStreamingContent(accumulatedText)
                    }

                case .outputTextDone(let textDone):
                    accumulatedText = textDone.text
                    updateStreamingContent(accumulatedText)

                case .contentPartDone(let partDone):
                    if let text = partDone.part.text {
                        accumulatedText = text
                        updateStreamingContent(accumulatedText)
                    }

                case .responseCompleted(let completed):
                    previousResponseId = completed.response.id
                    let finalText = completed.response.outputText ?? accumulatedText
                    finalizeStreamingMessage(with: finalText)

                case .responseFailed(let failed):
                    throw APIError.requestFailed(description: failed.response.error?.message ?? "Stream failed")

                case .error(let errorEvent):
                    throw APIError.requestFailed(description: errorEvent.message)

                default:
                    break
                }
            }

        } catch {
            self.error = "Streaming failed: \(error.localizedDescription)"
            
            // Handle error gracefully - finalize with partial content if available
            if !accumulatedText.isEmpty {
                finalizeStreamingMessage(with: accumulatedText)
            } else {
                // Remove empty streaming message on error
                messages.removeAll { $0.isStreaming }
            }
        }

//        isStreaming = false
    }

    private func updateStreamingContent(_ content: String) {
        guard let index = messages.firstIndex(where: { $0.isStreaming }) else { return }
        messages[index].content = content
        updateStreamingTimestampFor(index: index)
    }
    
    private func updateStreamingTimestampFor(index: Array.Index) {
        messages[index].timestamp = Date.now
    }

    private func finalizeStreamingMessage(with content: String) {
        guard let index = messages.firstIndex(where: { $0.isStreaming }) else { return }
        updateStreamingTimestampFor(index: index)
        messages[index].content = content.trimmingCharacters(in: .whitespacesAndNewlines)
//        isStreaming = false
        var message = messages[index]
        message.isStreaming = false
        messages.remove(at: index)
        messages.insert(message, at: index)

    }
}

