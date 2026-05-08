
import SwiftUI
import SwiftData
import OSLog

struct AppointmentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationViewModel.self) private var authViewModel
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
        do {
            try modelContext.save()
        } catch {
            Logger.appointments.error("addAppointment save failed: \(String(describing: error))")
        }
    }

    private func deleteAppointment(offsets: IndexSet) {
        // Snapshot the targets BEFORE the animation. Deleting then iterating
        // a live @Query result can cause "index out of range" if SwiftUI
        // re-evaluates the @Query mid-deletion.
        let targets = offsets.compactMap { offset -> Appointment? in
            guard offset < appointments.count else { return nil }
            return appointments[offset]
        }
        withAnimation {
            for appointment in targets {
                modelContext.delete(appointment)
            }
            do {
                try modelContext.save()
            } catch {
                Logger.appointments.error("deleteAppointment save failed: \(String(describing: error))")
            }
        }
    }
}

private extension Logger {
    static let appointments = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "Appointments")
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
