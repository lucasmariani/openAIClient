//
//  CustomChatInputTextView.swift
//  openAIClient
//
//  Created by Lucas on 29.06.25.
//

import UIKit

@MainActor
protocol CustomChatInputTextViewDelegate: AnyObject {
    func customChatInputTextViewDidRequestSend(_ textView: CustomChatInputTextView)
}

class CustomChatInputTextView: UITextView {
    
    weak var chatInputDelegate: CustomChatInputTextViewDelegate?
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override var keyCommands: [UIKeyCommand]? {
        return [
            // Enter key sends message
            UIKeyCommand(
                title: "Send Message",
                action: #selector(sendMessage),
                input: "\r",
                modifierFlags: [],
                alternates: [],
                discoverabilityTitle: "Send Message",
                attributes: [],
                state: .off
            ),
            // Shift+Enter adds new line
            UIKeyCommand(
                title: "New Line",
                action: #selector(insertNewLine),
                input: "\r",
                modifierFlags: .shift,
                alternates: [],
                discoverabilityTitle: "New Line",
                attributes: [],
                state: .off
            )
        ]
    }
    
    @objc private func sendMessage() {
        chatInputDelegate?.customChatInputTextViewDidRequestSend(self)
    }
    
    @objc private func insertNewLine() {
        // Insert newline at current cursor position
        guard let selectedRange = selectedTextRange else { return }
        
        replace(selectedRange, withText: "\n")
    }
}