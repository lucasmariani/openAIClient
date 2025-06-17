//
//  NetworkingStreamProvider.swift
//  openAIClient
//
//  Created by Claude on 17.06.25.
//

import Foundation

// MARK: - Pure Networking Events

public enum NetworkingStreamEvent: Sendable {
    case responseStarted(responseId: String)
    case contentDelta(text: String)
    case contentCompleted(text: String)
    case responseCompleted(response: ResponseModel)
    case streamError(NetworkingStreamError)
}

public enum NetworkingStreamError: Error, Sendable {
    case serviceFailed(underlying: Error)
    case streamCancelled
    case invalidContent
    case rateLimited
    case networkError(description: String)
    case encodingError(description: String)
}

// MARK: - Pure Networking Stream Provider

public struct NetworkingStreamProvider: Sendable {
    private let service: OpenAIService
    
    public init(service: OpenAIService) {
        self.service = service
    }
    
    // MARK: - Pure Streaming API
    
    /// Creates a pure AsyncThrowingStream for response streaming without UI concerns
    public func streamResponse(
        for text: String,
        model: Model,
        attachments: [OAAttachment] = [],
        conversationHistory: [ResponseMessage] = [],
        previousResponseId: String? = nil,
        instructions: String = "You are a helpful assistant. Use the conversation history to provide contextual responses.",
        maxOutputTokens: Int = 1000,
        temperature: Double = 0.7
    ) -> AsyncThrowingStream<NetworkingStreamEvent, Error> {
        
        return AsyncThrowingStream { continuation in
            let task = Task {
                await performPureStreaming(
                    text: text,
                    model: model,
                    attachments: attachments,
                    conversationHistory: conversationHistory,
                    previousResponseId: previousResponseId,
                    instructions: instructions,
                    maxOutputTokens: maxOutputTokens,
                    temperature: temperature,
                    continuation: continuation
                )
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    /// Generates a conversation title using the API
    public func generateTitle(
        userMessage: String,
        assistantMessage: String
    ) async throws -> String {
        let titlePrompt = """
        Based on this conversation, generate a concise, descriptive title (max 6 words):
        
        User: \(userMessage)
        Assistant: \(assistantMessage)
        
        Title:
        """
        
        let parameters = ModelResponseParameter(
            input: .array([.message(InputMessage(role: "user", content: .text(titlePrompt)))]),
            model: .gpt41nano,
            instructions: "Generate a short, descriptive title for this conversation. Respond with only the title, no additional text.",
            maxOutputTokens: 20,
            previousResponseId: nil,
            temperature: 0.3
        )
        
        do {
            // Use service protocol directly instead of casting
            let response = try await service.responseCreate(parameters)
            let generatedTitle = response.outputText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "New Chat"
            return generatedTitle.isEmpty ? "New Chat" : generatedTitle
        } catch {
            // Fallback to simple title generation
            let words = userMessage.components(separatedBy: .whitespaces).prefix(4)
            return words.joined(separator: " ")
        }
    }
    
    // MARK: - Private Implementation
    
    private func performPureStreaming(
        text: String,
        model: Model,
        attachments: [OAAttachment],
        conversationHistory: [ResponseMessage],
        previousResponseId: String?,
        instructions: String,
        maxOutputTokens: Int,
        temperature: Double,
        continuation: AsyncThrowingStream<NetworkingStreamEvent, Error>.Continuation
    ) async {
        do {
            // Build conversation input
            let parameters = try buildStreamingParameters(
                text: text,
                model: model,
                attachments: attachments,
                conversationHistory: conversationHistory,
                previousResponseId: previousResponseId,
                instructions: instructions,
                maxOutputTokens: maxOutputTokens,
                temperature: temperature
            )
            
            let serviceStream = try await service.responseCreateStream(parameters)
            var accumulatedText = ""
            
            for try await event in serviceStream {
                guard !Task.isCancelled else {
                    continuation.finish(throwing: NetworkingStreamError.streamCancelled)
                    return
                }
                
                switch event {
                case .responseCreated(let responseEvent):
                    continuation.yield(.responseStarted(responseId: responseEvent.response.id))
                    
                case .outputTextDelta(let delta):
                    let deltaText = delta.delta
                    if !deltaText.isEmpty {
                        accumulatedText += deltaText
                        continuation.yield(.contentDelta(text: deltaText))
                    }
                    
                case .outputTextDone(let textDone):
                    let finalText = textDone.text
                    if finalText != accumulatedText {
                        accumulatedText = finalText
                    }
                    continuation.yield(.contentCompleted(text: finalText))
                    
                case .contentPartDone(let partDone):
                    if let text = partDone.part.text {
                        if text != accumulatedText {
                            accumulatedText = text
                        }
                        continuation.yield(.contentCompleted(text: text))
                    }
                    
                case .responseCompleted(let completed):
                    continuation.yield(.responseCompleted(response: completed.response))
                    continuation.finish()
                    return
                    
                case .responseFailed(let failed):
                    let error = NetworkingStreamError.serviceFailed(
                        underlying: APIError.requestFailed(description: failed.response.error?.message ?? "Stream failed")
                    )
                    continuation.finish(throwing: error)
                    return
                    
                case .error(let errorEvent):
                    let error = NetworkingStreamError.networkError(description: errorEvent.message)
                    continuation.finish(throwing: error)
                    return
                    
                default:
                    break
                }
            }
        } catch {
            let streamingError: NetworkingStreamError
            if error is CancellationError {
                streamingError = .streamCancelled
            } else {
                streamingError = .serviceFailed(underlying: error)
            }
            continuation.finish(throwing: streamingError)
        }
    }
    
    private func buildStreamingParameters(
        text: String,
        model: Model,
        attachments: [OAAttachment],
        conversationHistory: [ResponseMessage],
        previousResponseId: String?,
        instructions: String,
        maxOutputTokens: Int,
        temperature: Double
    ) throws -> ModelResponseParameter {
        // Build conversation input
        var inputArray: [InputItem] = []
        
        // Add conversation history
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
        
        // Add current user message with attachments
        let currentUserMessage = try createUserInputMessage(text: text, attachments: attachments)
        inputArray.append(.message(currentUserMessage))
        
        return ModelResponseParameter(
            input: .array(inputArray),
            model: model,
            instructions: instructions,
            maxOutputTokens: maxOutputTokens,
            previousResponseId: previousResponseId,
            temperature: temperature
        )
    }
    
    private func createUserInputMessage(text: String, attachments: [OAAttachment]) throws -> InputMessage {
        if attachments.isEmpty {
            return InputMessage(role: "user", content: .text(text))
        } else {
            var contentItems: [ContentItem] = []
            
            // Add text content if present
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                contentItems.append(.text(TextContent(text: text)))
            }
            
            // Add attachments
            for attachment in attachments {
                if attachment.isImage {
                    let imageContent = ImageContent(
                        detail: "auto",
                        fileId: nil,
                        imageUrl: "data:\(attachment.mimeType);base64,\(attachment.base64EncodedData)"
                    )
                    contentItems.append(.image(imageContent))
                } else {
                    let fileContent = FileContent(
                        fileData: attachment.base64EncodedData,
                        fileId: nil,
                        filename: attachment.filename
                    )
                    contentItems.append(.file(fileContent))
                }
            }
            
            return InputMessage(role: "user", content: .array(contentItems))
        }
    }
}
