
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
    @State private var appError: AppError?
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
                ContentUnavailableView(
                    NSLocalizedString("appointments.empty_title", value: "No Appointments", comment: ""),
                    systemImage: "calendar.badge.plus",
                    description: Text(NSLocalizedString("appointments.empty_description", value: "Schedule your first appointment by tapping the plus button.", comment: ""))
                )
            } else {
                ForEach(appointments) { appointment in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appointment.pet?.name ?? NSLocalizedString("common.unknown_pet", comment: ""))
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(appointment.date, style: .date)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        Text(appointment.date, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
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
        .alert(item: $appError) { error in
            Alert(
                title: Text(NSLocalizedString("common.error", comment: "")),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text(NSLocalizedString("common.ok", comment: "")))
            )
        }
    }

    private func addAppointment(pet: Pet, date: Date) {
        let newAppointment = Appointment(date: date, pet: pet, user: authViewModel.currentUser)
        modelContext.insert(newAppointment)
        do {
            try modelContext.save()
            CloudKitMonitor.shared.recordLocalChange("Saved appointment")
        } catch {
            // Roll back the insert before surfacing the error so the
            // user retrying doesn't end up with a duplicate object in the
            // context. SwiftData's `insert` is reversed by `delete` even
            // before the next save.
            modelContext.delete(newAppointment)
            Logger.appointments.error("addAppointment save failed: \(String(describing: error))")
            CloudKitMonitor.shared.reportLocalSaveError(error, operation: "saving appointment")
            appError = .database(error.localizedDescription)
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
                CloudKitMonitor.shared.recordLocalChange("Deleted appointment")
            } catch {
                Logger.appointments.error("deleteAppointment save failed: \(String(describing: error))")
                CloudKitMonitor.shared.reportLocalSaveError(error, operation: "deleting appointment")
                appError = .database(error.localizedDescription)
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
                Section(header: Text(NSLocalizedString("appointments.section.pet", value: "Pet", comment: ""))) {
                    if pets.isEmpty {
                        Text(NSLocalizedString("appointments.no_pets_available", value: "No pets available. Please add a client and pet first.", comment: ""))
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(NSLocalizedString("appointments.select_pet", value: "Select Pet", comment: ""), selection: $selectedPet) {
                            Text(NSLocalizedString("appointments.select_pet_placeholder", value: "Select a pet", comment: "")).tag(nil as Pet?)
                            ForEach(pets) { pet in
                                Text(pet.name).tag(pet as Pet?)
                            }
                        }
                    }
                }

                Section(header: Text(NSLocalizedString("appointments.section.date_time", value: "Date & Time", comment: ""))) {
                    DatePicker(
                        NSLocalizedString("appointments.date_picker_label", value: "Appointment Date", comment: ""),
                        selection: $selectedDate,
                        in: Date()...   // disallow scheduling in the past
                    )
                }
            }
            .navigationTitle(NSLocalizedString("appointments.new_title", value: "New Appointment", comment: ""))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.cancel", comment: "")) { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("common.save", comment: "")) {
                        if let pet = selectedPet {
                            onSave(pet, selectedDate)
                            isPresented = false
                        }
                    }
                    .disabled(selectedPet == nil)
                }
            }
            .onAppear {
                // Auto-select the only pet so the user can save immediately
                // instead of being blocked by the "Save" disabled state.
                if pets.count == 1, selectedPet == nil {
                    selectedPet = pets.first
                }
            }
        }
    }
}
