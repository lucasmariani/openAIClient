//
//  AttributedStringCache.swift
//  openAIClient
//
//  Created by Lucas on 01.07.25.
//

import UIKit

/// Cache for attributed strings to avoid re-parsing markdown
@MainActor
final class AttributedStringCache {
    private struct CacheKey: Hashable {
        let text: String
        let role: OARole
    }
    
    private struct CacheEntry {
        let attributedString: NSAttributedString
        let timestamp: Date
    }
    
    private var cache: [CacheKey: CacheEntry] = [:]
    private let maxCacheSize: Int = 200
    private let cacheExpirationInterval: TimeInterval = 300 // 5 minutes
    
    // Differential parser for streaming optimization
    private let differentialParser = DifferentialMarkdownParser()
    
    static let shared = AttributedStringCache()
    
    private init() {
        // Start periodic cleanup
        Task {
            await startPeriodicCleanup()
        }
    }
    
    /// Get cached attributed string if available
    func getCachedAttributedString(for text: String, role: OARole) -> NSAttributedString? {
        let key = CacheKey(text: text, role: role)
        
        guard let entry = cache[key] else { return nil }
        
        // Check if cache is expired
        if Date().timeIntervalSince(entry.timestamp) > cacheExpirationInterval {
            cache.removeValue(forKey: key)
            return nil
        }
        
        return entry.attributedString
    }
    
    /// Cache an attributed string
    func cache(_ attributedString: NSAttributedString, for text: String, role: OARole) {
        let key = CacheKey(text: text, role: role)
        let entry = CacheEntry(attributedString: attributedString, timestamp: Date())
        
        cache[key] = entry
        
        // Enforce cache size limit
        if cache.count > maxCacheSize {
            removeOldestEntries()
        }
    }
    
    /// Create or get cached attributed string with markdown parsing
    func attributedString(from text: String, role: OARole) -> NSAttributedString {
        // Check cache first
        if let cached = getCachedAttributedString(for: text, role: role) {
            return cached
        }
        
        // Parse markdown
        let attributedString: NSAttributedString
        
        if let markdownString = try? NSAttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            let mutableString = NSMutableAttributedString(attributedString: markdownString)
            
            // Apply role-specific color
            let color: UIColor = {
                switch role {
                case .user: return .white
                case .assistant, .system: return .label
                }
            }()
            
            mutableString.addAttribute(
                .foregroundColor,
                value: color,
                range: NSRange(location: 0, length: mutableString.length)
            )
            
            // Set Dynamic Type font
            mutableString.addAttribute(
                .font,
                value: UIFont.preferredFont(forTextStyle: .body),
                range: NSRange(location: 0, length: mutableString.length)
            )
            
            attributedString = mutableString
        } else {
            // Fallback to plain text
            attributedString = NSAttributedString(
                string: text,
                attributes: [
                    .foregroundColor: role == .user ? UIColor.white : UIColor.label,
                    .font: UIFont.preferredFont(forTextStyle: .body)
                ]
            )
        }
        
        // Cache the result
        cache(attributedString, for: text, role: role)
        
        return attributedString
    }
    
    /// Create attributed string using differential parsing for streaming content
    func attributedStringForStreaming(from text: String, role: OARole, messageId: String) -> NSAttributedString {
        // Use differential parser for streaming content
        let tokens = differentialParser.parseDifferentially(content: text, for: messageId)
        let attributedString = differentialParser.attributedString(from: tokens, role: role)

        // Cache the result
        let key = CacheKey(text: text, role: role)
        let entry = CacheEntry(attributedString: attributedString, timestamp: Date())
        cache[key] = entry
        
        return attributedString
    }
    
    /// Clear differential parsing state when streaming completes
    func clearStreamingState(for messageId: String) {
        differentialParser.clearState(for: messageId)
    }
    
    /// Clear all cached strings
    func clearCache() {
        cache.removeAll()
    }
    
    private func removeOldestEntries() {
        let sortedEntries = cache.sorted { $0.value.timestamp < $1.value.timestamp }
        let entriesToRemove = sortedEntries.prefix(cache.count - maxCacheSize)
        
        for (key, _) in entriesToRemove {
            cache.removeValue(forKey: key)
        }
    }
    
    private func startPeriodicCleanup() async {
        while true {
            try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
            
            let now = Date()
            cache = cache.filter { _, entry in
                now.timeIntervalSince(entry.timestamp) <= cacheExpirationInterval
            }
        }
    }
}
