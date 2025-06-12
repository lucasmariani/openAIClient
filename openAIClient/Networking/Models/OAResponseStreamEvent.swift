//
//  OAResponseStreamEvent.swift
//  openAIClient
//
//  Created by Lucas on 12.06.25.
//

import Foundation

// MARK: - ResponseStreamEvent

/// Represents all possible streaming events from the Responses API
public enum OAResponseStreamEvent: Decodable {
  /// Emitted when a response is created
  case responseCreated(ResponseCreatedEvent)

  /// Emitted when the response is in progress
  case responseInProgress(ResponseInProgressEvent)

  /// Emitted when the model response is complete
  case responseCompleted(ResponseCompletedEvent)

  /// Emitted when a response fails
  case responseFailed(ResponseFailedEvent)

  /// Emitted when a response finishes as incomplete
  case responseIncomplete(ResponseIncompleteEvent)

  /// Emitted when a response is queued
  case responseQueued(ResponseQueuedEvent)

  /// Emitted when a new output item is added
  case outputItemAdded(OutputItemAddedEvent)

  /// Emitted when an output item is marked done
  case outputItemDone(OutputItemDoneEvent)

  /// Emitted when a new content part is added
  case contentPartAdded(ContentPartAddedEvent)

  /// Emitted when a content part is done
  case contentPartDone(ContentPartDoneEvent)

  /// Emitted when there is an additional text delta
  case outputTextDelta(OutputTextDeltaEvent)

  /// Emitted when text content is finalized
  case outputTextDone(OutputTextDoneEvent)

  /// Emitted when there is a partial refusal text
  case refusalDelta(RefusalDeltaEvent)

  /// Emitted when refusal text is finalized
  case refusalDone(RefusalDoneEvent)

//  /// Emitted when there is a partial function-call arguments delta
//  case functionCallArgumentsDelta(FunctionCallArgumentsDeltaEvent)
//
//  /// Emitted when function-call arguments are finalized
//  case functionCallArgumentsDone(FunctionCallArgumentsDoneEvent)
//
//  /// Emitted when a file search call is initiated
//  case fileSearchCallInProgress(FileSearchCallInProgressEvent)
//
//  /// Emitted when a file search is currently searching
//  case fileSearchCallSearching(FileSearchCallSearchingEvent)
//
//  /// Emitted when a file search call is completed
//  case fileSearchCallCompleted(FileSearchCallCompletedEvent)
//
//  /// Emitted when a web search call is initiated
//  case webSearchCallInProgress(WebSearchCallInProgressEvent)
//
//  /// Emitted when a web search call is executing
//  case webSearchCallSearching(WebSearchCallSearchingEvent)
//
//  /// Emitted when a web search call is completed
//  case webSearchCallCompleted(WebSearchCallCompletedEvent)
//
//  /// Emitted when a new reasoning summary part is added
//  case reasoningSummaryPartAdded(ReasoningSummaryPartAddedEvent)
//
//  /// Emitted when a reasoning summary part is completed
//  case reasoningSummaryPartDone(ReasoningSummaryPartDoneEvent)
//
//  /// Emitted when a delta is added to a reasoning summary text
//  case reasoningSummaryTextDelta(ReasoningSummaryTextDeltaEvent)
//
//  /// Emitted when a reasoning summary text is completed
//  case reasoningSummaryTextDone(ReasoningSummaryTextDoneEvent)
//
//  /// Emitted when an image generation call is in progress
//  case imageGenerationCallInProgress(ImageGenerationCallInProgressEvent)
//
//  /// Emitted when an image generation call is generating
//  case imageGenerationCallGenerating(ImageGenerationCallGeneratingEvent)
//
//  /// Emitted when a partial image is available
//  case imageGenerationCallPartialImage(ImageGenerationCallPartialImageEvent)
//
//  /// Emitted when an image generation call is completed
//  case imageGenerationCallCompleted(ImageGenerationCallCompletedEvent)
//
//  /// Emitted when there is a delta to MCP call arguments
//  case mcpCallArgumentsDelta(MCPCallArgumentsDeltaEvent)
//
//  /// Emitted when MCP call arguments are done
//  case mcpCallArgumentsDone(MCPCallArgumentsDoneEvent)
//
//  /// Emitted when an MCP call is in progress
//  case mcpCallInProgress(MCPCallInProgressEvent)
//
//  /// Emitted when an MCP call is completed
//  case mcpCallCompleted(MCPCallCompletedEvent)
//
//  /// Emitted when an MCP call failed
//  case mcpCallFailed(MCPCallFailedEvent)
//
//  /// Emitted when MCP list tools is in progress
//  case mcpListToolsInProgress(MCPListToolsInProgressEvent)
//
//  /// Emitted when MCP list tools is completed
//  case mcpListToolsCompleted(MCPListToolsCompletedEvent)
//
//  /// Emitted when MCP list tools failed
//  case mcpListToolsFailed(MCPListToolsFailedEvent)
//
//  /// Emitted when an annotation is added to output text
//  case outputTextAnnotationAdded(OutputTextAnnotationAddedEvent)
//
//  /// Emitted when there is a delta to reasoning content
//  case reasoningDelta(ReasoningDeltaEvent)
//
//  /// Emitted when reasoning content is done
//  case reasoningDone(ReasoningDoneEvent)
//
//  /// Emitted when there is a delta to reasoning summary
//  case reasoningSummaryDelta(ReasoningSummaryDeltaEvent)
//
//  /// Emitted when reasoning summary is done
//  case reasoningSummaryDone(ReasoningSummaryDoneEvent)

  /// Emitted when an error occurs
  case error(OAErrorEvent)

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)

    switch type {
    case "response.created":
      self = try .responseCreated(ResponseCreatedEvent(from: decoder))
    case "response.in_progress":
      self = try .responseInProgress(ResponseInProgressEvent(from: decoder))
    case "response.completed":
      self = try .responseCompleted(ResponseCompletedEvent(from: decoder))
    case "response.failed":
      self = try .responseFailed(ResponseFailedEvent(from: decoder))
    case "response.incomplete":
      self = try .responseIncomplete(ResponseIncompleteEvent(from: decoder))
    case "response.queued":
      self = try .responseQueued(ResponseQueuedEvent(from: decoder))
    case "response.output_item.added":
      self = try .outputItemAdded(OutputItemAddedEvent(from: decoder))
    case "response.output_item.done":
      self = try .outputItemDone(OutputItemDoneEvent(from: decoder))
    case "response.content_part.added":
      self = try .contentPartAdded(ContentPartAddedEvent(from: decoder))
    case "response.content_part.done":
      self = try .contentPartDone(ContentPartDoneEvent(from: decoder))
    case "response.output_text.delta":
      self = try .outputTextDelta(OutputTextDeltaEvent(from: decoder))
    case "response.output_text.done":
      self = try .outputTextDone(OutputTextDoneEvent(from: decoder))
    case "response.refusal.delta":
      self = try .refusalDelta(RefusalDeltaEvent(from: decoder))
    case "response.refusal.done":
      self = try .refusalDone(RefusalDoneEvent(from: decoder))
//    case "response.function_call_arguments.delta":
//      self = try .functionCallArgumentsDelta(FunctionCallArgumentsDeltaEvent(from: decoder))
//    case "response.function_call_arguments.done":
//      self = try .functionCallArgumentsDone(FunctionCallArgumentsDoneEvent(from: decoder))
//    case "response.file_search_call.in_progress":
//      self = try .fileSearchCallInProgress(FileSearchCallInProgressEvent(from: decoder))
//    case "response.file_search_call.searching":
//      self = try .fileSearchCallSearching(FileSearchCallSearchingEvent(from: decoder))
//    case "response.file_search_call.completed":
//      self = try .fileSearchCallCompleted(FileSearchCallCompletedEvent(from: decoder))
//    case "response.web_search_call.in_progress":
//      self = try .webSearchCallInProgress(WebSearchCallInProgressEvent(from: decoder))
//    case "response.web_search_call.searching":
//      self = try .webSearchCallSearching(WebSearchCallSearchingEvent(from: decoder))
//    case "response.web_search_call.completed":
//      self = try .webSearchCallCompleted(WebSearchCallCompletedEvent(from: decoder))
//    case "response.reasoning_summary_part.added":
//      self = try .reasoningSummaryPartAdded(ReasoningSummaryPartAddedEvent(from: decoder))
//    case "response.reasoning_summary_part.done":
//      self = try .reasoningSummaryPartDone(ReasoningSummaryPartDoneEvent(from: decoder))
//    case "response.reasoning_summary_text.delta":
//      self = try .reasoningSummaryTextDelta(ReasoningSummaryTextDeltaEvent(from: decoder))
//    case "response.reasoning_summary_text.done":
//      self = try .reasoningSummaryTextDone(ReasoningSummaryTextDoneEvent(from: decoder))
//    case "response.image_generation_call.in_progress":
//      self = try .imageGenerationCallInProgress(ImageGenerationCallInProgressEvent(from: decoder))
//    case "response.image_generation_call.generating":
//      self = try .imageGenerationCallGenerating(ImageGenerationCallGeneratingEvent(from: decoder))
//    case "response.image_generation_call.partial_image":
//      self = try .imageGenerationCallPartialImage(ImageGenerationCallPartialImageEvent(from: decoder))
//    case "response.image_generation_call.completed":
//      self = try .imageGenerationCallCompleted(ImageGenerationCallCompletedEvent(from: decoder))
//    case "response.mcp_call.arguments.delta":
//      self = try .mcpCallArgumentsDelta(MCPCallArgumentsDeltaEvent(from: decoder))
//    case "response.mcp_call.arguments.done":
//      self = try .mcpCallArgumentsDone(MCPCallArgumentsDoneEvent(from: decoder))
//    case "response.mcp_call.in_progress":
//      self = try .mcpCallInProgress(MCPCallInProgressEvent(from: decoder))
//    case "response.mcp_call.completed":
//      self = try .mcpCallCompleted(MCPCallCompletedEvent(from: decoder))
//    case "response.mcp_call.failed":
//      self = try .mcpCallFailed(MCPCallFailedEvent(from: decoder))
//    case "response.mcp_list_tools.in_progress":
//      self = try .mcpListToolsInProgress(MCPListToolsInProgressEvent(from: decoder))
//    case "response.mcp_list_tools.completed":
//      self = try .mcpListToolsCompleted(MCPListToolsCompletedEvent(from: decoder))
//    case "response.mcp_list_tools.failed":
//      self = try .mcpListToolsFailed(MCPListToolsFailedEvent(from: decoder))
//    case "response.output_text_annotation.added":
//      self = try .outputTextAnnotationAdded(OutputTextAnnotationAddedEvent(from: decoder))
//    case "response.reasoning.delta":
//      self = try .reasoningDelta(ReasoningDeltaEvent(from: decoder))
//    case "response.reasoning.done":
//      self = try .reasoningDone(ReasoningDoneEvent(from: decoder))
//    case "response.reasoning_summary.delta":
//      self = try .reasoningSummaryDelta(ReasoningSummaryDeltaEvent(from: decoder))
//    case "response.reasoning_summary.done":
//      self = try .reasoningSummaryDone(ReasoningSummaryDoneEvent(from: decoder))
    case "error":
      self = try .error(OAErrorEvent(from: decoder))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .type,
        in: container,
        debugDescription: "Unknown event type: \(type)")
    }
  }

  private enum CodingKeys: String, CodingKey {
    case type
  }
}

// MARK: - ResponseCreatedEvent

/// Emitted when a response is created
public struct ResponseCreatedEvent: Decodable {
  public let type: String
  public let response: OAResponseModel
  public let sequenceNumber: Int?

  enum CodingKeys: String, CodingKey {
    case type
    case response
    case sequenceNumber = "sequence_number"
  }
}

// MARK: - ResponseInProgressEvent

/// Emitted when the response is in progress
public struct ResponseInProgressEvent: Decodable {
  public let type: String
  public let response: OAResponseModel
  public let sequenceNumber: Int?

  enum CodingKeys: String, CodingKey {
    case type
    case response
    case sequenceNumber = "sequence_number"
  }
}

// MARK: - ResponseCompletedEvent

/// Emitted when the model response is complete
public struct ResponseCompletedEvent: Decodable {
  public let type: String
  public let response: OAResponseModel
  public let sequenceNumber: Int?

  enum CodingKeys: String, CodingKey {
    case type
    case response
    case sequenceNumber = "sequence_number"
  }
}

// MARK: - ResponseFailedEvent

/// Emitted when a response fails
public struct ResponseFailedEvent: Decodable {
  public let type: String
  public let response: OAResponseModel
  public let sequenceNumber: Int?

  enum CodingKeys: String, CodingKey {
    case type
    case response
    case sequenceNumber = "sequence_number"
  }
}

// MARK: - ResponseIncompleteEvent

/// Emitted when a response finishes as incomplete
public struct ResponseIncompleteEvent: Decodable {
  public let type: String
  public let response: OAResponseModel
  public let sequenceNumber: Int?

  enum CodingKeys: String, CodingKey {
    case type
    case response
    case sequenceNumber = "sequence_number"
  }
}

// MARK: - ResponseQueuedEvent

/// Emitted when a response is queued
public struct ResponseQueuedEvent: Decodable {
  public let type: String
  public let response: OAResponseModel
  public let sequenceNumber: Int?

  enum CodingKeys: String, CodingKey {
    case type
    case response
    case sequenceNumber = "sequence_number"
  }
}

// MARK: - OutputItemAddedEvent

/// Emitted when a new output item is added
public struct OutputItemAddedEvent: Decodable {
  public let type: String
  public let outputIndex: Int
  public let item: OAStreamOutputItem
  public let sequenceNumber: Int?

  enum CodingKeys: String, CodingKey {
    case type
    case outputIndex = "output_index"
    case item
    case sequenceNumber = "sequence_number"
  }
}

// MARK: - OutputItemDoneEvent

/// Emitted when an output item is marked done
public struct OutputItemDoneEvent: Decodable {
  public let type: String
  public let outputIndex: Int
  public let item: OAStreamOutputItem
  public let sequenceNumber: Int?

  enum CodingKeys: String, CodingKey {
    case type
    case outputIndex = "output_index"
    case item
    case sequenceNumber = "sequence_number"
  }
}

// MARK: - ContentPartAddedEvent

/// Emitted when a new content part is added
public struct ContentPartAddedEvent: Decodable {
  public let type: String
  public let itemId: String
  public let outputIndex: Int
  public let contentIndex: Int
  public let part: OAContentPart
  public let sequenceNumber: Int?

  enum CodingKeys: String, CodingKey {
    case type
    case itemId = "item_id"
    case outputIndex = "output_index"
    case contentIndex = "content_index"
    case part
    case sequenceNumber = "sequence_number"
  }
}

// MARK: - ContentPartDoneEvent

/// Emitted when a content part is done
public struct ContentPartDoneEvent: Decodable {
  public let type: String
  public let itemId: String
  public let outputIndex: Int
  public let contentIndex: Int
  public let part: OAContentPart
  public let sequenceNumber: Int?

  enum CodingKeys: String, CodingKey {
    case type
    case itemId = "item_id"
    case outputIndex = "output_index"
    case contentIndex = "content_index"
    case part
    case sequenceNumber = "sequence_number"
  }
}

// MARK: - OutputTextDeltaEvent

/// Emitted when there is an additional text delta
public struct OutputTextDeltaEvent: Decodable {
  public let type: String
  public let itemId: String
  public let outputIndex: Int
  public let contentIndex: Int
  public let delta: String
  public let sequenceNumber: Int?

  enum CodingKeys: String, CodingKey {
    case type
    case itemId = "item_id"
    case outputIndex = "output_index"
    case contentIndex = "content_index"
    case delta
    case sequenceNumber = "sequence_number"
  }
}

// MARK: - OutputTextDoneEvent

/// Emitted when text content is finalized
public struct OutputTextDoneEvent: Decodable {
  public let type: String
  public let itemId: String
  public let outputIndex: Int
  public let contentIndex: Int
  public let text: String
  public let sequenceNumber: Int?

  enum CodingKeys: String, CodingKey {
    case type
    case itemId = "item_id"
    case outputIndex = "output_index"
    case contentIndex = "content_index"
    case text
    case sequenceNumber = "sequence_number"
  }
}

// MARK: - RefusalDeltaEvent

/// Emitted when there is a partial refusal text
public struct RefusalDeltaEvent: Decodable {
  public let type: String
  public let itemId: String
  public let outputIndex: Int
  public let contentIndex: Int
  public let delta: String
  public let sequenceNumber: Int?

  enum CodingKeys: String, CodingKey {
    case type
    case itemId = "item_id"
    case outputIndex = "output_index"
    case contentIndex = "content_index"
    case delta
    case sequenceNumber = "sequence_number"
  }
}

// MARK: - RefusalDoneEvent

/// Emitted when refusal text is finalized
public struct RefusalDoneEvent: Decodable {
  public let type: String
  public let itemId: String
  public let outputIndex: Int
  public let contentIndex: Int
  public let refusal: String
  public let sequenceNumber: Int?

  enum CodingKeys: String, CodingKey {
    case type
    case itemId = "item_id"
    case outputIndex = "output_index"
    case contentIndex = "content_index"
    case refusal
    case sequenceNumber = "sequence_number"
  }
}

// MARK: - ErrorEvent

/// Emitted when an error occurs
public struct OAErrorEvent: Decodable {
  public let type: String
  public let code: String?
  public let message: String
  public let param: String?
  public let sequenceNumber: Int?

  enum CodingKeys: String, CodingKey {
    case type
    case code
    case message
    case param
    case sequenceNumber = "sequence_number"
  }
}

// MARK: - StreamOutputItem

/// Stream output item (simplified version for streaming)
public struct OAStreamOutputItem: Decodable {
  public let id: String
  public let type: String
  public let status: String?
  public let role: String?
  public let content: [OAOutputItem.OAContentItem]?
}

public struct OAContentPart: Decodable {
  public let type: String
  public let text: String?
  public let annotations: [Any]?

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    type = try container.decode(String.self, forKey: .type)
    text = try container.decodeIfPresent(String.self, forKey: .text)
    annotations = nil // Skip decoding annotations for now
  }

  enum CodingKeys: String, CodingKey {
    case type
    case text
    case annotations
  }
}

