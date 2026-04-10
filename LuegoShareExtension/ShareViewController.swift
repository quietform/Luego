//
//  ShareViewController.swift
//  LuegoShareExtension
//
//  Created by Arun Sasidharan on 11/11/25.
//

import UIKit
import OSLog

class ShareViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
    private static let logger = os.Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.esoxjem.Luego.share-extension",
        category: "Sharing"
    )

    private enum SharedItemKind {
        case url
        case text
    }

    private struct SharedItemCandidate {
        let provider: NSItemProvider
        let kind: SharedItemKind
    }

    private let successView = SuccessView()
    private var pendingCandidates: [SharedItemCandidate] = []
    private var nextCandidateIndex = 0
    private var lastProcessingError: String?
    private var isCompletingRequest = false

    override func viewDidLoad() {
        super.viewDidLoad()
        modalPresentationStyle = .overFullScreen
        setupUI()
        processSharedURL()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        if let presentationController = presentationController {
            presentationController.delegate = self
        }

        successView.alpha = 0
        successView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        successView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(successView)

        successView.onDismiss = { [weak self] in
            self?.dismissExtension()
        }

        NSLayoutConstraint.activate([
            successView.topAnchor.constraint(equalTo: view.topAnchor),
            successView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            successView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            successView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func processSharedURL() {
        guard let extensionContext = extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            completeWithError(message: "No items to share")
            return
        }

        pendingCandidates = sharedItemCandidates(from: inputItems)
        nextCandidateIndex = 0
        lastProcessingError = nil

        guard !pendingCandidates.isEmpty else {
            completeWithError(message: "No URL found")
            return
        }

        processNextCandidate()
    }

    private func sharedItemCandidates(from inputItems: [NSExtensionItem]) -> [SharedItemCandidate] {
        inputItems.flatMap { item in
            (item.attachments ?? []).compactMap { provider in
                if provider.hasItemConformingToTypeIdentifier("public.url") {
                    return SharedItemCandidate(provider: provider, kind: .url)
                }
                if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
                    return SharedItemCandidate(provider: provider, kind: .text)
                }
                return nil
            }
        }
    }

    private func processNextCandidate() {
        guard nextCandidateIndex < pendingCandidates.count else {
            completeWithError(message: lastProcessingError ?? "No URL found")
            return
        }

        let candidate = pendingCandidates[nextCandidateIndex]
        nextCandidateIndex += 1

        switch candidate.kind {
        case .url:
            handleURLProvider(candidate.provider)
        case .text:
            handleTextProvider(candidate.provider)
        }
    }

    private func finishProcessingCandidate(url: URL?, errorMessage: String?) {
        if let url {
            saveURL(url)
            return
        }

        if let errorMessage {
            lastProcessingError = errorMessage
        }

        processNextCandidate()
    }

    private func handleURLProvider(_ provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: "public.url", options: nil) { @Sendable [weak self] (item, error) in
            let extractedURL: URL?
            let errorMessage: String?

            if let error {
                extractedURL = nil
                errorMessage = "Failed to load URL: \(error.localizedDescription)"
            } else if let url = item as? URL {
                if SharedTextURLExtractor.isSupportedWebURL(url) {
                    extractedURL = url
                    errorMessage = nil
                } else {
                    extractedURL = nil
                    errorMessage = "Only web URLs are supported"
                }
            } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                if SharedTextURLExtractor.isSupportedWebURL(url) {
                    extractedURL = url
                    errorMessage = nil
                } else {
                    extractedURL = nil
                    errorMessage = "Only web URLs are supported"
                }
            } else {
                extractedURL = nil
                errorMessage = "Invalid URL format"
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.finishProcessingCandidate(url: extractedURL, errorMessage: errorMessage ?? "Unknown error")
            }
        }
    }

    private func handleTextProvider(_ provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { @Sendable [weak self] (item, error) in
            let extractedURL: URL?
            let errorMessage: String?

            if let error {
                extractedURL = nil
                errorMessage = "Failed to load text: \(error.localizedDescription)"
            } else if let text = item as? String, let url = SharedTextURLExtractor.extractFirstSupportedWebURL(from: text) {
                extractedURL = url
                errorMessage = nil
            } else {
                extractedURL = nil
                errorMessage = "No valid URL found in text"
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.finishProcessingCandidate(url: extractedURL, errorMessage: errorMessage ?? "Unknown error")
            }
        }
    }

    private func saveURL(_ url: URL) {
        do {
            try SharedStorage.shared.saveSharedURL(url)
            Self.logger.info("Share extension saved article URL: \(url.absoluteString, privacy: .public)")
            completeWithSuccess()
        } catch {
            Self.logger.error("Share extension failed to save article URL: \(error.localizedDescription, privacy: .public)")
            completeWithError(message: error.localizedDescription)
        }
    }

    private func completeWithSuccess() {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
            self.successView.alpha = 1
            self.successView.transform = .identity
        }
    }

    private func dismissExtension() {
        guard !isCompletingRequest else {
            return
        }

        isCompletingRequest = true
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func completeWithError(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: "LuegoShareExtension", code: -1, userInfo: [NSLocalizedDescriptionKey: message]))
        })
        self.present(alert, animated: true)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        dismissExtension()
    }
}

class SuccessView: UIView {

    private let checkmarkView = CheckmarkView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let actionButton = UIButton(type: .system)

    var onDismiss: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        backgroundColor = .clear

        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkmarkView)

        titleLabel.text = "Saved!"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.text = "Added to Luego"
        subtitleLabel.font = .systemFont(ofSize: 17, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        actionButton.setTitle("Dismiss", for: .normal)
        actionButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        actionButton.backgroundColor = .systemBlue
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.layer.cornerRadius = 12
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        addSubview(actionButton)

        NSLayoutConstraint.activate([
            checkmarkView.centerXAnchor.constraint(equalTo: centerXAnchor),
            checkmarkView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -60),
            checkmarkView.widthAnchor.constraint(equalToConstant: 80),
            checkmarkView.heightAnchor.constraint(equalToConstant: 80),

            titleLabel.topAnchor.constraint(equalTo: checkmarkView.bottomAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            actionButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 32),
            actionButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            actionButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    @objc private func actionTapped() {
        onDismiss?()
    }
}

class CheckmarkView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        let checkmarkPath = UIBezierPath()
        checkmarkPath.move(to: CGPoint(x: rect.width * 0.25, y: rect.height * 0.5))
        checkmarkPath.addLine(to: CGPoint(x: rect.width * 0.45, y: rect.height * 0.7))
        checkmarkPath.addLine(to: CGPoint(x: rect.width * 0.75, y: rect.height * 0.3))

        let shapeLayer = CAShapeLayer()
        shapeLayer.path = checkmarkPath.cgPath
        shapeLayer.strokeColor = UIColor.systemGreen.cgColor
        shapeLayer.lineWidth = 6
        shapeLayer.lineCap = .round
        shapeLayer.lineJoin = .round
        shapeLayer.fillColor = UIColor.clear.cgColor

        let circleLayer = CAShapeLayer()
        circleLayer.path = UIBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).cgPath
        circleLayer.fillColor = UIColor.systemGreen.withAlphaComponent(0.1).cgColor
        circleLayer.strokeColor = UIColor.systemGreen.cgColor
        circleLayer.lineWidth = 3

        layer.addSublayer(circleLayer)
        layer.addSublayer(shapeLayer)
    }
}
