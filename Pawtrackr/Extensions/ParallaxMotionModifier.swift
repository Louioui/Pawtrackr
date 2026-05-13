import SwiftUI
#if os(iOS)
import CoreMotion
#endif

/// A modifier that applies a subtle 3D tilt effect based on device orientation.
struct ParallaxMotionModifier: ViewModifier {
    #if os(iOS)
    @State private var motionManager = CMMotionManager()
    #endif
    @State private var pitch: Double = 0
    @State private var roll: Double = 0

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(pitch * 10), axis: (x: 1, y: 0, z: 0))
            .rotation3DEffect(.degrees(roll * 10), axis: (x: 0, y: 1, z: 0))
            .onAppear {
                #if os(iOS)
                if motionManager.isDeviceMotionAvailable {
                    motionManager.deviceMotionUpdateInterval = 0.05
                    motionManager.startDeviceMotionUpdates(to: .main) { motion, error in
                        if let motion = motion {
                            self.pitch = motion.attitude.pitch
                            self.roll = motion.attitude.roll
                        }
                    }
                }
                #endif
            }
            .onDisappear {
                #if os(iOS)
                motionManager.stopDeviceMotionUpdates()
                #endif
            }
    }
}


extension View {
    func parallaxEffect() -> some View {
        modifier(ParallaxMotionModifier())
    }
}
