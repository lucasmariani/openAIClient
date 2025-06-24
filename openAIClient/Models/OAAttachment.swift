//
//  OAAttachment.swift
//  openAIClient
//
//  Created by Lucas on 15.06.25.
//

import Foundation
import UIKit
import OpenAIForSwift

public struct OAAttachment: Codable, Sendable, Hashable {
    public let id: String
    public let filename: String
    public let mimeType: String
    public let data: Data
    public let thumbnailData: Data?
    
    public init(id: String, filename: String, mimeType: String, data: Data, thumbnailData: Data? = nil) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.thumbnailData = thumbnailData
    }
    
    public init?(attachment: Attachment) {
        guard let id = attachment.id,
              let filename = attachment.filename,
              let mimeType = attachment.mimeType,
              let data = attachment.data else {
            return nil
        }
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.thumbnailData = attachment.thumbnailData
    }

    func fileAttachment(from attachment: OAAttachment) -> FileAttachment {
        FileAttachment(id: attachment.id,
                       filename: attachment.filename,
                       mimeType: attachment.mimeType,
                       data: attachment.data,
                       thumbnailData: attachment.thumbnailData)
    }

    public var isImage: Bool {
        mimeType.hasPrefix("image/")
    }
    
    public var isDocument: Bool {
        !isImage
    }
    
    public var sizeString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(data.count))
    }
    
    public var base64EncodedData: String {
        data.base64EncodedString()
    }
    
    public func generateThumbnail() -> Data? {
        guard isImage, let image = UIImage(data: data) else { return nil }
        
        let thumbnailSize = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
        }
        
        return thumbnail.jpegData(compressionQuality: 0.7)
    }
}
