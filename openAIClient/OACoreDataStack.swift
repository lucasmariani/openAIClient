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
        
        // Configure for CloudKit
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve a persistent store description.")
        }
        
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        // Debug CloudKit container
        print("CloudKit container identifier: \(container.persistentStoreDescriptions.first?.cloudKitContainerOptions?.containerIdentifier ?? "nil")")
        
        // Check iCloud account status
        CKContainer.default().accountStatus { status, error in
            print("iCloud account status: \(status.rawValue)")
            if let error = error {
                print("iCloud account error: \(error)")
            }
        }
        
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                print("Core Data error: \(error), \(error.userInfo)")
                fatalError("Unresolved error: \(error), \(error.userInfo)")
            }
            print("Loaded store: \(storeDescription)")
        }
        
        // Set up remote change notifications
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { _ in
            print("🔄 Remote changes detected from CloudKit")
            NotificationCenter.default.post(name: .cloudKitDataChanged, object: nil)
        }
    }

    var mainContext: NSManagedObjectContext {
        let context = container.viewContext
        context.automaticallyMergesChangesFromParent = true
        return context
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
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
}
