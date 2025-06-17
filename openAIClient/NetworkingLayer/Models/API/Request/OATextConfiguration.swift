//
//  OATextConfiguration.swift
//  openAIClient
//
//  Created by Lucas on 12.06.25.
//

import Foundation

// MARK: - TextConfiguration

/// Text configuration options
public struct OATextConfiguration: Codable, Sendable {
    /// An object specifying the format that the model must output
    public var format: OAFormatType
    
    public init(format: OAFormatType) {
        self.format = format
    }
}

// MARK: - FormatType

/// Format types for text response
public enum OAFormatType: Codable, Sendable {
    case text
    case jsonSchema(OAJsonSchema)
    case jsonObject
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "text":
            self = .text
            
        case "json_schema":
            let schema = try container.decode(OAJsonSchema.self, forKey: .schema)
            self = .jsonSchema(schema)
            
        case "json_object":
            self = .jsonObject
            
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown format type: \(type)")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .text:
            try container.encode("text", forKey: .type)
            
        case .jsonSchema(let schema):
            try container.encode("json_schema", forKey: .type)
            try container.encode(schema, forKey: .schema)
            
        case .jsonObject:
            try container.encode("json_object", forKey: .type)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case schema
    }
    
}
