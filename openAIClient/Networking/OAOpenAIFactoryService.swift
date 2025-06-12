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

//  // MARK: AIProxy
//
//  /// Creates and returns an instance of `OpenAIService` for use with aiproxy.pro
//  /// Use this service to protect your OpenAI API key before going to production.
//  ///
//  /// - Parameters:
//  ///   - aiproxyPartialKey: The partial key provided in the 'API Keys' section of the AIProxy dashboard.
//  ///                        Please see the integration guide for acquiring your key, at https://www.aiproxy.pro/docs
//  ///
//  ///   - aiproxyServiceURL: The service URL is displayed in the AIProxy dashboard when you submit your OpenAI key.
//  ///                        This argument is required for keys that you submitted after July 22nd, 2024. If you are an
//  ///                        existing customer that configured your AIProxy project before July 22nd, you may continue
//  ///                        to leave this blank.
//  ///
//  ///   - aiproxyClientID: If your app already has client or user IDs that you want to annotate AIProxy requests
//  ///                      with, you can pass a clientID here. If you do not have existing client or user IDs, leave
//  ///                      the `clientID` argument out, and IDs will be generated automatically for you.
//  ///   - debugEnabled: If `true` service prints event on DEBUG builds, default to `false`.
//  ///
//  /// - Returns: A conformer of OpenAIService that proxies all requests through api.aiproxy.pro
//  public static func service(
//    aiproxyPartialKey: String,
//    aiproxyServiceURL: String? = nil,
//    aiproxyClientID: String? = nil,
//    debugEnabled: Bool = false)
//    -> OAOpenAIService
//  {
//    AIProxyService(
//      partialKey: aiproxyPartialKey,
//      serviceURL: aiproxyServiceURL,
//      clientID: aiproxyClientID,
//      debugEnabled: debugEnabled)
//  }
//
//  // MARK: Custom URL
//
//  /// Creates and returns an instance of `OpenAIService`.
//  ///
//  /// Use this service if you need to provide a custom URL, for example to run local models with OpenAI endpoints compatibility using Ollama.
//  /// Check [Ollama blog post](https://ollama.com/blog/openai-compatibility) for more.
//  ///
//  /// - Parameters:
//  ///   - apiKey: The optional API key required for authentication.
//  ///   - baseURL: The local host URL. defaults to  "http://localhost:11434"
//  ///   - debugEnabled: If `true` service prints event on DEBUG builds, default to `false`.
//  ///
//  /// - Returns: A fully configured object conforming to `OpenAIService`.
//  public static func service(
//    apiKey: Authorization = .apiKey(""),
//    baseURL: String,
//    debugEnabled: Bool = false)
//    -> OAOpenAIService
//  {
//    LocalModelService(
//      apiKey: apiKey,
//      baseURL: baseURL,
//      debugEnabled: debugEnabled)
//  }
//
//  // MARK: Proxy Path
//
//  /// Creates and returns an instance of `OpenAIService`.
//  ///
//  /// Use this service if you need to provide a custom URL with a proxy path, for example to run Groq.
//  ///
//  /// - Parameters:
//  ///   - apiKey: The optional API key required for authentication.
//  ///   - baseURL: The local host URL.  e.g "https://api.groq.com" or "https://generativelanguage.googleapis.com"
//  ///   - proxyPath: The proxy path e.g `openai`
//  ///   - overrideVersion: The API version. defaults to `v1`
//  ///   - extraHeaders: Additional headers needed for the request. Do not provide API key in these headers.
//  ///   - debugEnabled: If `true` service prints event on DEBUG builds, default to `false`.
//  ///
//  /// - Returns: A fully configured object conforming to `OpenAIService`.
//  public static func service(
//    apiKey: String,
//    overrideBaseURL: String,
//    configuration: URLSessionConfiguration = .default,
//    proxyPath: String? = nil,
//    overrideVersion: String? = nil,
//    extraHeaders: [String: String]? = nil,
//    debugEnabled: Bool = false)
//    -> OAOpenAIService
//  {
//    DefaultOpenAIService(
//      apiKey: apiKey,
//      baseURL: overrideBaseURL,
//      proxyPath: proxyPath,
//      overrideVersion: overrideVersion,
//      extraHeaders: extraHeaders,
//      configuration: configuration,
//      debugEnabled: debugEnabled)
//  }
}
