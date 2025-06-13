//
//  OAUsage.swift
//  openAIClient
//
//  Created by Lucas on 12.06.25.
//

import Foundation

/// Represents token usage details including input tokens, output tokens, a breakdown of output tokens, and the total tokens used.
public struct OAUsage: Codable, Sendable {

  /// Details about input tokens
  public struct OAInputTokensDetails: Codable, Sendable {
    /// Number of cached tokens
    public let cachedTokens: Int?

    enum CodingKeys: String, CodingKey {
      case cachedTokens = "cached_tokens"
    }
  }

  /// A detailed breakdown of the output tokens.
  public struct OAOutputTokensDetails: Codable, Sendable {
    /// The number of reasoning tokens.
    public let reasoningTokens: Int?

    enum CodingKeys: String, CodingKey {
      case reasoningTokens = "reasoning_tokens"
    }
  }

  /// Number of completion tokens used over the course of the run step.
  public let completionTokens: Int?

  /// Number of prompt tokens used over the course of the run step.
  public let promptTokens: Int?

  /// The number of input tokens.
  public let inputTokens: Int?

  /// Details about input tokens
  public let inputTokensDetails: OAInputTokensDetails?

  /// The number of output tokens.
  public let outputTokens: Int?

  /// A detailed breakdown of the output tokens.
  public let outputTokensDetails: OAOutputTokensDetails?

  /// The total number of tokens used.
  public let totalTokens: Int?

  enum CodingKeys: String, CodingKey {
    case completionTokens = "completion_tokens"
    case promptTokens = "prompt_tokens"
    case inputTokens = "input_tokens"
    case inputTokensDetails = "input_tokens_details"
    case outputTokens = "output_tokens"
    case outputTokensDetails = "output_tokens_details"
    case totalTokens = "total_tokens"
  }
}
