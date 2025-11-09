//
//  ExportManager.swift
//  Todo
//
//  Created by Bash33r on 09/11/25.
//

import Foundation
import CoreData
import SwiftUI

struct TodoExportData: Codable {
    let todos: [TodoItemData]
    let exportDate: Date
    let version: String
    
    struct TodoItemData: Codable {
        let title: String
        let isCompleted: Bool
        let createdAt: Date?
    }
}

class ExportManager {
    static let shared = ExportManager()
    
    private init() {}
    
    func exportTodos(context: NSManagedObjectContext) throws -> Data {
        let fetchRequest: NSFetchRequest<TodoItem> = TodoItem.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \TodoItem.createdAt, ascending: false)]
        
        let todos = try context.fetch(fetchRequest)
        
        let todoData = todos.map { todo in
            TodoExportData.TodoItemData(
                title: todo.title ?? "",
                isCompleted: todo.isCompleted,
                createdAt: todo.createdAt
            )
        }
        
        let exportData = TodoExportData(
            todos: todoData,
            exportDate: Date(),
            version: "1.0"
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        return try encoder.encode(exportData)
    }
    
    func exportTodosAsCSV(context: NSManagedObjectContext) throws -> String {
        let fetchRequest: NSFetchRequest<TodoItem> = TodoItem.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \TodoItem.createdAt, ascending: false)]
        
        let todos = try context.fetch(fetchRequest)
        
        var csv = "Title,Completed,Created At\n"
        
        let dateFormatter = ISO8601DateFormatter()
        
        for todo in todos {
            let title = (todo.title ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let completed = todo.isCompleted ? "Yes" : "No"
            let createdAt = todo.createdAt != nil ? dateFormatter.string(from: todo.createdAt!) : ""
            
            csv += "\"\(title)\",\"\(completed)\",\"\(createdAt)\"\n"
        }
        
        return csv
    }
    
    func importTodos(from data: Data, into context: NSManagedObjectContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let exportData = try decoder.decode(TodoExportData.self, from: data)
        
        for todoData in exportData.todos {
            let todo = TodoItem(context: context)
            todo.title = todoData.title
            todo.isCompleted = todoData.isCompleted
            todo.createdAt = todoData.createdAt ?? Date()
        }
        
        try context.save()
    }
    
    func importTodosFromCSV(_ csv: String, into context: NSManagedObjectContext) throws {
        let lines = csv.components(separatedBy: .newlines)
        guard lines.count > 1 else { return }
        
        let dateFormatter = ISO8601DateFormatter()
        
        // Skip header line
        for line in lines.dropFirst() {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            
            let components = parseCSVLine(line)
            guard components.count >= 2 else { continue }
            
            let title = components[0].trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            
            let completed = components[1].trimmingCharacters(in: .whitespaces).lowercased() == "yes"
            let createdAt: Date? = components.count >= 3 && !components[2].isEmpty
                ? dateFormatter.date(from: components[2]) : nil
            
            let todo = TodoItem(context: context)
            todo.title = title
            todo.isCompleted = completed
            todo.createdAt = createdAt ?? Date()
        }
        
        try context.save()
    }
    
    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)
        
        return result
    }
}

