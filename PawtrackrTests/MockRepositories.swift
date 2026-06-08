import Foundation
import SwiftData
@testable import Pawtrackr

/// A thread-safe mock repository for testing ClientsViewModel without a database.
final class MockClientRepository: ClientRepositoryProtocol, @unchecked Sendable {
    var clients: [PersistentIdentifier] = []
    var activeClients: [PersistentIdentifier] = []
    var shouldFail = false
    
    func fetchClients(query: String, limit: Int, offset: Int) async throws -> [PersistentIdentifier] {
        if shouldFail { throw AppError.database("Mock Failure") }
        return Array(clients.prefix(limit))
    }
    
    func fetchActiveClients(query: String) async throws -> [PersistentIdentifier] {
        return activeClients
    }
    
    func fetchInactiveClients(query: String, limit: Int, offset: Int) async throws -> ([PersistentIdentifier], Bool) {
        let page = Array(clients.prefix(limit))
        return (page, clients.count > limit)
    }
    
    func findClient(byPhone phone: String) async throws -> PersistentIdentifier? {
        return nil
    }
    
    func createClient(firstName: String, lastName: String, phone: String, email: String, address: String, photoData: Data?, pets: [NewPetData], contacts: [NewContactData]) async throws -> PersistentIdentifier {
        let id = await PersistentIdentifier.demoClient
        clients.append(id)
        return id
    }
    
    func saveClient(id: PersistentIdentifier, firstName: String, lastName: String, phone: String, email: String) async throws {}
    
    func deleteClient(id: PersistentIdentifier) async throws {
        clients.removeAll { $0 == id }
    }
}

/// A thread-safe mock for Dashboard testing.
final class MockDashboardRepository: DashboardRepositoryProtocol, @unchecked Sendable {
    var kpi = DashboardKPI()
    var activeVisits: [PersistentIdentifier] = []

    func fetchKPIs() async throws -> DashboardKPI { return kpi }
    func fetchActiveVisits() async throws -> [PersistentIdentifier] { return activeVisits }
    func fetchRecentClients(limit: Int) async throws -> [PersistentIdentifier] { return [] }
    func fetchOverduePets(limit: Int) async throws -> [PersistentIdentifier] { return [] }
    func fetchServiceDistribution(days: Int) async throws -> [String : Int] { return [:] }
    func fetchCategoryDistribution(days: Int) async throws -> [String : Int] { return [:] }
    func fetchRevenueSeries(days: Int) async throws -> [Date : Decimal] { return [:] }
}
