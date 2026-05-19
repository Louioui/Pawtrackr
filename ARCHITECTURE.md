# Pawtrackr Architecture Guide

## Overview
Pawtrackr is a high-performance business management platform for pet professionals. It is built using **SwiftUI**, **SwiftData**, and **CloudKit**, following a modern **MVVM-R (Model-View-ViewModel-Repository)** architecture.

## Core Pillars

### 1. Data Persistence (SwiftData + CloudKit)
- **Local First:** All data is stored locally in a private SwiftData container.
- **Sync:** CloudKit synchronization is enabled for multi-device support.
- **Real-time Refresh:** `CloudKitMonitor` observes remote import events and broadcasts `.refreshRequired` via the `GlobalEventBus` to ensure the UI updates immediately across all devices.
- **Smart Deduplication:** `CloudSyncReconciler` performs post-sync cleanup, including merging duplicate visits created by concurrent check-ins on multiple devices.
- **Models:** Use the `@Model` macro. Non-sendable model objects must never cross actor boundaries.

### 2. The Repository Pattern (MVVM-R)
- **Repositories:** Act as the interface between ViewModels and the Database.
- **Background Actors:** Most repositories (e.g., `ClientRepository`) are `@ModelActor` implementations. They perform heavy fetching on background threads and return **PersistentIdentifiers** or **Sendable** data structures.
- **Safety:** This pattern ensures the Main Thread remains responsive even with 10,000+ records.

### 3. Concurrency Strategy (Swift 6)
- **Strict Concurrency:** The project uses Swift 6 strict mode.
- **Data Handoff:** ViewModels fetch IDs from background repositories and resolve them to local model objects on the `@MainActor`.
- **Atomic Transactions:** Critical operations (like Checkout) use dedicated actors (`CheckoutTransactionActor`) to ensure idempotency and data integrity.

### 4. Technical Reliability
- **Self-Healing:** `StoreHealthCheck` verifies database integrity on every launch.
- **Resilience:** `ResilienceCoordinator` manages network retries for CloudKit.
- **Chaos Testing:** The app is regularly verified using `OmniChaosTests` to simulate system failures.

## Key Utilities
- **`SearchEngine`:** High-performance, diacritic-insensitive filtering.
- **`SummaryUpdater`:** Background aggregation of revenue and KPI data.
- **`SupportService`:** Generates diagnostic reports for troubleshooting.

## Engineering Mandates
1. **Always use `Decimal` for money.** Never use Double for financial totals.
2. **Inject Repositories into ViewModels** to facilitate mocking and unit testing.
3. **Use PersistentIdentifiers** for navigation and cross-thread data handoff.
