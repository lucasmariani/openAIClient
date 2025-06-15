//
//  OAOpenAIFactoryService.swift
//  openAIClient
//
//  Created by Lucas on 12.06.25.
//

import Foundation

public class OAOpenAIServiceFactory {

  /// Creates and returns an instance of `OpenAIService`.
  ///
  /// - Parameters:
  ///   - apiKey: The API key required for authentication.
  ///   - organizationID: The optional organization ID for multi-tenancy (default is `nil`).
  ///   - configuration: The URL session configuration to be used for network calls (default is `.default`).
  ///   - decoder: The JSON decoder to be used for parsing API responses (default is `JSONDecoder.init()`).
  ///   - debugEnabled: If `true` service prints event on DEBUG builds, default to `false`.

  /// - Returns: A fully configured object conforming to `OpenAIService`.
  public static func service(
    apiKey: String,
    organizationID: String? = nil,
    configuration: URLSessionConfiguration = .default,
    decoder: JSONDecoder = .init(),
    debugEnabled: Bool = false)
    -> OAOpenAIService
  {
    OADefaultOpenAIService(
      apiKey: apiKey,
      organizationID: organizationID,
      configuration: configuration,
      decoder: decoder,
      debugEnabled: debugEnabled)
  }
}
