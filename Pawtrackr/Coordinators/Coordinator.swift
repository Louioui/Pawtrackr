
import SwiftUI

protocol Coordinator: AnyObject {
    var navigationController: UINavigationController { get set }
    func start()
}
