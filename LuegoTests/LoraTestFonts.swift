import CoreText
import Foundation
import SwiftUI
import UIKit

enum LoraTestFonts {
    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Luego/Resources/Fonts/Lora")

    private static let registration: Void = {
        let fontURLs = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in fontURLs where url.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    static func register() {
        registration
    }
}

@MainActor
func renderedWidth(of view: some View) -> CGFloat {
    let controller = UIHostingController(rootView: view.fixedSize())
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 2000, height: 400))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    controller.view.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    controller.view.layoutIfNeeded()
    return controller.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).width
}
