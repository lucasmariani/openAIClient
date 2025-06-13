//
//  OAOpenAiService.swift
//  openAIClient
//
//  Created by Lucas on 12.06.25.
//

import Foundation

// MARK: - APIError

public enum APIError: Error {

    case requestFailed(description: String)
    case responseUnsuccessful(description: String, statusCode: Int)
    case invalidData
    case jsonDecodingFailure(description: String)
    case dataCouldNotBeReadMissingData(description: String)
    case bothDecodingStrategiesFailed
    case timeOutError

    public var displayDescription: String {
        switch self {
        case .requestFailed(let description): description
        case .responseUnsuccessful(let description, _): description
        case .invalidData: "Invalid data"
        case .jsonDecodingFailure(let description): description
        case .dataCouldNotBeReadMissingData(let description): description
        case .bothDecodingStrategiesFailed: "Decoding strategies failed."
        case .timeOutError: "Time Out Error."
        }
    }
}

// MARK: - OpenAIEnvironment

public struct OAOpenAIEnvironment: Sendable {

    /// The base URL for the OpenAI API.
    /// Example: "https://api.openai.com"
    let baseURL: String

    /// An optional path for proxying requests.
    /// Example: "/proxy-path"
    let proxyPath: String?

    /// An optional version of the OpenAI API to use.
    /// Example: "v1"
    let version: String?
}

// MARK: - Authorization

public enum Authorization: Sendable {
    case apiKey(String)
    case bearer(String)

    var headerField: String {
        switch self {
        case .apiKey:
            "api-key"
        case .bearer:
            "Authorization"
        }
    }

    var value: String {
        switch self {
        case .apiKey(let value):
            value
        case .bearer(let value):
            "Bearer \(value)"
        }
    }
}

// MARK: - OpenAIService

/// A protocol defining the required services for interacting with OpenAI's API.
///
/// The protocol outlines methods for fetching data and streaming responses,
/// as well as handling JSON decoding and networking tasks.

public protocol OAOpenAIService {

    /// The `URLSession` responsible for executing all network requests.
    ///
    /// This session is configured according to the needs of OpenAI's API,
    /// and it's used for tasks like sending and receiving data.
    var session: URLSession { get }
    /// The `JSONDecoder` instance used for decoding JSON responses.
    ///
    /// This decoder is used to parse the JSON responses returned by the API
    /// into model objects that conform to the `Decodable` protocol.
    var decoder: JSONDecoder { get }

    /// A computed property representing the current OpenAI environment configuration.
    var openAIEnvironment: OAOpenAIEnvironment { get }

    /// Returns a streaming [Response](https://platform.openai.com/docs/api-reference/responses/object) object.
    ///
    /// - Parameter parameters: The response model parameters with stream set to true
    /// - Returns: An AsyncThrowingStream of ResponseStreamEvent objects
    @MainActor func responseCreateStream(
        _ parameters: OAModelResponseParameter)
    async throws -> AsyncThrowingStream<OAResponseStreamEvent, Error>
}

extension OAOpenAIService {
    /// Asynchronously fetches a decodable data type from OpenAI's API.
    ///
    /// - Parameters:
    ///   - debugEnabled: If true the service will print events on DEBUG builds.
    ///   - type: The `Decodable` type that the response should be decoded to.
    ///   - request: The `URLRequest` describing the API request.
    /// - Throws: An error if the request fails or if decoding fails.
    /// - Returns: A value of the specified decodable type.
    public func fetch<T: Decodable>(
        debugEnabled: Bool,
        type: T.Type,
        with request: URLRequest)
    async throws -> T
    {
        if debugEnabled {
            printCurlCommand(request)
        }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed(description: "invalid response unable to get a valid HTTPURLResponse")
        }
        if debugEnabled {
            printHTTPURLResponse(httpResponse)
        }
        guard httpResponse.statusCode == 200 else {
            var errorMessage = "status code \(httpResponse.statusCode)"
            do {
                let error = try decoder.decode(OAOpenAIErrorResponse.self, from: data)
                errorMessage += " \(error.error.message ?? "NO ERROR MESSAGE PROVIDED")"
            } catch {
                // If decoding fails, proceed with a general error message
                errorMessage = "status code \(httpResponse.statusCode)"
            }
            throw APIError.responseUnsuccessful(
                description: errorMessage,
                statusCode: httpResponse.statusCode)
        }
#if DEBUG
        if debugEnabled {
            try print("DEBUG JSON FETCH API = \(JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any])")
        }
#endif
        do {
            return try decoder.decode(type, from: data)
        } catch DecodingError.keyNotFound(let key, let context) {
            let debug = "Key '\(key.stringValue)' not found: \(context.debugDescription)"
            let codingPath = "codingPath: \(context.codingPath)"
            let debugMessage = debug + codingPath
#if DEBUG
            if debugEnabled {
                print(debugMessage)
            }
#endif
            throw APIError.dataCouldNotBeReadMissingData(description: debugMessage)
        } catch {
#if DEBUG
            if debugEnabled {
                print("\(error)")
            }
#endif
            throw APIError.jsonDecodingFailure(description: error.localizedDescription)
        }
    }

    /// Asynchronously fetches a stream of decodable data types from OpenAI's API for chat completions.
    ///
    /// This method is primarily used for streaming chat completions.
    ///
    /// - Parameters:
    ///   - debugEnabled: If true the service will print events on DEBUG builds.
    ///   - type: The `Decodable` type that each streamed response should be decoded to.
    ///   - request: The `URLRequest` describing the API request.
    /// - Throws: An error if the request fails or if decoding fails.
    /// - Returns: An asynchronous throwing stream of the specified decodable type.
    @MainActor public func fetchStream<T: Decodable & Sendable>(
        debugEnabled: Bool,
        type _: T.Type,
        with request: URLRequest)
    async throws -> AsyncThrowingStream<T, Error>
    {
        if debugEnabled {
            printCurlCommand(request)
        }

        let (data, response) = try await session.bytes(
            for: request,
            delegate: session.delegate as? URLSessionTaskDelegate)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed(description: "invalid response unable to get a valid HTTPURLResponse")
        }
        if debugEnabled {
            printHTTPURLResponse(httpResponse)
        }
        guard httpResponse.statusCode == 200 else {
            var errorMessage = "status code \(httpResponse.statusCode)"
//            do {
//                let data = try await data.reduce(into: Data()) { data, byte in
//                    data.append(byte)
//                }
//                let error = try decoder.decode(OAOpenAIErrorResponse.self, from: data)
//                errorMessage += " \(error.error.message ?? "NO ERROR MESSAGE PROVIDED")"
//            } catch {
//                // If decoding fails, proceed with a general error message
//                errorMessage = "status code \(httpResponse.statusCode)"
//            }
            throw APIError.responseUnsuccessful(
                description: errorMessage,
                statusCode: httpResponse.statusCode)
        }

        // Capture the decoder locally to avoid self capture
        let localDecoder = self.decoder

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    for try await line in data.lines {
                        if
                            line.hasPrefix("data:"), line != "data: [DONE]",
                            let data = line.dropFirst(5).data(using: .utf8)
                        {
    #if DEBUG
                            if debugEnabled {
                                try print(
                                    "DEBUG JSON STREAM LINE = \(JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any])")
                            }
    #endif
                            do {
                                let decoded = try localDecoder.decode(T.self, from: data)
                                continuation.yield(decoded)
                            } catch DecodingError.keyNotFound(let key, let context) {
                                let debug = "Key '\(key.stringValue)' not found: \(context.debugDescription)"
                                let codingPath = "codingPath: \(context.codingPath)"
                                let debugMessage = debug + codingPath
    #if DEBUG
                                if debugEnabled {
                                    print(debugMessage)
                                }
    #endif
                                continuation.finish(throwing: APIError.dataCouldNotBeReadMissingData(description: debugMessage))
                                return
                            } catch {
    #if DEBUG
                                if debugEnabled {
                                    debugPrint("CONTINUATION ERROR DECODING \(error.localizedDescription)")
                                }
    #endif
                                continuation.finish(throwing: error)
                                return
                            }
                        }
                    }
                    continuation.finish()
                } catch DecodingError.keyNotFound(let key, let context) {
                    let debug = "Key '\(key.stringValue)' not found: \(context.debugDescription)"
                    let codingPath = "codingPath: \(context.codingPath)"
                    let debugMessage = debug + codingPath
    #if DEBUG
                    if debugEnabled {
                        print(debugMessage)
                    }
    #endif
                    continuation.finish(throwing: APIError.dataCouldNotBeReadMissingData(description: debugMessage))
                } catch {
    #if DEBUG
                    if debugEnabled {
                        print("CONTINUATION ERROR DECODING \(error.localizedDescription)")
                    }
    #endif
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func printCurlCommand(
        _ request: URLRequest)
    {
        guard let url = request.url, let httpMethod = request.httpMethod else {
            debugPrint("Invalid URL or HTTP method.")
            return
        }

        var baseCommand = "curl \(url.absoluteString)"

        // Add method if not GET
        if httpMethod != "GET" {
            baseCommand += " -X \(httpMethod)"
        }

        // Add headers if any, masking the Authorization token
        if let headers = request.allHTTPHeaderFields {
            for (header, value) in headers {
                let maskedValue = header.lowercased() == "authorization" ? maskAuthorizationToken(value) : value
                baseCommand += " \\\n-H \"\(header): \(maskedValue)\""
            }
        }

        // Add body if present
        if let httpBody = request.httpBody {
            let bodyString = prettyPrintJSON(httpBody)
            // The body string is already pretty printed and should be enclosed in single quotes
            baseCommand += " \\\n-d '\(bodyString)'"
        }

        // Print the final command
#if DEBUG
        print(baseCommand)
#endif
    }

    private func prettyPrintJSON(
        _ data: Data)
    -> String
    {
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
            let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
            let prettyPrintedString = String(data: prettyData, encoding: .utf8)
        else { return "Could not print JSON - invalid format" }
        return prettyPrintedString
    }

    private func printHTTPURLResponse(
        _ response: HTTPURLResponse,
        data: Data? = nil)
    {
#if DEBUG
        print("\n- - - - - - - - - - INCOMING RESPONSE - - - - - - - - - -\n")
        print("URL: \(response.url?.absoluteString ?? "No URL")")
        print("Status Code: \(response.statusCode)")
        print("Headers: \(response.allHeaderFields)")
        if let mimeType = response.mimeType {
            print("MIME Type: \(mimeType)")
        }
        if let data, response.mimeType == "application/json" {
            print("Body: \(prettyPrintJSON(data))")
        } else if let data, let bodyString = String(data: data, encoding: .utf8) {
            print("Body: \(bodyString)")
        }
        print("\n- - - - - - - - - - - - - - - - - - - - - - - - - - - -\n")
#endif
    }

    private func maskAuthorizationToken(_ token: String) -> String {
        if token.count > 6 {
            let prefix = String(token.prefix(3))
            let suffix = String(token.suffix(3))
            return "\(prefix)................\(suffix)"
        } else {
            return "INVALID TOKEN LENGTH"
        }
    }

}

extension OAResponseStreamEvent: @unchecked Sendable {}
