//
//  OADefaultOpenAIService.swift
//  openAIClient
//
//  Created by Lucas on 12.06.25.
//

import Foundation

struct OADefaultOpenAIService: OAOpenAIService, Sendable {

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
    openAIEnvironment = OAOpenAIEnvironment(
      baseURL: baseURL ?? "https://api.openai.com",
      proxyPath: proxyPath,
      version: overrideVersion ?? "v1")
    self.debugEnabled = debugEnabled
  }

  let session: URLSession
  let decoder: JSONDecoder
  let openAIEnvironment: OAOpenAIEnvironment

  // MARK: Response

  func responseCreate(
    _ parameters: OAModelResponseParameter)
    async throws -> OAResponseModel
  {
    var responseParameters = parameters
    responseParameters.stream = false
    let request = try OAOpenAIAPI.response(.create).request(
      apiKey: apiKey,
      openAIEnvironment: openAIEnvironment,
      organizationID: organizationID,
      method: .post,
      params: responseParameters,
      extraHeaders: extraHeaders)
    return try await fetch(debugEnabled: debugEnabled, type: OAResponseModel.self, with: request)
  }

  func responseModel(
    id: String)
    async throws -> OAResponseModel
  {
    let request = try OAOpenAIAPI.response(.get(responseID: id)).request(
      apiKey: apiKey,
      openAIEnvironment: openAIEnvironment,
      organizationID: organizationID,
      method: .post,
      extraHeaders: extraHeaders)
    return try await fetch(debugEnabled: debugEnabled, type: OAResponseModel.self, with: request)
  }

  func responseCreateStream(
    _ parameters: OAModelResponseParameter)
    async throws -> AsyncThrowingStream<OAResponseStreamEvent, Error>
  {
    var responseParameters = parameters
    responseParameters.stream = true
    let request = try OAOpenAIAPI.response(.create).request(
      apiKey: apiKey,
      openAIEnvironment: openAIEnvironment,
      organizationID: organizationID,
      method: .post,
      params: responseParameters,
      extraHeaders: extraHeaders)
      
      return try await fetchStream(debugEnabled: debugEnabled, type: OAResponseStreamEvent.self, with: request)
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
