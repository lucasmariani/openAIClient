//
//  OACoreDataStack.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import CoreData
import CloudKit
import Foundation

extension Notification.Name {
    static let cloudKitDataChanged = Notification.Name("cloudKitDataChanged")
}

@MainActor
final class OACoreDataStack {
    static let shared = OACoreDataStack()
    
    let container: NSPersistentCloudKitContainer
    private var _isInitialized = false
    
    /// Indicates whether the Core Data stack has finished initializing
    var isInitialized: Bool {
        _isInitialized
    }
    
    private init() {
        container = NSPersistentCloudKitContainer(name: "DataModel")
        
        // Configure for CloudKit with Swift 6.2+ enhancements
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
        
        // Start async initialization immediately but don't block
        Task {
            await initializeStore()
        }
    }

//    private func setupNotifications() {
//        // Note: With your current architecture using OACoreDataManager + @Observable,
//        // you don't actually need automatic mainContext merging since your UI doesn't
//        // directly observe Core Data objects. The actor pattern with explicit 
//        // fetchPersistedChats() calls handles state updates properly.
//        
//        // This observer is kept minimal - mainly for potential future CloudKit sync
//        // or if you ever add direct Core Data UI bindings
//        
//        NotificationCenter.default.addObserver(
//            forName: .NSManagedObjectContextDidSave,
//            object: nil,
//            queue: .main
//        ) { [weak self] notification in
//            guard let self = self else { return }
//            
//            // Extract Sendable identifier before crossing the actor boundary
//            guard let context = notification.object as? NSManagedObjectContext else { return }
//            let contextObjectID = ObjectIdentifier(context) // ObjectIdentifier is Sendable
//            
//            // Use Task with MainActor to safely access mainContext
//            Task { @MainActor in
//                // Only handle saves from background contexts, not our main context
//                let mainContextID = ObjectIdentifier(self.mainContext)
//                guard contextObjectID != mainContextID else { return }
//                
//                // For now, just refresh - could be extended for CloudKit changes
//                self.mainContext.refreshAllObjects()
//            }
//        }
//    }

    /// Asynchronously initialize the Core Data stack
    private func initializeStore() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            container.loadPersistentStores { [weak self] storeDescription, error in
                if let error = error as NSError? {
                    print("Core Data error: \(error), \(error.userInfo)")
                    // Don't fatal error on initialization failure - allow app to continue
                    // The app can handle this gracefully
                }
                
                Task { @MainActor in
                    // Configure main context for optimal performance
                    let mainContext = self?.container.viewContext
                    mainContext?.automaticallyMergesChangesFromParent = true
                    mainContext?.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
                    mainContext?.undoManager = nil  // Disable for performance in non-editing contexts
                    
                    // Set up remote change notifications with modern async handling
                    if let container = self?.container {
                        NotificationCenter.default.addObserver(
                            forName: .NSPersistentStoreRemoteChange,
                            object: container.persistentStoreCoordinator,
                            queue: .main
                        ) { _ in
                            NotificationCenter.default.post(name: .cloudKitDataChanged, object: nil)
                        }
                    }
                    
                    // Mark as initialized
                    self?._isInitialized = true
                    
                    continuation.resume()
                }
            }
        }
    }
    
    /// Wait for Core Data initialization to complete
    func waitForInitialization() async {
        while !_isInitialized {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
    
    var mainContext: NSManagedObjectContext {
        let context = container.viewContext
        context.automaticallyMergesChangesFromParent = true
        return context
    }
    
    nonisolated func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        context.undoManager = nil  // Disable for performance
        return context
    }
    
    func saveContext() {
        // Only save if Core Data is initialized
        guard _isInitialized else { 
            print("⚠️ Core Data not initialized yet, skipping save")
            return 
        }
        
        let context = mainContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            let nserror = error as NSError
            print("❌ Core Data save error: \(nserror), \(nserror.userInfo)")
            // Don't fatal error on save failure during app lifecycle transitions
        }
    }
    
    /// Async version of saveContext for better integration with modern Swift concurrency
    func saveContextAsync() async {
        await waitForInitialization()
        
        let context = mainContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            let nserror = error as NSError
            print("❌ Core Data async save error: \(nserror), \(nserror.userInfo)")
        }
    }
    
    // MARK: - Modern Swift 6.2+ Convenience Methods
    
    /// Perform an operation on a background context with proper error handling
    func performBackgroundTask<T: Sendable>(
        _ operation: @escaping @Sendable (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        await waitForInitialization()

        return try await Task.detached(priority: .utility) {
            let context = self.newBackgroundContext()
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
        }.value
    }

    /// Perform a batch delete operation using NSBatchDeleteRequest
    func performBatchDelete<T: NSManagedObject>(
        entity: T.Type,
        predicateFormat: String,
        arguments: [any Sendable]
    ) async throws -> [NSManagedObjectID] {
        await waitForInitialization()
        
        return try await performBackgroundTask { context in
            let fetchRequest = T.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: predicateFormat, argumentArray: arguments)
            
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            deleteRequest.resultType = .resultTypeObjectIDs
            
            let result = try context.execute(deleteRequest) as! NSBatchDeleteResult
            let objectIDs = result.result as! [NSManagedObjectID]
            
            // Note: No automatic merging needed since OACoreDataManager 
            // calls fetchPersistedChats() after batch operations, which properly
            // updates the actor state and notifies the UI through @Observable

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
