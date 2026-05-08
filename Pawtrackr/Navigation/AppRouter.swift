//
//  AppRouter.swift
//  Pawtrackr
//
//  Centralized navigation router for unified, programmatical navigation.
//

import SwiftUI
import SwiftData

@Observable
final class AppRouter {
    var path = NavigationPath()
    
    enum Route: Hashable {
        case clientDetail(PersistentIdentifier)
        case checkout(PersistentIdentifier)
        case visitDetail(PersistentIdentifier)
    }
    
    func navigate(to route: Route) {
        path.append(route)
    }
    
    func pop() {
        path.removeLast()
    }
}
