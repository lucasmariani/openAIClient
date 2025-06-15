//
// OACoreDataError.swift
// openAIClient
//
// Created by Lucas on 28.05.25.
// Enhanced with Swift 6.1+ structured error handling

import Foundation

// MARK: - Modern Structured Error Types

/// A comprehensive error type providing detailed context for debugging and user feedback
public struct StructuredError: Error, Sendable {

    // MARK: - Core Properties

    /// The domain/category of the error
    public let domain: ErrorDomain

    /// The specific error code within the domain
    public let code: String

    /// Human-readable error message
    public let message: String

    /// Additional context and metadata
    public let context: ErrorContext

    /// Underlying error that caused this error
    public let underlyingError: Error?

    /// Timestamp when the error occurred
    public let timestamp: Date

    /// Suggested recovery actions
    public let recoverySuggestion: String?

    // MARK: - Error Domains

    public enum ErrorDomain: String, Sendable, CaseIterable {
        case coreData = "CoreDataDomain"
        case networking = "NetworkingDomain"
        case streaming = "StreamingDomain"
        case authentication = "AuthenticationDomain"
        case userInterface = "UserInterfaceDomain"
        case fileSystem = "FileSystemDomain"
    }

    // MARK: - Error Context

    public struct ErrorContext: Sendable {
        /// The operation that was being performed
        public let operation: String

        /// Entity or resource identifier
        public let entityId: String?

        /// Entity type (e.g., "Chat", "Message", "Stream")
        public let entityType: String?

        /// Additional metadata
        public let metadata: [String: String]

        /// Debug information
        public let debugInfo: DebugInfo?

        public init(
            operation: String,
            entityId: String? = nil,
            entityType: String? = nil,
            metadata: [String: String] = [:],
            debugInfo: DebugInfo? = nil
        ) {
            self.operation = operation
            self.entityId = entityId
            self.entityType = entityType
            self.metadata = metadata
            self.debugInfo = debugInfo
        }
    }

    // MARK: - Debug Information

    public struct DebugInfo: Sendable {
        public let file: String
        public let function: String
        public let line: Int
        public let threadInfo: String

        public init(
            file: String = #file,
            function: String = #function,
            line: Int = #line
        ) {
            self.file = String(file.split(separator: "/").last ?? "Unknown")
            self.function = function
            self.line = line
            self.threadInfo = Thread.isMainThread ? "MainThread" : "BackgroundThread"
        }
    }

    // MARK: - Initializers

    public init(
        domain: ErrorDomain,
        code: String,
        message: String,
        context: ErrorContext,
        underlyingError: Error? = nil,
        recoverySuggestion: String? = nil
    ) {
        self.domain = domain
        self.code = code
        self.message = message
        self.context = context
        self.underlyingError = underlyingError
        self.timestamp = Date.now
        self.recoverySuggestion = recoverySuggestion
    }
}

// MARK: - Error Factory Methods

extension StructuredError {

    // MARK: - Core Data Errors

    public static func chatNotFound(
        chatId: String,
        operation: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) -> StructuredError {
        StructuredError(
            domain: .coreData,
            code: "CHAT_NOT_FOUND",
            message: "Chat with ID '\(chatId)' could not be found",
            context: ErrorContext(
                operation: operation,
                entityId: chatId,
                entityType: "Chat",
                metadata: ["searchId": chatId],
                debugInfo: DebugInfo(file: file, function: function, line: line)
            ),
            recoverySuggestion: "Verify the chat ID is correct or create a new chat"
        )
    }

    public static func messageNotFound(
        messageId: String,
        chatId: String? = nil,
        operation: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) -> StructuredError {
        var metadata = ["searchId": messageId]
        if let chatId = chatId {
            metadata["chatId"] = chatId
        }

        return StructuredError(
            domain: .coreData,
            code: "MESSAGE_NOT_FOUND",
            message: "Message with ID '\(messageId)' could not be found",
            context: ErrorContext(
                operation: operation,
                entityId: messageId,
                entityType: "Message",
                metadata: metadata,
                debugInfo: DebugInfo(file: file, function: function, line: line)
            ),
            recoverySuggestion: "Refresh the chat or verify the message still exists"
        )
    }

    public static func coreDataSaveFailed(
        operation: String,
        underlyingError: Error,
        entityType: String? = nil,
        entityId: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) -> StructuredError {
        StructuredError(
            domain: .coreData,
            code: "SAVE_FAILED",
            message: "Failed to save changes to Core Data",
            context: ErrorContext(
                operation: operation,
                entityId: entityId,
                entityType: entityType,
                metadata: ["coreDataError": underlyingError.localizedDescription],
                debugInfo: DebugInfo(file: file, function: function, line: line)
            ),
            underlyingError: underlyingError,
            recoverySuggestion: "Try the operation again or restart the app"
        )
    }

    // MARK: - Networking Errors

    public static func networkRequestFailed(
        endpoint: String,
        statusCode: Int? = nil,
        underlyingError: Error? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) -> StructuredError {
        var metadata = ["endpoint": endpoint]
        if let statusCode = statusCode {
            metadata["statusCode"] = String(statusCode)
        }

        return StructuredError(
            domain: .networking,
            code: "REQUEST_FAILED",
            message: "Network request failed for endpoint: \(endpoint)",
            context: ErrorContext(
                operation: "networkRequest",
                entityId: endpoint,
                entityType: "HTTPRequest",
                metadata: metadata,
                debugInfo: DebugInfo(file: file, function: function, line: line)
            ),
            underlyingError: underlyingError,
            recoverySuggestion: "Check internet connection and try again"
        )
    }

    // MARK: - Streaming Errors

    public static func streamingFailed(
        chatId: String,
        phase: String,
        underlyingError: Error? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) -> StructuredError {
        StructuredError(
            domain: .streaming,
            code: "STREAMING_FAILED",
            message: "Message streaming failed during \(phase) phase",
            context: ErrorContext(
                operation: "messageStreaming",
                entityId: chatId,
                entityType: "ChatStream",
                metadata: ["phase": phase, "chatId": chatId],
                debugInfo: DebugInfo(file: file, function: function, line: line)
            ),
            underlyingError: underlyingError,
            recoverySuggestion: "Try sending the message again"
        )
    }
}
