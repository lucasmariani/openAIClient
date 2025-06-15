//
//  OAEndpoint.swift
//  openAIClient
//
//  Created by Lucas on 12.06.25.
//

import Foundation

// MARK: - HTTPMethod

enum HTTPMethod: String {
    case post = "POST"
    case get = "GET"
    case delete = "DELETE"
}

// MARK: - Endpoint

protocol OAEndpoint {
    func path(
        in openAIEnvironment: OAOpenAIEnvironment)
    -> String
}

// MARK: Endpoint+Requests

extension OAEndpoint {
    
    func request(
        apiKey: Authorization,
        openAIEnvironment: OAOpenAIEnvironment,
        organizationID: String?,
        method: HTTPMethod,
        params: Encodable? = nil,
        queryItems: [URLQueryItem] = [],
        betaHeaderField: String? = nil,
        extraHeaders: [String: String]? = nil)
    throws -> URLRequest
    {
        let finalPath = path(in: openAIEnvironment)
        var request = URLRequest(url: urlComponents(base: openAIEnvironment.baseURL, path: finalPath, queryItems: queryItems).url!)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey.value, forHTTPHeaderField: apiKey.headerField)
        if let organizationID {
            request.addValue(organizationID, forHTTPHeaderField: "OpenAI-Organization")
        }
        if let betaHeaderField {
            request.addValue(betaHeaderField, forHTTPHeaderField: "OpenAI-Beta")
        }
        if let extraHeaders {
            for header in extraHeaders {
                request.addValue(header.value, forHTTPHeaderField: header.key)
            }
        }
        request.httpMethod = method.rawValue
        if let params {
            request.httpBody = try JSONEncoder().encode(params)
        }
        return request
    }
    
    func multiPartRequest(
        apiKey: Authorization,
        openAIEnvironment: OAOpenAIEnvironment,
        organizationID: String?,
        method: HTTPMethod,
        params: OAMultipartFormDataParameters,
        queryItems: [URLQueryItem] = [])
    throws -> URLRequest
    {
        let finalPath = path(in: openAIEnvironment)
        var request = URLRequest(url: urlComponents(base: openAIEnvironment.baseURL, path: finalPath, queryItems: queryItems).url!)
        request.httpMethod = method.rawValue
        let boundary = UUID().uuidString
        request.addValue(apiKey.value, forHTTPHeaderField: apiKey.headerField)
        if let organizationID {
            request.addValue(organizationID, forHTTPHeaderField: "OpenAI-Organization")
        }
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = params.encode(boundary: boundary)
        return request
    }
    
    private func urlComponents(
        base: String,
        path: String,
        queryItems: [URLQueryItem])
    -> URLComponents
    {
        var components = URLComponents(string: base)!
        components.path = path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components
    }
    
}

public protocol OAMultipartFormDataParameters {
    
    func encode(boundary: String) -> Data
}

