import SwiftUI

struct MascotBadge: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.paperCream)

            Image("Kike")
                .resizable()
                .scaledToFit()
                .frame(width: size * 152 / 180, height: size * 152 / 180)
        }
        .frame(width: size, height: size)
    }
}
