//
//  Persistence.swift
//  Todo
//
//  Created by Bash33r on 09/11/25.
//

import CoreData
import Combine

enum PersistenceError: LocalizedError {
    case loadFailed(String)
    case saveFailed(String)
    case migrationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .loadFailed(let message):
            return "Failed to load data: \(message)"
        case .saveFailed(let message):
            return "Failed to save data: \(message)"
        case .migrationFailed(let message):
            return "Failed to migrate data: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .loadFailed:
            return "Please try restarting the app. If the problem persists, contact support."
        case .saveFailed:
            return "Please check your device storage and try again."
        case .migrationFailed:
            return "Your data may need to be reset. Please contact support if this continues."
        }
    }
}

class PersistenceController: ObservableObject {
    static let shared = PersistenceController()
    
    @Published var hasError = false
    @Published var errorMessage: String?
    @Published var errorRecoverySuggestion: String?

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        let sampleTodos = ["Buy groceries", "Finish project", "Call dentist", "Read book", "Exercise"]
        for (index, title) in sampleTodos.enumerated() {
            let newTodo = TodoItem(context: viewContext)
            newTodo.title = title
            newTodo.isCompleted = index % 2 == 0
            newTodo.createdAt = Date()
        }
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            print("Preview data save failed: \(nsError.localizedDescription)")
            // Don't crash in preview - just log the error
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Todo")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Configure lightweight migration for Core Data
            let description = container.persistentStoreDescriptions.first
            description?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Log the error for debugging
                print("Core Data failed to load: \(error.localizedDescription)")
                print("Error details: \(error.userInfo)")
                
                // Determine error type and provide recovery suggestions
                let errorCode = (error as NSError).code
                var errorMessage = "Failed to load your todos."
                var recoverySuggestion = "Please try restarting the app."
                
                switch errorCode {
                case NSPersistentStoreIncompleteSaveError:
                    errorMessage = "Data save was incomplete."
                    recoverySuggestion = "Some of your todos may not have been saved. Please check and try again."
                case NSMigrationError:
                    errorMessage = "Data migration failed."
                    recoverySuggestion = "Your todos may need to be reset. This usually happens after an app update."
                case NSPersistentStoreInvalidTypeError:
                    errorMessage = "Invalid data storage."
                    recoverySuggestion = "The app data may be corrupted. Try restarting the app."
                default:
                    if error.localizedDescription.contains("disk") || error.localizedDescription.contains("space") {
                        errorMessage = "Not enough storage space."
                        recoverySuggestion = "Please free up some space on your device and try again."
                    } else if error.localizedDescription.contains("permission") {
                        errorMessage = "Permission denied."
                        recoverySuggestion = "The app needs permission to save data. Please check your settings."
                    }
                }
                
                // Set error state for UI display
                DispatchQueue.main.async {
                    self.hasError = true
                    self.errorMessage = errorMessage
                    self.errorRecoverySuggestion = recoverySuggestion
                }
                
                // Log to crash reporting service (integrate Firebase Crashlytics or similar)
                // Crashlytics.crashlytics().record(error: error)
            } else {
                // Clear any previous errors on successful load
                DispatchQueue.main.async {
                    self.hasError = false
                    self.errorMessage = nil
                    self.errorRecoverySuggestion = nil
                }
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        // Performance optimizations
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Enable undo manager for undo/redo functionality
        container.viewContext.undoManager = UndoManager()
        
        // Set undo manager limits to prevent memory issues
        container.viewContext.undoManager?.levelsOfUndo = 20
    }
}
