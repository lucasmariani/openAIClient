//
//  OACoreDataStack.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import CoreData

//final class CoreDataStack {
//    @MainActor static let shared = CoreDataStack(modelName: "DataModel")
//    let container: NSPersistentContainer
//
//    private init(modelName: String) {
//        container = NSPersistentContainer(name: modelName)
//        container.loadPersistentStores { _, error in
//            if let error = error { fatalError("Core Data store failed: \(error)") }
//        }
//        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
//    }
//
//    /// UI code (main thread) should use this
//    var viewContext: NSManagedObjectContext { container.viewContext }
//
//    /// For background/actor work
//    func newBackgroundContext() -> NSManagedObjectContext {
//        container.newBackgroundContext()
//    }
//}

final class OACoreDataStack: Sendable {
    static let shared = OACoreDataStack()

    let container: NSPersistentContainer

    private init() {
        container = NSPersistentContainer(name: "DataModel")
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error: \(error), \(error.userInfo)")
            }
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
