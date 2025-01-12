import SwiftUI
import PDFKit
import WebKit

// MARK: - OnboardingStep
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case termsAndConditions
    case licenseActivation
    case setup
    
    var title: String {
        switch self {
        case .welcome:
            return "Welcome to DropBeat"
        case .termsAndConditions:
            return "Terms & Conditions"
        case .licenseActivation:
            return "Activate Your License"
        case .setup:
            return "Quick Setup"
        }
    }
}

// MARK: - OnboardingViewModel
class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome
    @Published var agreedToTerms: Bool = false
    @Published var licenseKey: String = "" {
        didSet {
            // Prevent recursive calls
            guard licenseKey != oldValue else { return }
            
            // Format license key as user types
            var cleaned = licenseKey.uppercased().filter { $0.isLetter || $0.isNumber }
            
            // Limit total length first
            if cleaned.count > 10 {
                cleaned = String(cleaned.prefix(10))
            }
            
            // Format with dashes
            var formatted = cleaned
            if cleaned.count >= 2 {
                // Add DB- prefix if not present
                if !cleaned.hasPrefix("DB") {
                    formatted = "DB" + cleaned.dropFirst(2)
                }
                
                // Add dashes for sections
                if cleaned.count > 2 {
                    formatted = "DB-" + cleaned.dropFirst(2)
                    if cleaned.count > 6 {
                        let secondPart = cleaned.dropFirst(2).prefix(4)
                        let thirdPart = cleaned.dropFirst(6).prefix(4)
                        formatted = "DB-\(secondPart)-\(thirdPart)"
                    }
                }
            }
            
            // Update only if different to prevent recursive updates
            if formatted != licenseKey {
                licenseKey = formatted
            }
        }
    }
    @Published var isValidating: Bool = false
    @Published var validationError: String?
    @Published var hasCompletedYTMusicSetup: Bool = false
    @Published var hasCompletedExtensionSetup: Bool = false
    @Published var showConfetti: Bool = false
    
    func validateLicense() async {
        guard !licenseKey.isEmpty else {
            validationError = "Please enter a license key"
            return
        }
        
        isValidating = true
        do {
            let response = try await LicenseService.shared.validateLicense(key: licenseKey)
            if response.valid {
                AppStateManager.shared.saveLicenseKey(licenseKey)
                validationError = nil
                showConfetti = true
                // Reset confetti after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.showConfetti = false
                }
                await moveToNextStep()
            } else {
                validationError = response.error ?? "Invalid license key"
            }
        } catch {
            validationError = error.localizedDescription
        }
        isValidating = false
    }
    
    @MainActor
    func moveToNextStep() {
        if let nextIndex = OnboardingStep.allCases.firstIndex(where: { $0 == currentStep })?.advanced(by: 1),
           let nextStep = OnboardingStep(rawValue: nextIndex) {
            withAnimation {
                currentStep = nextStep
            }
        }
    }
}

struct StyledTextView: NSViewRepresentable {
    let attributedString: NSAttributedString
    
    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        
        // Set default paragraph style with line spacing
        let defaultParagraphStyle = NSMutableParagraphStyle()
        defaultParagraphStyle.lineSpacing = 8 // Add 8 points of space between lines
        textView.defaultParagraphStyle = defaultParagraphStyle
        
        return textView
    }
    
    func updateNSView(_ nsView: NSTextView, context: Context) {
        nsView.textStorage?.setAttributedString(attributedString)
    }
}

struct OnboardingView: View {
    @StateObject private var viewModel: OnboardingViewModel
    @Environment(\.dismiss) private var dismiss
    private let bottomBarHeight: CGFloat = 44
    
    init(viewModel: OnboardingViewModel = OnboardingViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        ZStack {
            // Main Content
            VStack(spacing: 0) {
                // Title and Content
                switch viewModel.currentStep {
                case .welcome:
                    WelcomeStepContent(viewModel: viewModel)
                case .termsAndConditions:
                    TermsStepContent()
                case .licenseActivation:
                    LicenseStepContent(
                        licenseKey: $viewModel.licenseKey,
                        isValidating: viewModel.isValidating,
                        validationError: viewModel.validationError
                    )
                case .setup:
                    SetupStepContent(
                        hasCompletedYTMusicSetup: $viewModel.hasCompletedYTMusicSetup,
                        hasCompletedExtensionSetup: $viewModel.hasCompletedExtensionSetup
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            // Offset up by half the bottom bar height for visual centering when bottom bar is present
            .offset(y: viewModel.currentStep != .welcome ? -bottomBarHeight/2 : 0)
            
            // Bottom Button Bar - Only show for non-welcome steps
            if viewModel.currentStep != .welcome {
                VStack {
                    Spacer()
                    BottomBar(viewModel: viewModel, dismiss: dismiss)
                }
            }
            
            // Confetti Animation
            LottieConfettiView(isVisible: viewModel.showConfetti)
                .allowsHitTesting(false)
                .frame(width: 600, height: 400)
        }
        .frame(width: 600, height: 400)
        .background(Color(.windowBackgroundColor))
    }
}

struct WelcomeStepContent: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()
                
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.2), radius: 4)
                    .padding(.bottom, 32)
                
                VStack(spacing: 8) {
                    Text("Welcome to DropBeats")
                        .font(.system(size: 24, weight: .bold))
                        .multilineTextAlignment(.center)
                    
                    Text("The Missing YouTube Music Player for Mac")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 24)
                
                Button {
                    withAnimation {
                        viewModel.moveToNextStep()
                    }
                } label: {
                    Text("Let's Get Started")
                        .font(.system(size: 14, weight: .regular))
                        .frame(minWidth: 120)
                        
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .offset(y: -20)  // Slight upward adjustment for visual balance
        }
    }
}

struct TermsStepContent: View {
    @State private var termsText: String = ""
    private let bottomBarHeight: CGFloat = 44
    private let verticalPadding: CGFloat = 24
    
    var formattedText: AttributedString {
        let attributedString = NSMutableAttributedString(string: termsText)
        let lines = termsText.components(separatedBy: .newlines)
        var currentPosition = 0
        
        // Set paragraph style with line spacing for the entire text
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 8  // Add 8 points of space between lines
        paragraphStyle.paragraphSpacing = 12 // Add extra space between paragraphs
        attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attributedString.length))
        
        for line in lines {
            let range = NSRange(location: currentPosition, length: line.count)
            
            // Format main titles (all caps lines)
            if line.uppercased() == line && !line.isEmpty {
                attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: NSFont.systemFontSize + 2, weight: .bold), range: range)
            }
            // Format numbered sections (e.g., "1.1", "3.2")
            else if line.matches(of: #/^\d+\.\d+\s+.*/#).first != nil {
                attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .bold), range: range)
            }
            // Format subtitles (lines ending with :)
            else if line.hasSuffix(":") {
                attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: NSFont.systemFontSize + 1, weight: .bold), range: range)
                attributedString.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
            }
            // Format bullet points
            else if line.hasPrefix("•") {
                attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: NSFont.systemFontSize), range: range)
                attributedString.addAttribute(.foregroundColor, value: NSColor.textColor.withAlphaComponent(0.7), range: range)
            }
            
            currentPosition += line.count + 1 // +1 for newline character
        }
        
        return AttributedString(attributedString)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 36))
                .foregroundColor(.accentColor)
            
            VStack(spacing: 8) {
                Text("Terms & Conditions")
                    .font(.system(size: 24, weight: .bold))
                
                Text("Please read and accept our terms")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            // Document Container
            ScrollView {
                VStack(spacing: 0) {
                    Text(formattedText)
                        .font(.system(.body))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                        .background(Color.white)
                }
                .background(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .padding([.horizontal, .bottom], 16)
            }
            .padding(.top, 16) // Add padding at the top of the scroll view
            .frame(height: 400 - bottomBarHeight - verticalPadding * 2 - 140)
            .background(Color.black.opacity(0.05))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
        }
        .padding(.top, 32)
        .frame(maxHeight: .infinity, alignment: .center)
        .onAppear {
            // Try loading without subdirectory first
            if let termsURL = Bundle.main.url(forResource: "terms", withExtension: "txt"),
               let content = try? String(contentsOf: termsURL, encoding: .utf8) {
                termsText = content
                print("Terms loaded successfully from root")
            }
            // Try with Resources subdirectory
            else if let termsURL = Bundle.main.url(forResource: "terms", withExtension: "txt", subdirectory: "Resources"),
               let content = try? String(contentsOf: termsURL, encoding: .utf8) {
                termsText = content
                print("Terms loaded successfully from Resources directory")
            }
            // Try direct path as fallback
            else {
                print("Attempting to load from direct paths...")
                let possiblePaths = [
                    Bundle.main.bundlePath + "/Contents/Resources/terms.txt",
                    Bundle.main.bundlePath + "/Resources/terms.txt",
                    Bundle.main.resourcePath! + "/terms.txt"
                ]
                
                for path in possiblePaths {
                    print("Trying path: \(path)")
                    if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                        termsText = content
                        print("Terms loaded successfully from: \(path)")
                        break
                    }
                }
                
                if termsText.isEmpty {
                    print("Failed to load terms.txt from all paths")
                }
            }
        }
    }
}

struct LicenseStepContent: View {
    @Binding var licenseKey: String
    let isValidating: Bool
    let validationError: String?
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 36))
                .foregroundColor(.accentColor)
            
            VStack(spacing: 8) {
                Text("Activate Your License")
                    .font(.system(size: 24, weight: .bold))
                
                Text("Enter your license key to activate DropBeat")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 16) {
                TextField("DB-XXXX-XXXX", text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(width: 160)
                    .textCase(.uppercase)
                
                if let error = validationError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Color(.systemRed))
                            .imageScale(.small)
                        Text(error)
                            .foregroundColor(Color(.systemRed))
                            .font(.caption)
                    }
                }
            }
            .padding(.top, 8)
        }
    }
}

struct BottomBar: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let dismiss: DismissAction
    
    var body: some View {
        HStack(spacing: 12) {
            switch viewModel.currentStep {
            case .welcome:
                EmptyView()
                
            case .termsAndConditions:
                Toggle(isOn: $viewModel.agreedToTerms) {
                    Text("I agree to the Terms & Conditions")
                }
                .toggleStyle(.checkbox)
                
                Spacer()
                
                Button("Accept & Continue") {
                    viewModel.moveToNextStep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.agreedToTerms)
                
            case .licenseActivation:
                Button("Go Back") {
                    withAnimation { viewModel.currentStep = .termsAndConditions }
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button {
                    Task {
                        await viewModel.validateLicense()
                    }
                } label: {
                    if viewModel.isValidating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Activate License")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.licenseKey.isEmpty || viewModel.isValidating)
                
            case .setup:
                Button("Go Back") {
                    withAnimation { viewModel.currentStep = .licenseActivation }
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Complete Setup") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.hasCompletedYTMusicSetup || !viewModel.hasCompletedExtensionSetup)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
        .background(
            Rectangle()
                .fill(.background.opacity(0.3))
                .background(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 1, y: -1)
        )
    }
}

struct SetupStepContent: View {
    @Binding var hasCompletedYTMusicSetup: Bool
    @Binding var hasCompletedExtensionSetup: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundColor(.accentColor)
            
            VStack(spacing: 8) {
                Text("License Key Activated")
                    .font(.system(size: 24, weight: .bold))
                
                Text("Just two more steps to complete your setup")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 16) {
                SetupStepRow(
                    step: 1,
                    title: "Open YouTube Music",
                    description: "First, let's open YouTube Music in your default browser",
                    isCompleted: hasCompletedYTMusicSetup,
                    action: {
                        if let url = URL(string: "https://music.youtube.com") {
                            NSWorkspace.shared.open(url)
                            hasCompletedYTMusicSetup = true
                        }
                    }
                )
                
                SetupStepRow(
                    step: 2,
                    title: "Install Chrome Extension",
                    description: "Install our Chrome extension to control YouTube Music",
                    isCompleted: hasCompletedExtensionSetup,
                    action: {
                        if let url = URL(string: "https://chrome.google.com/webstore/detail/your-extension-id") {
                            NSWorkspace.shared.open(url)
                            hasCompletedExtensionSetup = true
                        }
                    }
                )
            }
            .padding(.top, 8)
        }
    }
}

struct SetupStepRow: View {
    let step: Int
    let title: String
    let description: String
    let isCompleted: Bool
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                if isCompleted {
                    Circle()
                        .fill(Color.blue.opacity(0.8))
                        .frame(width: 32, height: 32)
                } else {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.8), lineWidth: 2)
                        .frame(width: 32, height: 32)
                }
                
                if isCompleted {
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                        .imageScale(.small)
                } else {
                    Text("\(step)")
                        .foregroundColor(Color.accentColor)
                        .font(.headline)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(isCompleted ? "Done" : "Open") {
                action()
            }
            .buttonStyle(.bordered)
            .disabled(isCompleted)
        }
        .padding()
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

#Preview {
    OnboardingView()
}


