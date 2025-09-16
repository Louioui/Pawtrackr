
import SwiftUI
import SwiftData

struct AppointmentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var appointments: [Appointment]
    @State private var newAppointmentDate = Date()
    @State private var selectedPet: Pet?

    var body: some View {
        NavigationStack {
            List {
                ForEach(appointments) { appointment in
                    VStack(alignment: .leading) {
                        Text(appointment.pet.name)
                        Text(appointment.date, style: .date)
                    }
                }
                .onDelete(perform: deleteAppointment)
            }
            .navigationTitle("Appointments")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: addAppointment) {
                        Label("Add Appointment", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: .constant(true)) {
                VStack {
                    DatePicker("Date", selection: $newAppointmentDate)
                    PetSelectionView(selectedPet: $selectedPet)
                    Button("Save") {
                        addAppointment()
                    }
                }
            }
        }
    }

    private func addAppointment() {
        guard let pet = selectedPet else { return }
        let newAppointment = Appointment(date: newAppointmentDate, pet: pet, user: User(name: "", email: ""))
        modelContext.insert(newAppointment)
    }

    private func deleteAppointment(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(appointments[index])
            }
        }
    }
}

struct PetSelectionView: View {
    @Query private var pets: [Pet]
    @Binding var selectedPet: Pet?

    var body: some View {
        Picker("Pet", selection: $selectedPet) {
            ForEach(pets) { pet in
                Text(pet.name).tag(pet as Pet?)
            }
        }
    }
}
