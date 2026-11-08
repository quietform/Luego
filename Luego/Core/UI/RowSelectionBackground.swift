import SwiftUI

struct RowSelectionBackground: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(isSelected ? Color.regularSelectionFill : Color.clear)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
    }
}
