import os
import SwiftUI
import UIKit

struct AnimationCalibration: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> AnimationCalibrationController {
        AnimationCalibrationController()
    }

    func updateUIViewController(_ uiViewController: AnimationCalibrationController, context: Context) {}
}

final class AnimationCalibrationController: UIViewController {
    private let canvas = CalibrationCanvas()
    private let startButton = UIButton(type: .system)
    private let resultLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        startButton.setTitle("Start calibration", for: .normal)
        startButton.accessibilityIdentifier = "calibration.start"
        startButton.addTarget(self, action: #selector(start), for: .touchUpInside)
        resultLabel.accessibilityIdentifier = "calibration.result"
        resultLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let stack = UIStackView(arrangedSubviews: [canvas, startButton, resultLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            canvas.heightAnchor.constraint(equalToConstant: 240)
        ])
    }

    @objc private func start() {
        resultLabel.text = nil
        startButton.isEnabled = false
        canvas.start { [weak self] result in
            self?.resultLabel.text = result
            self?.startButton.isEnabled = true
        }
    }
}

private final class CalibrationCanvas: UIView {
    private var link: CADisplayLink?
    private var interval: OSSignpostIntervalState?
    private var started = 0.0
    private var elapsed = 0.0
    private var draws = 0
    private var stalls = 0
    private var stallMilliseconds = 0.0
    private let stalled = ProcessInfo.processInfo.arguments.contains("--benchmark-stall")
    private var completion: ((String) -> Void)?

    func start(completion: @escaping (String) -> Void) {
        self.completion = completion
        draws = 0
        stalls = 0
        stallMilliseconds = 0
        elapsed = 0
        started = CACurrentMediaTime()
        interval = BenchmarkSignposts.signposter.beginAnimationInterval("CalibrationAnimation", id: BenchmarkSignposts.signposter.makeSignpostID())
        let link = CADisplayLink(target: self, selector: #selector(tick))
        self.link = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func tick() {
        if elapsed >= 3, let interval {
            link?.invalidate()
            link = nil
            BenchmarkSignposts.signposter.endInterval("CalibrationAnimation", interval)
            self.interval = nil
            completion?("\(draws)|\(stalls)|\(Int(stallMilliseconds))|\(CACurrentMediaTime() - started)")
            completion = nil
        } else {
            elapsed = CACurrentMediaTime() - started
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard interval != nil else { return }
        precondition(Thread.isMainThread)
        if stalled, stalls == 0, elapsed >= 0.8 {
            let signposter = BenchmarkSignposts.signposter
            let stall = signposter.beginInterval("InjectedDrawStall", id: signposter.makeSignpostID())
            let start = CACurrentMediaTime()
            Thread.sleep(forTimeInterval: 0.2)
            stallMilliseconds = (CACurrentMediaTime() - start) * 1_000
            stalls += 1
            signposter.endInterval("InjectedDrawStall", stall)
        }
        UIColor.systemBackground.setFill()
        UIRectFill(bounds)
        UIColor.systemBlue.setFill()
        let progress = min(elapsed / 3, 1)
        UIRectFill(CGRect(x: progress * (bounds.width - 40), y: 80, width: 40, height: 80))
        draws += 1
    }
}
