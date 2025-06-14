//
//  OACoreDataStack.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import CoreData
import CloudKit

extension Notification.Name {
    static let cloudKitDataChanged = Notification.Name("cloudKitDataChanged")
}

final class OACoreDataStack: Sendable {
    static let shared = OACoreDataStack()

    let container: NSPersistentCloudKitContainer

    private init() {
        container = NSPersistentCloudKitContainer(name: "DataModel")
        
        // Configure for CloudKit with Swift 6.1+ enhancements
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve a persistent store description.")
        }
        
        // CloudKit Configuration
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        #if DEBUG
        // Performance debugging (Development only)
        description.setOption(1 as NSNumber, forKey: "NSSQLiteDebugOption")
        description.setOption(1 as NSNumber, forKey: "NSCoreDataConcurrencyDebugKey")
        #endif
        
        // Performance optimizations
        let pragmas = [
            "journal_mode": "WAL",           // Write-Ahead Logging for better concurrency
            "synchronous": "NORMAL",         // Balanced durability and performance
            "cache_size": "10000",           // Larger cache for better performance
            "temp_store": "MEMORY"           // Temporary tables in memory
        ]
        description.setOption(pragmas as NSObject, forKey: NSSQLitePragmasOption)
        
        // Memory pressure handling
        description.shouldInferMappingModelAutomatically = true
        description.shouldMigrateStoreAutomatically = true
        
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                print("Core Data error: \(error), \(error.userInfo)")
                fatalError("Unresolved error: \(error), \(error.userInfo)")
            }
            print("✅ Core Data store loaded: \(storeDescription)")
        }
        
        // Configure main context for optimal performance
        let mainContext = container.viewContext
        mainContext.automaticallyMergesChangesFromParent = true
        mainContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        mainContext.undoManager = nil  // Disable for performance in non-editing contexts
        
        // Set up remote change notifications with modern async handling
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { _ in
            NotificationCenter.default.post(name: .cloudKitDataChanged, object: nil)
        }
    }

    var mainContext: NSManagedObjectContext {
        let context = container.viewContext
        context.automaticallyMergesChangesFromParent = true
        return context
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        context.undoManager = nil  // Disable for performance
        return context
    }

    func saveContext() {
        let context = mainContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            let nserror = error as NSError
            fatalError("Unresolved error: \(nserror), \(nserror.userInfo)")
        }
    }
    
    // MARK: - Modern Swift 6.1+ Convenience Methods
    
    /// Perform an operation on a background context with proper error handling
    func performBackgroundTask<T: Sendable>(
        _ operation: @escaping @Sendable (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        let context = newBackgroundContext()
        return try await context.perform {
            do {
                let result = try operation(context)
                if context.hasChanges {
                    try context.save()
                }
                return result
            } catch {
                context.rollback()
                throw error
            }
        }
    }
    
    /// Perform a batch operation with TaskGroup for concurrent processing
    func performBatchOperation<T: Sendable>(
        batchSize: Int = 100,
        items: [T],
        operation: @escaping @Sendable (NSManagedObjectContext, [T]) throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            let batches = items.chunked(into: batchSize)
            
            for batch in batches {
                group.addTask {
                    try await self.performBackgroundTask { context in
                        try operation(context, batch)
                    }
                }
            }
            
            try await group.waitForAll()
        }
    }
    
    /// Perform a batch delete operation using NSBatchDeleteRequest
    func performBatchDelete<T: NSManagedObject>(
        entity: T.Type,
        predicateFormat: String,
        arguments: [any Sendable]
    ) async throws -> [NSManagedObjectID] {
        return try await performBackgroundTask { context in
            let fetchRequest = T.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: predicateFormat, argumentArray: arguments)
            
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            deleteRequest.resultType = .resultTypeObjectIDs
            
            let result = try context.execute(deleteRequest) as! NSBatchDeleteResult
            let objectIDs = result.result as! [NSManagedObjectID]
            
            // Merge changes to update other contexts
            let changes = [NSDeletedObjectsKey: objectIDs]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context, self.mainContext])
            
            return objectIDs
        }
    }
}

// MARK: - Array Extension for Batching

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
