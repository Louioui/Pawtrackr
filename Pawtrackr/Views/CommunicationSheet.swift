//
//  CommunicationSheet.swift
//  Pawtrackr
//
//  Sheet to select a template and send a message to a client.
//

import SwiftUI
import SwiftData

struct CommunicationSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query private var templates: [MessageTemplate]
    
    let pet: Pet
    let visit: Visit?
    
    @State private var selectedTemplate: MessageTemplate?
    @State private var customMessage: String = ""
    
    var body: some View {
        NavigationStack {
            VStack {
                if templates.isEmpty {
                    ContentUnavailableView("No Templates", systemImage: "text.bubble", description: Text("Add templates in Settings to quickly message clients."))
                } else {
                    List {
                        Section("Templates") {
                            ForEach(templates) { template in
                                Button {
                                    selectedTemplate = template
                                    customMessage = template.processedContent(pet: pet, visit: visit)
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(template.title).font(.headline)
                                        Text(template.processedContent(pet: pet, visit: visit))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                        
                        if selectedTemplate != nil {
                            Section("Message Preview") {
                                TextEditor(text: $customMessage)
                                    .frame(minHeight: 100)
                            }
                        }
                    }
                }
                
                if !customMessage.isEmpty {
                    Button(action: sendMessage) {
                        Label("Send via SMS", systemImage: "message.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                    .padding()
                }
            }
            .navigationTitle("Message \(pet.owner?.firstName ?? "Client")")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func sendMessage() {
        guard let phone = pet.owner?.phone,
              let urlString = PhoneUtils.smsURLString(phone, body: customMessage),
              let url = URL(string: urlString) else { return }
        
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
        dismiss()
    }
}
