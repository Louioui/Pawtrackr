import SwiftUI
import SwiftData

struct DevicesHealthView: View {
    @Query(sort: \DeviceStatus.deviceName) private var devices: [DeviceStatus]
    
    var body: some View {
        // Using a simple Vstack wrapper for now as CardView is not accessible here
        VStack(spacing: 16) {
            Text("Device Sync Status")
                .font(.headline)
            List(devices) { device in
                HStack {
                    Text(device.deviceName)
                    Spacer()
                    Circle()
                        .fill(device.isOnline ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}
