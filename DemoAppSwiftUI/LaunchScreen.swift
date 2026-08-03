//
// WoodChat — внутренний мессенджер Woodstream.
//

import SwiftUI

/// Экран запуска WoodChat: логотип (пузырь с годовыми кольцами) на тёплом фоне.
struct StreamLogoLaunch: View {
    @State private var appeared = false

    private let wood = Color(red: 0.48, green: 0.29, blue: 0.13)
    private let woodLight = Color(red: 0.75, green: 0.54, blue: 0.32)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [woodLight.opacity(0.25), wood.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(LinearGradient(colors: [woodLight, wood], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 120, height: 120)

                    Ellipse()
                        .fill(Color(red: 1.0, green: 0.97, blue: 0.94))
                        .frame(width: 78, height: 62)
                        .offset(y: -4)

                    ForEach([36, 22, 10], id: \.self) { radius in
                        Circle()
                            .stroke(wood, lineWidth: 7)
                            .frame(width: CGFloat(radius), height: CGFloat(radius))
                            .offset(y: -4)
                    }
                }
                .scaleEffect(appeared ? 1 : 0.85)
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: appeared)

                (Text("Wood").foregroundColor(wood) + Text("Chat").foregroundColor(woodLight))
                    .font(.system(size: 34, weight: .bold))

                Text("Мессенджер Woodstream")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear { appeared = true }
    }
}
