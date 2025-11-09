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

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TodoItem.createdAt, ascending: false)],
        animation: .default)
    private var todos: FetchedResults<TodoItem>
    
    @State private var newTodoTitle = ""
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            List {
                if todos.isEmpty {
                    ContentUnavailableView {
                        Label("No Todos", systemImage: "checklist")
                    } description: {
                        Text("Add your first todo item to get started")
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(todos) { todo in
                        TodoRowView(todo: todo, onToggle: {
                            toggleComplete(todo: todo)
                        })
                    }
                    .onDelete(perform: deleteTodos)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    TextField("New Todo", text: $newTodoTitle, prompt: Text("Enter new todo"))
                        .textFieldStyle(.roundedBorder)
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            addTodo()
                        }
                        .submitLabel(.done)
                        .accessibilityLabel("New todo text field")
                        .accessibilityHint("Enter the text for a new todo item")
                    
                    Button(action: addTodo) {
                        Label("Add Todo", systemImage: "plus.circle.fill")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add todo")
                    .accessibilityHint("Adds a new todo item to the list")
                }
                .padding()
                .background(.regularMaterial)
            }
            .navigationTitle("Todos")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                        .disabled(todos.isEmpty)
                }
            }
            .alert("Unable to Save", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK", role: .cancel) { }
            } message: { message in
                Text(message)
            }
        }
    }

    private func addTodo() {
        let trimmedTitle = newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }
        
        let newTodo = TodoItem(context: viewContext)
        newTodo.title = trimmedTitle
        newTodo.isCompleted = false
        newTodo.createdAt = Date()
        
        newTodoTitle = ""
        isTextFieldFocused = false
        
        saveContext()
    }
    
    private func toggleComplete(todo: TodoItem) {
        todo.isCompleted.toggle()
        saveContext()
    }

    private func deleteTodos(offsets: IndexSet) {
        offsets.map { todos[$0] }.forEach(viewContext.delete)
        saveContext()
    }
    
    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            errorMessage = "Failed to save changes. Please try again."
            showError = true
            print("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
}

struct TodoRowView: View {
    let todo: TodoItem
    let onToggle: () -> Void
    
    var body: some View {
        Toggle(isOn: Binding(
            get: { todo.isCompleted },
            set: { _ in onToggle() }
        )) {
            Text(todo.title)
                .strikethrough(todo.isCompleted)
                .foregroundStyle(todo.isCompleted ? .secondary : .primary)
        }
        .toggleStyle(ChecklistToggleStyle())
        .accessibilityLabel(todo.title)
        .accessibilityHint(todo.isCompleted ? "Completed. Double tap to mark as not completed" : "Not completed. Double tap to mark as completed")
        .accessibilityValue(todo.isCompleted ? "Completed" : "Not completed")
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
