# Pawtrackr Architecture Memory

## Checkout Pilot Decisions

- `CheckoutViewModel` is the only owner of checkout UI state. `CheckoutView` can bind to editor buffers, but every persisted value must flow back through the view model before navigation or confirmation.
- Checkout money is Decimal-only. Service subtotal, manual amount overrides, tips, payments, and line-item reconciliation must avoid `Double` currency math.
- The 4-step checkout draft is a crash-recovery boundary. Step transitions, payment method changes, external references, and tips are critical state and must be saved immediately through `CheckoutDraftStore`.
- Draft disk I/O belongs off the main actor. `CheckoutDraftStore` remains an actor for serialization, while JSON/file reads and writes execute through detached utility tasks.
- Confirm-and-pay is protected at two layers: a UI/view-model debounce blocks rapid duplicate taps, and `CheckoutTransactionActor` keeps persistence idempotent by visit UUID.
- Checkout success must not hide cleanup or refresh failures. Draft deletion and main-context refresh errors are logged instead of swallowed with `try?`.

## Data Store Pilot Decisions

- `DataStoreService` is the central SwiftData access facade. The production initializer accepts an existing `ModelContainer`; test and QualityControl code can use the `inMemory` initializer.
- Background fetches must create a detached `ModelContext` from the shared `ModelContainer`; UI-bound fetches remain on the main actor.

## Verification Notes

- The requested `platform=iOS Simulator,name=iPhone 15` destination fails on this machine when Xcode resolves `OS:latest`; use an explicit installed OS such as `OS=17.4`.
