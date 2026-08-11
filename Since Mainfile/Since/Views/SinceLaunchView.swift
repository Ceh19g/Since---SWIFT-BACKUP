import SwiftUI

struct SinceLaunchView: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 64, weight: .regular))
                        .foregroundStyle(.orange)
                        .offset(y: -34)

                    Image(systemName: "hourglass")
                        .font(.system(size: 112, weight: .medium))
                        .foregroundStyle(.primary)

                    Capsule()
                        .fill(.teal)
                        .frame(width: 34, height: 11)
                        .offset(y: 23)
                }
                .frame(width: 136, height: 136)

                Text("Since")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    SinceLaunchView()
}

#Preview("Dark") {
    SinceLaunchView()
        .preferredColorScheme(.dark)
}
