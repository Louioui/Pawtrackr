
import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    var body: some View {
        VStack {
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .padding()

            Button("Sign In") {
                authViewModel.signIn(email: email)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
