//
//  DefaultOpenAIService.swift
//  openAIClient
//
//  Created by Lucas on 12.06.25.
//

import Foundation

struct DefaultOpenAIService: OpenAIService, Sendable {
    
    init(
        apiKey: String,
        organizationID: String? = nil,
        baseURL: String? = nil,
        proxyPath: String? = nil,
        overrideVersion: String? = nil,
        extraHeaders: [String: String]? = nil,
        configuration: URLSessionConfiguration,
        decoder: JSONDecoder = .init(),
        debugEnabled: Bool)
    {
        session = URLSession(configuration: configuration)
        self.decoder = decoder
        self.apiKey = .bearer(apiKey)
        self.organizationID = organizationID
        self.extraHeaders = extraHeaders
        openAIEnvironment = OpenAIEnvironment(
            baseURL: baseURL ?? "https://api.openai.com",
            proxyPath: proxyPath,
            version: overrideVersion ?? "v1")
        self.debugEnabled = debugEnabled
    }
    
    let session: URLSession
    let decoder: JSONDecoder
    let openAIEnvironment: OpenAIEnvironment
    
    // MARK: Response
    
    func responseCreate(
        _ parameters: ModelResponseParameter)
    async throws -> ResponseModel
    {
        var responseParameters = parameters
        responseParameters.stream = false
        let request = try OpenAIAPI.response(.create).request(
            apiKey: apiKey,
            openAIEnvironment: openAIEnvironment,
            organizationID: organizationID,
            method: .post,
            params: responseParameters,
            extraHeaders: extraHeaders)
        return try await fetch(debugEnabled: debugEnabled, type: ResponseModel.self, with: request)
    }
    
    func responseModel(
        id: String)
    async throws -> ResponseModel
    {
        let request = try OpenAIAPI.response(.get(responseID: id)).request(
            apiKey: apiKey,
            openAIEnvironment: openAIEnvironment,
            organizationID: organizationID,
            method: .post,
            extraHeaders: extraHeaders)
        return try await fetch(debugEnabled: debugEnabled, type: ResponseModel.self, with: request)
    }
    
    func responseCreateStream(
        _ parameters: ModelResponseParameter)
    async throws -> AsyncThrowingStream<ResponseStreamEvent, Error>
    {
        var responseParameters = parameters
        responseParameters.stream = true
        let request = try OpenAIAPI.response(.create).request(
            apiKey: apiKey,
            openAIEnvironment: openAIEnvironment,
            organizationID: organizationID,
            method: .post,
            params: responseParameters,
            extraHeaders: extraHeaders)
        
        return try await fetchStream(debugEnabled: debugEnabled, type: ResponseStreamEvent.self, with: request)
    }
    
    private static let assistantsBetaV2 = "assistants=v2"
    
    /// [authentication](https://platform.openai.com/docs/api-reference/authentication)
    private let apiKey: Authorization
    /// [organization](https://platform.openai.com/docs/api-reference/organization-optional)
    private let organizationID: String?
    /// Set this flag to TRUE if you need to print request events in DEBUG builds.
    private let debugEnabled: Bool
    /// Extra headers for the request.
    private let extraHeaders: [String: String]?
}
