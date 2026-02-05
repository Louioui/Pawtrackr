//
//  Coordinator.swift
//  Pawtrackr
//
//  Legacy coordinator protocol - iOS only.
//  Navigation is now handled by NavigationRouter for cross-platform support.
//

#if canImport(UIKit)
import SwiftUI
import UIKit

protocol Coordinator: AnyObject {
    var navigationController: UINavigationController { get set }
    func start()
}
#endif
