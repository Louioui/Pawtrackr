import SwiftUI
import SwiftData
import OSLog

/// Buffered pet editor shared by client profiles and pet detail.
struct EditPetSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let pet: Pet
    private let baseline: PetEditFields
    @State private var fields: PetEditFields
    @State private var weightText: String
    @State private var hasBirthdate: Bool
    @State private var birthdate: Date
    @State private var isSaving = false
    @State private var error: AppError?
    @State private var confirmsRemoval = false

    init(pet: Pet) {
        self.pet = pet
        let snapshot = PetEditFields(pet: pet)
        baseline = snapshot
        _fields = State(initialValue: snapshot)
        _weightText = State(initialValue: snapshot.weight.map { NSDecimalNumber(decimal: $0).description(withLocale: Locale.current) } ?? "")
        _hasBirthdate = State(initialValue: snapshot.birthdate != nil)
        _birthdate = State(initialValue: snapshot.birthdate ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalization.localized("new_client.pets", value: "Pet")) {
                    ImagePicker(imageData: $fields.photoData) {
                        AvatarView(.pet(species: fields.species, gender: fields.gender, name: fields.name, imageData: fields.photoData), size: .lg)
                    }
                    .accessibilityLabel(AppLocalization.localized("add_pet.choose_photo", value: "Choose Photo"))
                    input("add_pet.name", fallback: "Name", text: $fields.name, limit: TextInputLimits.name)
                        .accessibilityIdentifier("editPet.name")
                    Picker(AppLocalization.localized("add_pet.species", value: "Species"), selection: $fields.species) {
                        Text(Species.dog.displayName).tag(Species.dog)
                        Text(Species.cat.displayName).tag(Species.cat)
                    }
                    Picker(AppLocalization.localized("add_pet.gender", value: "Gender"), selection: $fields.gender) {
                        Text(PetGender.male.displayName).tag(PetGender.male)
                        Text(PetGender.female.displayName).tag(PetGender.female)
                    }
                    input("add_pet.breed", fallback: "Breed", text: $fields.breed, limit: TextInputLimits.shortText)
                    input("add_pet.color", fallback: "Color", text: $fields.color, limit: TextInputLimits.shortText)
                    Toggle(AppLocalization.localized("add_pet.set_birthdate", value: "Set Birthdate"), isOn: $hasBirthdate)
                    if hasBirthdate {
                        DatePicker(AppLocalization.localized("add_pet.birthdate", value: "Birthdate"), selection: $birthdate, in: ...Date(), displayedComponents: .date)
                    }
                    input("pet.editor.weight", fallback: "Weight (lb)", text: $weightText, limit: 20)
                        .accessibilityIdentifier("editPet.weight")
                }
                Section(AppLocalization.localized("pet.editor.care", value: "Care and Behavior")) {
                    input("pet.editor.notes", fallback: "Notes", text: $fields.notes, limit: TextInputLimits.notes)
                    input("add_pet.health_notes", fallback: "Health Notes", text: $fields.health, limit: TextInputLimits.notes)
                    input("pet.editor.instructions", fallback: "Special Instructions", text: $fields.instructions, limit: TextInputLimits.notes)
                    ForEach(Pet.BehaviorTag.allCases) { tag in
                        Toggle(tag.displayName, isOn: behaviorBinding(tag))
                            .accessibilityLabel(tag.displayName)
                    }
                }
                Section {
                    if pet.archivedAt != nil {
                        Button(AppLocalization.localized("pet.editor.restore", value: "Restore Pet")) {
                            Task { await setRemoved(false) }
                        }
                        .pressScaleStyle()
                        .accessibilityLabel(AppLocalization.localized("pet.editor.restore", value: "Restore Pet"))
                    } else {
                        Button(AppLocalization.localized("pet.editor.remove", value: "Remove Pet"), role: .destructive) {
                            confirmsRemoval = true
                        }
                        .pressScaleStyle()
                        .accessibilityLabel(AppLocalization.localized("pet.editor.remove", value: "Remove Pet"))
                        .accessibilityIdentifier("editPet.remove")
                    }
                    Text(AppLocalization.localized("pet.editor.history_kept", value: "Removed pets leave current client lists. Their visit and payment history stays intact, and they can be restored."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(AppLocalization.localized("pet.editor.title", value: "Edit Pet"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.localized("common.cancel", value: "Cancel")) { dismiss() }
                        .pressScaleStyle()
                        .accessibilityLabel(AppLocalization.localized("common.cancel", value: "Cancel"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.localized("common.save", value: "Save")) { Task { await save() } }
                        .disabled(fields.name.trimmed.isEmpty)
                        .pressScaleStyle()
                        .accessibilityLabel(AppLocalization.localized("common.save", value: "Save"))
                        .accessibilityIdentifier("editPet.save")
                }
            }
            .disabled(isSaving)
            .interactiveDismissDisabled(isSaving)
            .confirmationDialog(AppLocalization.localized("pet.editor.remove", value: "Remove Pet"), isPresented: $confirmsRemoval, titleVisibility: .visible) {
                Button(AppLocalization.localized("pet.editor.remove", value: "Remove Pet"), role: .destructive) {
                    Task { await setRemoved(true) }
                }
            } message: {
                Text(AppLocalization.localized("pet.editor.history_kept", value: "Visit and payment history will be kept."))
            }
            .alert(item: $error) { error in
                Alert(title: Text(AppLocalization.localized("common.error", value: "Error")), message: Text(error.localizedDescription))
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 540, idealHeight: 650)
        #else
        .presentationDetents([.large])
        #endif
    }

    /// Provides a labeled input with the same bounds as the create-client form.
    private func input(_ key: String, fallback: String, text: Binding<String>, limit: Int) -> some View {
        TextField(AppLocalization.localized(key, value: fallback), text: text, axis: .vertical)
            .textLengthLimit(text, to: limit)
            .accessibilityLabel(AppLocalization.localized(key, value: fallback))
    }

    /// Toggles a standardized behavior while retaining unrelated legacy/custom tags.
    private func behaviorBinding(_ kind: Pet.BehaviorTag) -> Binding<Bool> {
        Binding(
            get: { fields.behaviorTags.contains { Pet.behaviorTagKind(for: $0) == kind } },
            set: { enabled in
                fields.behaviorTags.removeAll { Pet.behaviorTagKind(for: $0) == kind }
                if enabled { fields.behaviorTags.append(kind.displayName) }
            }
        )
    }

    /// Validates Decimal weight, saves via the model actor, and publishes only after commit.
    private func save() async {
        guard !isSaving else { return }
        let raw = weightText.trimmed
        if raw.isEmpty { fields.weight = nil }
        else {
            // Reject trailing garbage rather than Decimal's partial-string parsing.
            let separator = Locale.current.decimalSeparator ?? "."
            let pattern = "^[0-9]+(?:" + NSRegularExpression.escapedPattern(for: separator) + "[0-9]+)?$"
            guard raw.range(of: pattern, options: .regularExpression) != nil,
                  let weight = Decimal(string: raw, locale: .current), weight > 0 else {
                error = .validation(.custom(message: AppLocalization.localized("pet.editor.invalid_weight", value: "Enter a weight greater than zero.")))
                return
            }
            fields.weight = weight
        }
        fields.birthdate = hasBirthdate ? birthdate : nil
        isSaving = true
        defer { isSaving = false }
        do {
            let committed = try await PetEditorRepository(modelContainer: modelContext.container)
                .save(id: pet.persistentModelID, fields: fields, baseline: baseline)
            committed.apply(to: pet, changedFrom: PetEditFields(pet: pet))
            NotificationCenter.default.post(name: .clientDidUpdate, object: nil)
            HapticManager.notify(.success)
            dismiss()
        } catch { report(error) }
    }

    /// Mirrors the actor's committed removal state without deleting historical relationships.
    private func setRemoved(_ removed: Bool) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            pet.archivedAt = try await PetEditorRepository(modelContainer: modelContext.container)
                .setRemoved(id: pet.persistentModelID, removed: removed)
            NotificationCenter.default.post(name: .clientDidUpdate, object: nil)
            dismiss()
        } catch { report(error) }
    }

    /// Logs and surfaces failed persistence without dismissing the user's editor.
    private func report(_ failure: Error) {
        Logger.database.error("Pet editor failed: \(failure.localizedDescription, privacy: .public)")
        error = failure as? AppError ?? .database(failure.localizedDescription)
    }
}
