//
//  ContentView.swift
//  Todo
//
//  Created by Bash33r on 09/11/25.
//

import SwiftUI
import CoreData
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FocusState private var isTextFieldFocused: Bool
    @ObservedObject private var persistenceController = PersistenceController.shared

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TodoItem.createdAt, ascending: false)],
        animation: .default)
    private var todos: FetchedResults<TodoItem>
    
    // Performance optimization: Batch size for efficient fetching
    private let batchSize = 50
    
    @State private var newTodoTitle = ""
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showPersistenceError = false
    @State private var undoManagerState = 0 // Force view updates when undo stack changes
    @State private var validationMessage: String? = nil
    @State private var showValidationWarning = false
    @State private var showImportSheet = false
    @State private var showExportSheet = false
    @State private var exportURL: URL?
    @State private var showImportError = false
    @State private var importErrorMessage: String?
    
    private let maxTodoLength = 500
    private var remainingCharacters: Int {
        max(0, maxTodoLength - newTodoTitle.count)
    }
    private var isNearLimit: Bool {
        remainingCharacters < 50 && remainingCharacters > 0
    }
    private var isAtLimit: Bool {
        remainingCharacters == 0
    }
    
    private var undoManager: UndoManager? {
        viewContext.undoManager
    }
    
    private var canUndo: Bool {
        let result = undoManager?.canUndo ?? false
        return result
    }
    
    private var canRedo: Bool {
        let result = undoManager?.canRedo ?? false
        return result
    }

    var body: some View {
        NavigationStack {
            todoList
                .safeAreaInset(edge: .bottom) {
                    inputSection
                }
                .navigationTitle("Todos")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        undoRedoButtons
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        trailingToolbarButtons
                    }
                }
                .onChange(of: viewContext.hasChanges) { oldValue, newValue in
                    if newValue || oldValue != newValue {
                        undoManagerState += 1
                    }
                }
                .onAppear {
                    undoManagerState = 0
                }
                .alert("Unable to Save", isPresented: $showError, presenting: errorMessage) { _ in
                    Button("OK", role: .cancel) { }
                } message: { message in
                    Text(message)
                }
                .alert("Data Error", isPresented: $showPersistenceError) {
                    Button("Retry") {
                        persistenceController.hasError = false
                    }
                    Button("OK", role: .cancel) { }
                } message: {
                    persistenceErrorMessage
                }
                .onChange(of: persistenceController.hasError) { oldValue, newValue in
                    if newValue {
                        showPersistenceError = true
                    }
                }
                .sheet(isPresented: $showImportSheet) {
                    DocumentPicker { url in
                        importTodos(from: url)
                    }
                }
                .sheet(isPresented: $showExportSheet) {
                    if let url = exportURL {
                        ShareSheet(activityItems: [url])
                    }
                }
                .alert("Import Error", isPresented: $showImportError, presenting: importErrorMessage) { _ in
                    Button("OK", role: .cancel) { }
                } message: { message in
                    Text(message)
                }
                .alert("Validation Warning", isPresented: $showValidationWarning, presenting: validationMessage) { _ in
                    Button("OK", role: .cancel) { }
                } message: { message in
                    Text(message)
                }
        }
    }
    
    private var todoList: some View {
        List {
            if todos.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Todos", systemImage: "checklist")
                    } description: {
                        Text("Add your first todo item to get started")
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(todos) { todo in
                    TodoRowView(
                        todo: todo,
                        onToggle: {
                            toggleComplete(todo: todo)
                        },
                        onEdit: { newTitle in
                            editTodo(todo: todo, newTitle: newTitle)
                        }
                    )
                    .id(todo.objectID)
                }
                .onDelete(perform: deleteTodos)
            }
        }
    }
    
    private var inputSection: some View {
        VStack(spacing: 8) {
            if isNearLimit || isAtLimit {
                HStack {
                    Text(isAtLimit ? "Character limit reached" : "\(remainingCharacters) characters remaining")
                        .font(.caption)
                        .foregroundColor(isAtLimit ? .red : .orange)
                    Spacer()
                }
                .padding(.horizontal)
            }
            
            HStack(spacing: 12) {
                todoTextField
                addButton
            }
        }
        .padding()
        .background(.regularMaterial)
    }
    
    private var todoTextField: some View {
        TextField("New Todo", text: $newTodoTitle, prompt: Text("Enter new todo"))
            .textFieldStyle(.roundedBorder)
            .focused($isTextFieldFocused)
            .onSubmit {
                addTodo()
            }
            .submitLabel(.done)
            .onChange(of: newTodoTitle) { oldValue, newValue in
                if newValue.count > maxTodoLength {
                    newTodoTitle = String(newValue.prefix(maxTodoLength))
                    validationMessage = "Todo text is too long. Maximum \(maxTodoLength) characters allowed."
                    showValidationWarning = true
                } else {
                    validationMessage = nil
                    showValidationWarning = false
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isAtLimit ? Color.red : (isNearLimit ? Color.orange : Color.clear), lineWidth: 1)
            )
            .accessibilityLabel("New todo text field")
            .accessibilityHint(isAtLimit ? "Character limit reached. \(remainingCharacters) characters remaining." : "Enter the text for a new todo item. \(remainingCharacters) characters remaining.")
            .accessibilityValue(isAtLimit ? "At character limit" : "\(remainingCharacters) characters remaining")
    }
    
    private var addButton: some View {
        Button(action: addTodo) {
            Label("Add Todo", systemImage: "plus.circle.fill")
                .labelStyle(.iconOnly)
        }
        .disabled(newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAtLimit)
        .accessibilityLabel("Add todo")
        .accessibilityHint("Adds a new todo item to the list")
    }
    
    private var undoRedoButtons: some View {
        HStack(spacing: 8) {
            Button(action: undo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.body)
            }
            .disabled(!canUndo)
            .opacity(canUndo ? 1.0 : 0.3)
            .accessibilityLabel("Undo")
            
            Button(action: redo) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.body)
            }
            .disabled(!canRedo)
            .opacity(canRedo ? 1.0 : 0.3)
            .accessibilityLabel("Redo")
        }
    }
    
    private var trailingToolbarButtons: some View {
        HStack(spacing: 8) {
            EditButton()
                .disabled(todos.isEmpty)
            
            Menu {
                Button(action: exportTodos) {
                    Label("Export Todos", systemImage: "square.and.arrow.up")
                }
                .disabled(todos.isEmpty)
                
                Button(action: { showImportSheet = true }) {
                    Label("Import Todos", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
    
    @ViewBuilder
    private var persistenceErrorMessage: some View {
        if let message = persistenceController.errorMessage, let suggestion = persistenceController.errorRecoverySuggestion, !suggestion.isEmpty {
            Text("\(message)\n\n\(suggestion)")
        } else if let message = persistenceController.errorMessage {
            Text(message)
        } else {
            Text("An error occurred.")
        }
    }
    
    private func exportTodos() {
        do {
            let data = try ExportManager.shared.exportTodos(context: viewContext)
            
            // Create temporary file for sharing
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "todos_\(Date().timeIntervalSince1970).json"
            let fileURL = tempDir.appendingPathComponent(fileName)
            
            try data.write(to: fileURL)
            exportURL = fileURL
            showExportSheet = true
        } catch {
            errorMessage = "Failed to export todos: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func importTodos(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            
            // Try JSON first
            if url.pathExtension == "json" {
                try ExportManager.shared.importTodos(from: data, into: viewContext)
            } else if url.pathExtension == "csv" {
                if let csvString = String(data: data, encoding: .utf8) {
                    try ExportManager.shared.importTodosFromCSV(csvString, into: viewContext)
                } else {
                    throw NSError(domain: "ImportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid CSV encoding"])
                }
            } else {
                // Try JSON as default
                try ExportManager.shared.importTodos(from: data, into: viewContext)
            }
        } catch {
            importErrorMessage = "Failed to import todos: \(error.localizedDescription)"
            showImportError = true
        }
    }

    private func addTodo() {
        let trimmedTitle = newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            validationMessage = "Todo cannot be empty. Please enter some text."
            showValidationWarning = true
            return
        }
        
        guard trimmedTitle.count <= maxTodoLength else {
            validationMessage = "Todo is too long. Maximum \(maxTodoLength) characters allowed."
            showValidationWarning = true
            return
        }
        
        // Final validation - limit todo title length to prevent UI issues
        let finalTitle = String(trimmedTitle.prefix(maxTodoLength))
        
        viewContext.processPendingChanges()
        viewContext.undoManager?.beginUndoGrouping()
        let newTodo = TodoItem(context: viewContext)
        newTodo.title = finalTitle
        newTodo.isCompleted = false
        newTodo.createdAt = Date()
        viewContext.undoManager?.setActionName("Add Todo")
        viewContext.undoManager?.endUndoGrouping()
        viewContext.processPendingChanges()
        
        newTodoTitle = ""
        isTextFieldFocused = false
        undoManagerState += 1
        
        saveContext()
    }
    
    private func toggleComplete(todo: TodoItem) {
        viewContext.processPendingChanges()
        viewContext.undoManager?.beginUndoGrouping()
        let oldValue = todo.isCompleted
        todo.isCompleted.toggle()
        viewContext.undoManager?.registerUndo(withTarget: todo) { target in
            target.isCompleted = oldValue
            self.undoManagerState += 1
        }
        viewContext.undoManager?.setActionName(todo.isCompleted ? "Complete Todo" : "Uncomplete Todo")
        viewContext.undoManager?.endUndoGrouping()
        viewContext.processPendingChanges()
        undoManagerState += 1
        
        saveContext()
    }

    private func deleteTodos(offsets: IndexSet) {
        viewContext.processPendingChanges()
        viewContext.undoManager?.beginUndoGrouping()
        let todosToDelete = offsets.map { todos[$0] }
        todosToDelete.forEach { todo in
            viewContext.delete(todo)
        }
        viewContext.undoManager?.setActionName("Delete Todo\(todosToDelete.count > 1 ? "s" : "")")
        viewContext.undoManager?.endUndoGrouping()
        viewContext.processPendingChanges()
        undoManagerState += 1
        
        saveContext()
    }
    
    private func editTodo(todo: TodoItem, newTitle: String) {
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }
        
        // Limit todo title length
        let maxLength = 500
        let finalTitle = String(trimmedTitle.prefix(maxLength))
        
        viewContext.processPendingChanges()
        viewContext.undoManager?.beginUndoGrouping()
        let oldTitle = todo.title ?? ""
        todo.title = finalTitle
        viewContext.undoManager?.registerUndo(withTarget: todo) { target in
            target.title = oldTitle
            self.undoManagerState += 1
        }
        viewContext.undoManager?.setActionName("Edit Todo")
        viewContext.undoManager?.endUndoGrouping()
        viewContext.processPendingChanges()
        undoManagerState += 1
        
        saveContext()
    }
    
    private func undo() {
        guard viewContext.undoManager?.canUndo == true else { return }
        viewContext.undoManager?.undo()
        viewContext.processPendingChanges()
        undoManagerState += 1
        saveContext()
    }
    
    private func redo() {
        guard viewContext.undoManager?.canRedo == true else { return }
        viewContext.undoManager?.redo()
        viewContext.processPendingChanges()
        undoManagerState += 1
        saveContext()
    }
    
    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            var userMessage = "Failed to save changes."
            
            // Provide specific error messages based on error type
            if nsError.code == NSValidationErrorMaximum || nsError.code == NSValidationErrorMinimum {
                userMessage = "Invalid data. Please check your input."
            } else if nsError.code == NSSQLiteError || nsError.code == NSPersistentStoreSaveError {
                userMessage = "Storage error. Please check your device storage."
            } else if nsError.domain == NSCocoaErrorDomain {
                userMessage = "Data error. Please try again."
            }
            
            errorMessage = userMessage
            showError = true
            print("Unresolved error \(nsError), \(nsError.userInfo)")
            
            // Log to crash reporting service
            // Crashlytics.crashlytics().record(error: error)
        }
    }
}

struct TodoRowView: View {
    let todo: TodoItem
    let onToggle: () -> Void
    let onEdit: (String) -> Void
    
    @State private var isEditing = false
    @State private var editedTitle = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isCompleted ? Color.accentColor : Color.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(isEditing)
            
            if isEditing {
                TextField("Todo", text: $editedTitle)
                    .textFieldStyle(.plain)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        saveEdit()
                    }
                    .onAppear {
                        editedTitle = todo.title ?? ""
                        isTextFieldFocused = true
                    }
                    .onChange(of: editedTitle) { oldValue, newValue in
                        // Limit input length
                        if newValue.count > 500 {
                            editedTitle = String(newValue.prefix(500))
                        }
                    }
                    .submitLabel(.done)
            } else {
                Text(todo.title ?? "")
                    .strikethrough(todo.isCompleted)
                    .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        startEditing()
                    }
            }
            
            Spacer()
            
            if isEditing {
                Button(action: saveEdit) {
                    Label("Save", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                
                Button(action: cancelEdit) {
                    Label("Cancel", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isEditing ? "Editing todo" : (todo.title ?? "Todo"))
        .accessibilityHint(todo.isCompleted ? "Completed. Double tap to mark as not completed" : "Not completed. Double tap to mark as completed. Double tap and hold to edit")
        .accessibilityValue(todo.isCompleted ? "Completed" : "Not completed")
    }
    
    private func startEditing() {
        editedTitle = todo.title ?? ""
        isEditing = true
    }
    
    private func saveEdit() {
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            onEdit(trimmedTitle)
        }
        isEditing = false
        isTextFieldFocused = false
    }
    
    private func cancelEdit() {
        isEditing = false
        isTextFieldFocused = false
        editedTitle = todo.title ?? ""
    }
}

struct ChecklistToggleStyle: ToggleStyle {
    #if os(iOS)
    private static let hapticGenerator: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        return generator
    }()
    #endif
    
    func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            configuration.isOn.toggle()
            #if os(iOS)
            ChecklistToggleStyle.hapticGenerator.impactOccurred()
            #endif
        }) {
            HStack(spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(configuration.isOn ? Color.accentColor : Color.secondary)
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isOn)
                
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
