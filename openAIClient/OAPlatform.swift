//
//  OAPlatform.swift
//  openAIClient
//
//  Created by Lucas on 13.06.25.
//

import Foundation

struct OAPlatform {
    static var isMacCatalyst: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }
}
