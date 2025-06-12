//
//  OAOpenAIApi.swift
//  openAIClient
//
//  Created by Lucas on 12.06.25.
//

import Foundation

enum OAOpenAIAPI {

  /// OpenAI's most advanced interface for generating model responses. Supports text and image inputs, and text outputs. Create stateful interactions with the model, using the output of previous responses as input. Extend the model's capabilities with built-in tools for file search, web search, computer use, and more. Allow the model access to external systems and data using function calling.
  case response(ResponseCategory) // https://platform.openai.com/docs/api-reference/responses

  enum ResponseCategory {
    case create
    case get(responseID: String)
  }
}

// MARK: Endpoint

extension OAOpenAIAPI: OAEndpoint {

  /// Builds the final path that includes:
  ///
  ///   - optional proxy path (e.g. "/my-proxy")
  ///   - version if non-nil (e.g. "/v1")
  ///   - then the specific endpoint path (e.g. "/assistants")
  func path(in openAIEnvironment: OAOpenAIEnvironment) -> String {
    // 1) Potentially prepend proxy path if `proxyPath` is non-empty
    let proxyPart =
      if let envProxyPart = openAIEnvironment.proxyPath, !envProxyPart.isEmpty {
        "/\(envProxyPart)"
      } else {
        ""
      }
    let mainPart = openAIPath(in: openAIEnvironment)

    return proxyPart + mainPart // e.g. "/my-proxy/v1/assistants"
  }

  func openAIPath(in openAIEnvironment: OAOpenAIEnvironment) -> String {
    let version =
      if let envOverrideVersion = openAIEnvironment.version, !envOverrideVersion.isEmpty {
        "/\(envOverrideVersion)"
      } else {
        ""
      }

    switch self {
    case .response(let category):
      switch category {
      case .create: return "\(version)/responses"
      case .get(let responseID): return "\(version)/responses/\(responseID)"
      }
    }
  }
}
