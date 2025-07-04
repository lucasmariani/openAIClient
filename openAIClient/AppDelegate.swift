//
//  AppDelegate.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import UIKit
import CoreData

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate.
        // Save data if appropriate. See also applicationDidEnterBackground:

        print("⚠️ App will terminate - performing emergency Core Data save")

        // Request additional background time to complete Core Data save
        var backgroundTaskID = UIBackgroundTaskIdentifier.invalid
        backgroundTaskID = application.beginBackgroundTask {
            application.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }

        // Force synchronous save to ensure data persistence
        let context = OACoreDataStack.shared.mainContext
        if context.hasChanges {
            do {
                try context.save()
                print("✅ Emergency Core Data save successful")
            } catch {
                print("❌ Emergency Core Data save failed: \(error)")
            }
        }

        // End background task
        if backgroundTaskID != .invalid {
            application.endBackgroundTask(backgroundTaskID)
        }
    }
}

