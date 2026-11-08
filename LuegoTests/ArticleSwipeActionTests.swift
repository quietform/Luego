import SwiftUI
import Testing

struct ArticleSwipeActionTests {
    @Test
    func deleteOwnsItsRedTintSoTintedLayoutsCannotRecolorIt() {
        #expect(ArticleSwipeAction.delete.tint == .red)
    }
}
