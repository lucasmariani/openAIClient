//
//  OACoreDataActor.swift
//  openAIClient
//
//  Created by Lucas on 15.06.25.
//

import Foundation
import CoreData

/// Global actor for isolating Core Data operations
/// This ensures all Core Data operations happen on the correct thread/queue
/// and provides proper isolation boundaries for Swift 6 strict concurrency
@globalActor
actor CoreDataActor {
    static let shared = CoreDataActor()
    
    private init() {}
}

/// Protocol for safely transferring Core Data operations across actor boundaries
protocol CoreDataOperationTransferable: Sendable {
    associatedtype Result: Sendable
    func execute(in context: NSManagedObjectContext) async throws -> Result
}

/// Helper for executing Core Data operations with proper isolation
extension CoreDataActor {
    
    /// Execute a Core Data operation with proper error handling and isolation
    static func performOperation<T: CoreDataOperationTransferable>(
        _ operation: T
    ) async throws -> T.Result {
        return try await operation.execute(in: OACoreDataStack.shared.container.newBackgroundContext())
    }
    
    /// Execute a simple Core Data operation with a closure
    static func performOperation<T: Sendable>(
        _ operation: @escaping @Sendable (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        let context = OACoreDataStack.shared.container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    let result = try operation(context)
                    if context.hasChanges {
                        try context.save()
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
