//
//  OAOpenAiErrorResponse.swift
//  openAIClient
//
//  Created by Lucas on 12.06.25.
//

import Foundation

public struct OAOpenAIErrorResponse: Decodable {
    
    public let error: Error
    
    public struct Error: Decodable {
        public let message: String?
        public let type: String?
        public let param: String?
        public let code: String?
    }
}
