//
//  OutputItem.swift
//  openAIClient
//
//  Created by Lucas on 12.06.25.
//

import Foundation

/// An output item from the model response
public enum OutputItem: Decodable, Sendable {
    /// An output message from the model
    case message(Message)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "message":
            let message = try Message(from: decoder)
            self = .message(message)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown output item type: \(type)")
        }
    }

    // MARK: - Output Message

    /// An output message from the model
    public struct Message: Decodable, Sendable {
        /// The content of the output message
        public let content: [ContentItem]
        /// The unique ID of the output message
        public let id: String
        /// The role of the output message. Always "assistant"
        public let role: String
        /// The status of the message input. One of "in_progress", "completed", or "incomplete"
        public let status: String?
        /// The type of the output message. Always "message"
        public let type: String

        enum CodingKeys: String, CodingKey {
            case content, id, role, status, type
        }
    }

    /// Content item in an output message
    public enum ContentItem: Decodable, Sendable {
        /// Text output from the model
        case outputText(OutputText)

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "output_text":
                let text = try OutputText(from: decoder)
                self = .outputText(text)

            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown content item type: \(type)")
            }
        }

        /// Text output from the model
        public struct OutputText: Decodable, Sendable {
            /// The text content
            public let text: String
            /// Annotations in the text, if any
            public let annotations: [Annotation]
            /// The type of the content. Always "output_text"
            public let type: String

            enum CodingKeys: String, CodingKey {
                case text, annotations, type
            }
        }

        /// Annotation in text output
        public struct Annotation: Decodable, Sendable {
            // Properties would be defined based on different annotation types
            // Such as file_citation, etc.
        }

        /// Other content types could be added here as they are defined

        private enum CodingKeys: String, CodingKey {
            case type
        }

    }

    private enum CodingKeys: String, CodingKey {
        case type
    }

}
