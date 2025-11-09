//
//  TodoApp.swift
//  Todo
//
//  Created by Bash33r on 09/11/25.
//

import SwiftUI
import CoreData

@main
struct TodoApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
