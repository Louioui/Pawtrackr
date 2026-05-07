
import SwiftUI
import SwiftData

struct AppointmentsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authViewModel: AuthenticationViewModel
    @Query(sort: \Appointment.date) private var appointments: [Appointment]
    @State private var showingAddSheet = false
    @State private var selectedDate = Date()
    @State private var selectedPet: Pet?
    private let wrapsInNavigationStack: Bool

    init(wrapsInNavigationStack: Bool = true) {
        self.wrapsInNavigationStack = wrapsInNavigationStack
    }

    var body: some View {
        if wrapsInNavigationStack {
            NavigationStack {
                appointmentsContent
            }
        } else {
            appointmentsContent
        }
    }

    private var appointmentsContent: some View {
        List {
            if appointments.isEmpty {
                ContentUnavailableView("No Appointments", systemImage: "calendar.badge.plus", description: Text("Schedule your first appointment by tapping the plus button."))
            } else {
                ForEach(appointments) { appointment in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appointment.pet?.name ?? NSLocalizedString("common.unknown_pet", comment: ""))
                                .font(.headline)
                            Text(appointment.date, style: .date)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(appointment.date, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deleteAppointment)
            }
        }
        .navigationTitle(NSLocalizedString("appointments.title", comment: ""))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddSheet = true }) {
                    Label(NSLocalizedString("appointments.add", comment: ""), systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddAppointmentView(isPresented: $showingAddSheet, onSave: addAppointment)
        }
    }

    private func addAppointment(pet: Pet, date: Date) {
        let newAppointment = Appointment(date: date, pet: pet, user: authViewModel.currentUser)
        modelContext.insert(newAppointment)
        try? modelContext.save()
    }

    private func deleteAppointment(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(appointments[index])
            }
            try? modelContext.save()
        }
    }
}

struct AddAppointmentView: View {
    @Binding var isPresented: Bool
    var onSave: (Pet, Date) -> Void
    
    @Query(sort: \Pet.name) private var pets: [Pet]
    @State private var selectedPet: Pet?
    @State private var selectedDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Pet")) {
                    if pets.isEmpty {
                        Text("No pets available. Please add a client and pet first.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Select Pet", selection: $selectedPet) {
                            Text("Select a pet").tag(nil as Pet?)
                            ForEach(pets) { pet in
                                Text(pet.name).tag(pet as Pet?)
                            }
                        }
                    }
                }
                
                Section(header: Text("Date & Time")) {
                    DatePicker("Appointment Date", selection: $selectedDate)
                }
            }
            .navigationTitle("New Appointment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let pet = selectedPet {
                            onSave(pet, selectedDate)
                            isPresented = false
                        }
                    }
                    .disabled(selectedPet == nil)
                }
            }
        }
    }
}
