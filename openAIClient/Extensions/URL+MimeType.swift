//
//  URL+MimeType.swift
//  openAIClient
//
//  Created by Lucas on 15.06.25.
//

import Foundation
import UniformTypeIdentifiers

extension URL {
    var mimeType: String {
        if let uti = UTType(filenameExtension: self.pathExtension) {
            return uti.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }
}
