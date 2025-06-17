//
//  Model.swift
//  openAIClient
//
//  Created by Lucas on 12.06.25.
//

import Foundation

/// [Models](https://platform.openai.com/docs/models)
public enum Model: Sendable, Codable, Equatable, Hashable, CaseIterable {
    public static let allCases: [Model] = [.o1, .o1pro, .o3mini, .o4mini, .gpt4omini, .gpt4o, .gpt41nano, .gpt41mini, .gpt41]

    // Reasoning
    case o1
    case o1pro
    case o3mini
    case o4mini

    // gpt4o
    case gpt4omini
    case gpt4o

    // gpt4.1
    case gpt41nano
    case gpt41mini
    case gpt41

    // Unavailable
    case o1Preview
    case o1Mini
    case gpt4o20240806
    case gpt35Turbo
    case gpt35Turbo1106 // Most updated - Supports parallel function calls
    case gpt4 // 8,192 tokens
    case gpt41106Preview // Most updated - Supports parallel function calls 128,000 tokens
    case dalle2
    case dalle3
    case custom(String)

    public init(value: String) {
        switch value {
        case "o1": self = .o1
        case "o1-pro": self = .o1pro
        case "o3-mini": self = .o3mini
        case "o4-mini": self = .o4mini
        case "gpt-4o-mini": self = .gpt4omini
        case "gpt-4o": self = .gpt4o
        case "gpt-4.1-nano": self = .gpt41nano
        case "gpt-4.1-mini": self = .gpt41mini
        case "gpt-4.1": self = .gpt41
        default: self = .gpt41nano
        }
    }

    public var value: String {
        switch self {
        case .o1: "o1"
        case .o1pro: "o1-pro"
        case .o3mini: "o3-mini"
        case .o4mini: "o4-mini"

        case .gpt4omini: "gpt-4o-mini"
        case .gpt4o: "gpt-4o"

        case .gpt41nano: "gpt-4.1-nano"
        case .gpt41mini: "gpt-4.1-mini"
        case .gpt41: "gpt-4.1"

        default: "unavailable"
        }
    }

    public var displayName: String {
        switch self {
        case .o1: "o1"
        case .o1pro: "o1 pro"
        case .o3mini: "o3 mini"
        case .o4mini: "o4 mini"

        case .gpt4omini: "GPT-4o mini"
        case .gpt4o: "GPT-4o"

        case .gpt41nano: "GPT-4.1 nano"
        case .gpt41mini: "GPT-4.1 mini"
        case .gpt41: "GPT-4.1"
        default: "unavailable"
        }
    }
}
