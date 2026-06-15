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
                    HStack(spacing: 12) {
                        Button(action: { sendMessage(method: .sms) }) {
                            Label("SMS", systemImage: "message.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                        }
                        
                        Button(action: { sendMessage(method: .whatsapp) }) {
                            Label("WhatsApp", systemImage: "bubble.left.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                        }
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
        #if os(macOS)
        // macOS sheets size-to-fit and otherwise render cramped; give the
        // template picker a comfortable, iOS-like canvas.
        .frame(minWidth: 440, idealWidth: 460, minHeight: 560, idealHeight: 640)
        #endif
    }
    
    enum MessageMethod {
        case sms, whatsapp
    }
    
    private func sendMessage(method: MessageMethod) {
        guard let phone = pet.owner?.phone else { return }
        
        let urlString: String?
        switch method {
        case .sms:
            urlString = PhoneUtils.smsURLString(phone, body: customMessage)
        case .whatsapp:
            urlString = PhoneUtils.whatsappURLString(phone, body: customMessage)
        }
        
        guard let urlString = urlString, let url = URL(string: urlString) else { return }
        
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
        dismiss()
    }
}
