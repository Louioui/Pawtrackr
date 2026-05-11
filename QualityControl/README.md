# QualityControl

Focused quality-control coverage added for Pawtrackr production flows.

Suites:
- `InsightsQualityControlUITests`: Insights loading, picker state, scroll depth, refresh responsiveness.
- `ClientsQualityControlUITests`: direct-launch Clients smoke checks, search, add-client sheet.
- `SettingsQualityControlUITests`: security toggles, disable-lock confirmation, export reachability.
- `CheckoutQualityControlUITests`: payment validation, method switching, review navigation.
- `PetHistoryQualityControlUITests`: pet-history sheet, search, scope switching.
- `RecentHistoryQualityControlUITests`: dashboard history entry, search, scope switching.
- `OnboardingQualityControlUITests`: welcome/backflow, PIN mismatch guardrails, demo-data completion.

Supporting coverage:
- `ResilienceCoordinatorTests`: retry behavior and CloudKit retry classification.

Typical local run:

```bash
xcodebuild test -project Pawtrackr.xcodeproj -scheme Pawtrackr -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'
```
