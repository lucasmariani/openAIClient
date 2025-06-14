//
//  ResponseStreamProvider.swift
//  openAIClient
//
//  Created by Lucas on 11.06.25.
//

import Foundation

// MARK: - Streaming Events and Errors

public enum StreamingEvent: Sendable {
    case messageStarted(OAResponseMessage)
    case messageUpdated(OAResponseMessage)
    case messageCompleted(OAResponseMessage)
    case streamError(StreamingError)
}

public enum StreamingError: Error, Sendable {
    case serviceFailed(underlying: Error)
    case streamCancelled
    case invalidContent
    case rateLimited
    case networkError(description: String)
}

@MainActor
@Observable
public class OAResponseStreamProvider {

    // MARK: - Properties
    
    public let model: OAModel
    private let service: OAOpenAIService
    private var previousResponseId: String?
    private var streamTask: Task<Void, Never>?
    
    // Observable properties for tracking current stream
    public var messages: [OAResponseMessage] = []
    public var error: String?
    
    // AsyncSequence-based streaming support
    private var currentStreamContinuation: AsyncStream<StreamingEvent>.Continuation?
    private var sharedStream: AsyncStream<StreamingEvent>?
    
    // Throttling support for back-pressure management
    private var lastUpdateTime: Date = Date()
    private let throttleInterval: TimeInterval = 0.05 // 50ms minimum between updates

    // MARK: - Initialization

    public init(service: OAOpenAIService, model: OAModel) {
        self.service = service
        self.model = model
    }

    // MARK: - Public Methods

    public func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
    }

    public func clearMessages() {
        stopStreaming()
        messages.removeAll()
        error = nil
        // Clean up any active streams
        currentStreamContinuation?.finish()
        currentStreamContinuation = nil
        sharedStream = nil
    }
    
    // MARK: - Enhanced AsyncSequence API
    
    /// Creates a shareable AsyncSequence for streaming events with back-pressure support
    public func streamEvents(for text: String) -> AsyncStream<StreamingEvent> {
        // If we already have a shared stream for this input, return it
        if let existingStream = sharedStream {
            return existingStream
        }
        
        let stream = AsyncStream<StreamingEvent> { continuation in
            self.currentStreamContinuation = continuation
            
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stopStreaming()
                    self?.currentStreamContinuation = nil
                    self?.sharedStream = nil
                }
            }
            
            // Start the streaming task
            self.streamTask = Task { @MainActor in
                await self.performEnhancedStreaming(for: text, continuation: continuation)
            }
        }
        
        sharedStream = stream
        return stream
    }
    
    /// Enhanced streaming with throttling and better error handling
    private func performEnhancedStreaming(for userInput: String, continuation: AsyncStream<StreamingEvent>.Continuation) async {
        error = nil

        // Add user message to observable array
        let userMessage = OAResponseMessage(
            role: .user,
            content: userInput,
            timestamp: Date(),
            responseId: ""
        )
        messages.append(userMessage)

        var accumulatedText = ""
        var currentMessage = OAResponseMessage(role: .assistant, content: "", responseId: "")

        do {
            let stream = try await createParametersAndStream(for: userInput)
            
            for try await event in stream {
                guard !Task.isCancelled else {
                    continuation.yield(.streamError(.streamCancelled))
                    break
                }
                
                switch event {
                case .responseCreated(let event):
                    let streamingMessage = OAResponseMessage(role: .assistant, content: "", responseId: event.response.id)
                    messages.append(streamingMessage)
                    currentMessage = streamingMessage
                    continuation.yield(.messageStarted(streamingMessage))

                case .outputTextDelta(let delta):
                    let deltaText = delta.delta
                    if !deltaText.isEmpty {
                        accumulatedText += deltaText
                        
                        // Apply throttling for back-pressure management
                        let now = Date()
                        if now.timeIntervalSince(lastUpdateTime) >= throttleInterval {
                            currentMessage = currentMessage.updatedWith(content: accumulatedText, isStreaming: true)
                            updateLocalMessage(currentMessage)
                            continuation.yield(.messageUpdated(currentMessage))
                            lastUpdateTime = now
                        }
                    }
                    
                case .outputTextDone(let textDone):
                    accumulatedText = textDone.text
                    currentMessage = currentMessage.updatedWith(content: accumulatedText, isStreaming: true)
                    updateLocalMessage(currentMessage)
                    continuation.yield(.messageUpdated(currentMessage))
                    
                case .contentPartDone(let partDone):
                    if let text = partDone.part.text {
                        accumulatedText = text
                        currentMessage = currentMessage.updatedWith(content: accumulatedText, isStreaming: true)
                        updateLocalMessage(currentMessage)
                        continuation.yield(.messageUpdated(currentMessage))
                    }
                    
                case .responseCompleted(let completed):
                    previousResponseId = completed.response.id
                    let finalText = completed.response.outputText ?? accumulatedText
                    let finalMessage = currentMessage.updatedWith(content: finalText, isStreaming: false)
                    updateLocalMessage(finalMessage)
                    continuation.yield(.messageCompleted(finalMessage))
                    continuation.finish()
                    return
                    
                case .responseFailed(let failed):
                    let error = StreamingError.serviceFailed(
                        underlying: APIError.requestFailed(description: failed.response.error?.message ?? "Stream failed")
                    )
                    continuation.yield(.streamError(error))
                    continuation.finish()
                    return
                    
                case .error(let errorEvent):
                    let error = StreamingError.networkError(description: errorEvent.message)
                    continuation.yield(.streamError(error))
                    continuation.finish()
                    return
                    
                default:
                    break
                }
            }
            
        } catch {
            let streamingError: StreamingError
            if error is CancellationError {
                streamingError = .streamCancelled
            } else {
                streamingError = .serviceFailed(underlying: error)
            }
            
            self.error = "Streaming failed: \(error.localizedDescription)"
            continuation.yield(.streamError(streamingError))
            continuation.finish()
        }
    }
    
    /// Helper to update local message array
    private func updateLocalMessage(_ message: OAResponseMessage) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[index] = message
    }
    
    /// Helper to create parameters and service stream
    private func createParametersAndStream(for userInput: String) async throws -> AsyncThrowingStream<OAResponseStreamEvent, Error> {
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
        
        return try await service.responseCreateStream(parameters)
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
}

