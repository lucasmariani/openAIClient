//
//  StreamingCoordinator.swift
//  openAIClient
//
//  Created by Claude on 17.06.25.
//

import Foundation

// MARK: - UI Stream Events

public enum UIStreamEvent: Sendable {
    case messageStarted(ResponseMessage)
    case messageUpdated(ResponseMessage)
    case messageCompleted(ResponseMessage)
    case streamError(StreamingError)
}

public enum StreamingError: Error, Sendable {
    case serviceFailed(underlying: Error)
    case streamCancelled
    case invalidContent
    case rateLimited
    case networkError(description: String)
}

// MARK: - UI Streaming Coordinator

@MainActor
@Observable
public final class StreamingCoordinator {
    
    // MARK: - Properties
    
    public let model: Model
    private let networkingProvider: NetworkingStreamProvider
    private var streamTask: Task<Void, Never>?
    
    // Observable properties for UI tracking
    public var messages: [ResponseMessage] = []
    public var error: String?
    public var isStreaming: Bool = false
    
    // UI-specific throttling for smooth updates
    private var lastUpdateTime: Date = Date()
    private let throttleInterval: TimeInterval = 0.05 // 50ms minimum between updates
    
    // MARK: - Initialization
    
    public init(networkingProvider: NetworkingStreamProvider, model: Model) {
        self.networkingProvider = networkingProvider
        self.model = model
    }
    
    // MARK: - Public API
    
    public func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }
    
    public func clearMessages() {
        stopStreaming()
        messages.removeAll()
        error = nil
    }
    
    /// UI-friendly streaming method with throttling and @MainActor execution
    public func streamMessage(
        text: String,
        attachments: [OAAttachment] = [],
        previousResponseId: String? = nil
    ) -> AsyncStream<UIStreamEvent> {
        
        return AsyncStream { continuation in
            streamTask = Task { @MainActor in
                await performUIStreaming(
                    text: text,
                    attachments: attachments,
                    previousResponseId: previousResponseId,
                    continuation: continuation
                )
            }
            
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stopStreaming()
                }
            }
        }
    }
    
    /// Generate title using networking layer
    public func generateTitle(userMessage: String, assistantMessage: String) async throws -> String {
        return try await networkingProvider.generateTitle(
            userMessage: userMessage,
            assistantMessage: assistantMessage
        )
    }
    
    // MARK: - Private Implementation
    
    private func performUIStreaming(
        text: String,
        attachments: [OAAttachment],
        previousResponseId: String?,
        continuation: AsyncStream<UIStreamEvent>.Continuation
    ) async {
        error = nil
        isStreaming = true
        
        // Add user message to UI
        let userMessage = ResponseMessage(
            role: .user,
            content: text,
            timestamp: Date(),
            responseId: ""
        )
        messages.append(userMessage)
        
        var currentMessage = ResponseMessage(role: .assistant, content: "", responseId: "")
        var accumulatedText = ""
        
        do {
            // Use pure networking stream
            let networkingStream = networkingProvider.streamResponse(
                for: text,
                model: model,
                attachments: attachments,
                previousResponseId: previousResponseId
            )
            
            for try await event in networkingStream {
                guard !Task.isCancelled else {
                    continuation.yield(.streamError(.streamCancelled))
                    break
                }
                
                switch event {
                case .responseStarted(let responseId):
                    let streamingMessage = ResponseMessage(
                        role: .assistant,
                        content: "",
                        responseId: responseId
                    )
                    messages.append(streamingMessage)
                    currentMessage = streamingMessage
                    continuation.yield(.messageStarted(streamingMessage))
                    
                case .contentDelta(let deltaText):
                    accumulatedText += deltaText
                    
                    // Apply UI throttling for smooth updates
                    let now = Date()
                    if now.timeIntervalSince(lastUpdateTime) >= throttleInterval {
                        currentMessage = currentMessage.updatedWith(content: accumulatedText, isStreaming: true)
                        updateLocalMessage(currentMessage)
                        continuation.yield(.messageUpdated(currentMessage))
                        lastUpdateTime = now
                    }
                    
                case .contentCompleted(let finalText):
                    accumulatedText = finalText
                    currentMessage = currentMessage.updatedWith(content: accumulatedText, isStreaming: true)
                    updateLocalMessage(currentMessage)
                    continuation.yield(.messageUpdated(currentMessage))
                    
                case .responseCompleted(let response):
                    let finalText = response.outputText ?? accumulatedText
                    let finalMessage = currentMessage.updatedWith(content: finalText, isStreaming: false)
                    updateLocalMessage(finalMessage)
                    continuation.yield(.messageCompleted(finalMessage))
                    continuation.finish()
                    isStreaming = false
                    return
                    
                case .streamError(let networkingError):
                    let uiError = mapNetworkingErrorToUIError(networkingError)
                    self.error = "Streaming failed: \(networkingError)"
                    continuation.yield(.streamError(uiError))
                    continuation.finish()
                    isStreaming = false
                    return
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
            isStreaming = false
        }
    }
    
    /// Helper to update local message array
    private func updateLocalMessage(_ message: ResponseMessage) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[index] = message
    }
    
    /// Map networking errors to UI errors
    private func mapNetworkingErrorToUIError(_ networkingError: NetworkingStreamError) -> StreamingError {
        switch networkingError {
        case .serviceFailed(let underlying):
            return .serviceFailed(underlying: underlying)
        case .streamCancelled:
            return .streamCancelled
        case .invalidContent:
            return .invalidContent
        case .rateLimited:
            return .rateLimited
        case .networkError(let description):
            return .networkError(description: description)
        case .encodingError(let description):
            return .networkError(description: description)
        }
    }
}
