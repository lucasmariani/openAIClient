//
//  SceneDelegate.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import UIKit
import CoreData

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var chatDataManager: OAChatDataManager?
    private var coreDataManager: OACoreDataManager?
    private var repository: ChatRepository?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).

        guard let windowScene = scene as? UIWindowScene else { return }

        let splitViewController = UISplitViewController(style: .doubleColumn)

        splitViewController.preferredDisplayMode = .automatic
        splitViewController.preferredSplitBehavior = .automatic
        splitViewController.displayModeButtonVisibility = .automatic

        // Initialize CoreData manager asynchronously
        Task {
            let coreDataManager = await OACoreDataManager()
            
            // Create single repository instance shared by both components
            guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "API_KEY") as? String else {
                fatalError("Error retrieving API_KEY")
            }
            let configuration = URLSessionConfiguration.default
            let service = OAOpenAIServiceFactory.service(apiKey: apiKey, configuration: configuration)
            let streamProvider = OAResponseStreamProvider(service: service, model: .gpt41nano)
            let repository = OAChatRepositoryImpl(coreDataManager: coreDataManager, streamProvider: streamProvider)
            
            await MainActor.run {
                let chatDataManager = OAChatDataManager(repository: repository)
                
                // Store references for lifecycle management
                self.coreDataManager = coreDataManager
                self.chatDataManager = chatDataManager
                self.repository = repository

                let sidebar = OASidebarViewController(chatDataManager: chatDataManager)
                let sidebarNav = UINavigationController(rootViewController: sidebar)

                let chatVC = OAChatViewController(chatDataManager: chatDataManager)
                let detailNav = UINavigationController(rootViewController: chatVC)

                splitViewController.setViewController(sidebarNav, for: .primary)
                splitViewController.setViewController(detailNav, for: .secondary)
            }
        }

        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = splitViewController
        window?.makeKeyAndVisible()
    }


    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        
        // Note: CloudKit sync is handled automatically via remote change notifications
        // No manual sync needed here since we set up proper observers
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
        
        // Force save Core Data context to ensure no data loss
        OACoreDataStack.shared.saveContext()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
        
        // Check for CloudKit updates when returning to foreground
        Task {
            if let coreDataManager = coreDataManager {
                try? await coreDataManager.fetchPersistedChats()
            }
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
        
        // Force save Core Data context
        OACoreDataStack.shared.saveContext()
    }
}

