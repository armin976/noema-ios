// OnboardingView.swift
import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct OnboardingView: View {
    @Binding var showOnboarding: Bool
    @EnvironmentObject var experience: AppExperienceCoordinator
    @State private var currentPage = 0
    @StateObject private var embedInstaller = EmbedModelInstaller()
    @State private var animateElements = false
    @State private var logoScale: CGFloat = 0.5
    @State private var textOpacity: Double = 0
    @State private var isDownloadingEmbedModel = false
    @State private var embedProgress: Double = 0
    @Environment(\.colorScheme) var colorScheme
    
    let totalPages = 4
    
    // Color Palette - Navy and White
    var navyBlue: Color {
        colorScheme == .dark ? Color(red: 173/255, green: 185/255, blue: 202/255) : Color(red: 20/255, green: 40/255, blue: 80/255)
    }
    
    var navyAccent: Color {
        colorScheme == .dark ? Color(red: 143/255, green: 165/255, blue: 192/255) : Color(red: 40/255, green: 60/255, blue: 100/255)
    }
    
    var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 16/255, green: 20/255, blue: 28/255) : Color.white
    }
    
    var secondaryBackground: Color {
        colorScheme == .dark ? Color(red: 24/255, green: 30/255, blue: 42/255) : Color(red: 248/255, green: 250/255, blue: 252/255)
    }
    
    var textPrimary: Color {
        colorScheme == .dark ? Color.white : Color(red: 10/255, green: 20/255, blue: 40/255)
    }
    
    var textSecondary: Color {
        colorScheme == .dark ? Color(red: 180/255, green: 190/255, blue: 210/255) : Color(red: 100/255, green: 110/255, blue: 130/255)
    }
    
    var body: some View {
        ZStack {
            // Clean background
            backgroundColor
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Page content
                TabView(selection: $currentPage) {
                    ScrollView {
                        welcomePage
                            .padding(.vertical, 20)
                    }
                    .tag(0)
                    
                    ScrollView {
                        overviewPage
                            .padding(.vertical, 20)
                    }
                    .tag(1)
                    
                    ScrollView {
                        modelsPage
                            .padding(.vertical, 20)
                    }
                    .tag(2)
                    
                    ScrollView {
                        getStartedPage
                            .padding(.vertical, 20)
                    }
                    .tag(3)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)
                
                // Navigation
                navigationView
                    .padding(.horizontal, 30)
                    .padding(.bottom, 50)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                logoScale = 1.0
            }
            withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
                textOpacity = 1.0
                animateElements = true
            }
            // Ensure the embed installer reflects current disk state if the user reopens onboarding
            embedInstaller.refreshStateFromDisk()
        }
    }
    
    private var welcomePage: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Logo and title
            VStack(spacing: 24) {
                Image("Noema")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .scaleEffect(logoScale)
                
                VStack(spacing: 12) {
                    Text("Welcome to Noema")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundColor(textPrimary)
                        .opacity(textOpacity)
                    
                    Text("Your private AI workspace")
                        .font(.title3)
                        .foregroundColor(textSecondary)
                        .opacity(textOpacity)
                }
            }
            
            Spacer()
            
            // Key benefits
            VStack(spacing: 24) {
                benefitRow(
                    icon: "lock.shield",
                    title: "100% Private",
                    description: "Your data never leaves your device"
                )
                
                benefitRow(
                    icon: "cpu",
                    title: "Runs Locally",
                    description: "No cloud required"
                )
                
                benefitRow(
                    icon: "books.vertical",
                    title: "Smart Datasets",
                    description: "Add open textbooks and datasets to guide answers"
                )
            }
            .padding(.horizontal, 40)
            .opacity(animateElements ? 1 : 0)
            .animation(.easeOut(duration: 0.8).delay(0.4), value: animateElements)
            
            Spacer()
        }
    }
    
    private func benefitRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(navyBlue)
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(textPrimary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(textSecondary)
            }
            
            Spacer()
        }
    }
    
    private var overviewPage: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                Text("What is Noema?")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(textPrimary)
                
                Text("Think of Noema as a simple way to run AI on your device. To get useful answers, you pair a local model with datasets (like open textbooks). We’ll guide you through the first setup.")
                    .font(.body)
                    .foregroundColor(textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .lineSpacing(4)
            }
            .padding(.top, 40)
            
            onboardingImageView(keywords: ["Onboarding2", "overview", "interface", "home"], height: 200)
            
            VStack(spacing: 20) {
                Text("How it works")
                    .font(.headline)
                    .foregroundColor(textPrimary)
                
                VStack(alignment: .leading, spacing: 16) {
                    stepRow(number: "1", text: "Download AI models that run locally")
                    stepRow(number: "2", text: "Add datasets to enhance model knowledge")
                    stepRow(number: "3", text: "Chat with AI using your curated sources")
                }
                .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .opacity(animateElements ? 1 : 0)
        .animation(.easeOut(duration: 0.6), value: animateElements)
    }
    
    private func stepRow(number: String, text: String) -> some View {
        HStack(spacing: 16) {
            Text(number)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(navyBlue)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(navyBlue.opacity(0.1))
                )
            
            Text(text)
                .font(.body)
                .foregroundColor(textPrimary)
            
            Spacer()
        }
    }
    
    private var modelsPage: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                Text("Pick a model and add a dataset")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(textPrimary)
                
                Text("Start by installing one model. Then add a dataset (like an open textbook) so the AI can answer with grounded knowledge.")
                    .font(.body)
                    .foregroundColor(textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 40)
            
            // Models section
            VStack(spacing: 20) {
                Text("Model Formats")
                    .font(.headline)
                    .foregroundColor(textPrimary)
                
                HStack(spacing: 16) {
                    modelFormatCard(icon: "cube", title: "GGUF", description: "Good default · portable")
                    modelFormatCard(icon: "bolt", title: "MLX", description: "Apple Silicon optimized")
                    modelFormatCard(icon: "rectangle.stack", title: "LeapAI", description: "Optional small model backend")
                }
                .padding(.horizontal, 30)
            }
            
            onboardingImageView(keywords: ["Onboarding3", "models", "model", "selection"], height: 150)
            
            // Datasets section
            VStack(spacing: 16) {
                Text("Enhance with Datasets")
                    .font(.headline)
                    .foregroundColor(textPrimary)
                
                Text("Add one or two datasets (like open textbooks) to keep responses accurate and help the AI cite sources.")
                    .font(.body)
                    .foregroundColor(textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .lineSpacing(4)
            }
            
            Spacer()
        }
        .opacity(animateElements ? 1 : 0)
        .animation(.easeOut(duration: 0.6), value: animateElements)
    }
    
    private func modelFormatCard(icon: String, title: String, description: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(navyBlue)
            
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(textPrimary)
            
            Text(description)
                .font(.caption2)
                .foregroundColor(textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(secondaryBackground)
        .cornerRadius(8)
    }
    
    private var getStartedPage: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                Text("Get Started")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(textPrimary)
                
                Text("First, enable fast dataset search")
                    .font(.body)
                    .foregroundColor(textSecondary)
            }
            .padding(.top, 40)
            
            onboardingImageView(keywords: ["Onboarding4", "get-started", "getting-started", "setup", "start"], height: 180)
            
            // Embedding model download section
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Label("Enable dataset search", systemImage: "magnifyingglass")
                        .font(.headline)
                        .foregroundColor(textPrimary)
                    
                    Text("Download a small embedding model so Noema can index and search your datasets")
                        .font(.caption)
                        .foregroundColor(textSecondary)
                        .multilineTextAlignment(.center)
                    
                    Text("320 MB • One-time download")
                        .font(.caption2)
                        .foregroundColor(textSecondary.opacity(0.8))
                }
                
                if embedInstaller.state == .ready {
                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundColor(.green)
                } else {
                    VStack(spacing: 12) {
                        Button(action: {
                            startEmbeddingDownload()
                        }) {
                            if isDownloadingEmbedModel {
                                HStack(spacing: 12) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .scaleEffect(0.8)
                                    Text(downloadStatusText)
                                        .font(.body)
                                }
                                .frame(width: 200)
                            } else {
                                Text("Download Now")
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .frame(width: 200)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(navyBlue)
                        .disabled(isDownloadingEmbedModel || embedInstaller.state == .ready)
                        .accessibilityLabel("Download embedding model")
                        .accessibilityHint("Installs the small model used for local dataset search.")

                        if isDownloadingEmbedModel && embedProgress > 0 {
                            ProgressView(value: embedProgress)
                                .frame(width: 240)
                                .tint(navyBlue)
                        }
                    }
                }
                
                Button(action: completeOnboarding) {
                    Text(embedInstaller.state == .ready ? "Start Using Noema" : "Skip for Now")
                        .font(.body)
                        .foregroundColor(embedInstaller.state == .ready ? navyBlue : textSecondary)
                }
                .padding(.top, 8)
            }
            .padding(24)
            .background(secondaryBackground)
            .cornerRadius(12)
            .padding(.horizontal, 30)
            
            Spacer()
        }
        .opacity(animateElements ? 1 : 0)
        .animation(.easeOut(duration: 0.6), value: animateElements)
    }

    private func completeOnboarding() {
        withAnimation(.easeInOut) {
            showOnboarding = false
        }
        experience.markOnboardingComplete()
    }

    private func onboardingImageView(keywords: [String], height: CGFloat) -> some View {
        Group {
            if let img = loadOnboardingImage(keywords: keywords) {
                img
                    .resizable()
                    .scaledToFit()
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 30)
            } else {
                fallbackOnboardingImage()
                    .resizable()
                    .scaledToFit()
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 30)
            }
        }
    }

    private func loadOnboardingImage(keywords: [String]) -> Image? {
        let candidateAssetNames: [String] = keywords.flatMap { key in
            let k = key
            return [
                k,
                "Onboarding_\(k)",
                "onboarding_\(k)",
                "Onboarding-\(k)",
                "onboarding-\(k)"
            ]
        }
#if canImport(UIKit)
        for name in candidateAssetNames {
            if let ui = UIImage(named: name) {
                return Image(uiImage: ui)
            }
        }
        if let urls = Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: "OnboardingImages") {
            let lowerKeywords = keywords.map { $0.lowercased() }
            let exts = Set(["png","jpg","jpeg","heic","heif","webp","gif","pdf"])
            if let url = urls.first(where: { url in
                exts.contains(url.pathExtension.lowercased()) &&
                lowerKeywords.contains(where: { url.lastPathComponent.lowercased().contains($0) })
            }) {
                if let img = UIImage(contentsOfFile: url.path) {
                    return Image(uiImage: img)
                }
            }
        }
#endif
#if canImport(AppKit)
        for name in candidateAssetNames {
            if let ns = NSImage(named: NSImage.Name(name)) {
                return Image(nsImage: ns)
            }
        }
        if let urls = Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: "OnboardingImages") {
            let lowerKeywords = keywords.map { $0.lowercased() }
            let exts = Set(["png","jpg","jpeg","heic","heif","webp","gif","pdf"])
            if let url = urls.first(where: { url in
                exts.contains(url.pathExtension.lowercased()) &&
                lowerKeywords.contains(where: { url.lastPathComponent.lowercased().contains($0) })
            }) {
                if let ns = NSImage(contentsOf: url) {
                    return Image(nsImage: ns)
                }
            }
        }
#endif
        return nil
    }
    
    private func fallbackOnboardingImage() -> Image {
#if canImport(UIKit)
        if let ui = UIImage(named: "Noema") {
            return Image(uiImage: ui)
        }
#endif
#if canImport(AppKit)
        if let ns = NSImage(named: NSImage.Name("Noema")) {
            return Image(nsImage: ns)
        }
#endif
        return Image(systemName: "photo.on.rectangle.angled")
    }
    
    private var downloadStatusText: String {
        switch embedInstaller.state {
        case .downloading:
            return "Downloading..."
        case .verifying:
            return "Verifying..."
        case .installing:
            return "Installing..."
        default:
            return "Preparing..."
        }
    }
    
    private func startEmbeddingDownload() {
        isDownloadingEmbedModel = true
        embedProgress = 0
        
        // Create a timer to smoothly update progress
        let progressTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
        var timerCancellable: AnyCancellable?
        
        timerCancellable = progressTimer.sink { _ in
            if self.embedInstaller.state == .downloading {
                self.embedProgress = self.embedInstaller.progress
            }
        }
        
        Task { @MainActor in
            await embedInstaller.installIfNeeded()
            
            // Cancel the timer
            timerCancellable?.cancel()
            
            // Ensure final progress
            embedProgress = embedInstaller.state == .ready ? 1.0 : embedProgress
            
            // After installation completes, proactively load & warm up the backend
            if embedInstaller.state == .ready {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000) // brief delay to ensure FS move complete
                    await EmbeddingModel.shared.warmUp()
                } catch {
                    // Ignore; UI already reflects installer state
                }
            }
            
            isDownloadingEmbedModel = false
        }
    }
    
    private var navigationView: some View {
        HStack {
            // Skip button (except on last page)
            if currentPage < totalPages - 1 {
                Button("Skip", action: completeOnboarding)
                .keyboardShortcut(.escape, modifiers: [])
                .foregroundColor(textSecondary)
            } else {
                Spacer()
                    .frame(width: 60)
            }
            
            Spacer()
            
            // Page indicators
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? navyBlue : textSecondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .scaleEffect(index == currentPage ? 1.2 : 1)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentPage)
                }
            }
            
            Spacer()
            
            // Next button
            if currentPage < totalPages - 1 {
                Button("Next") {
                    withAnimation {
                        currentPage += 1
                        animateElements = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            animateElements = true
                        }
                    }
                }
                .fontWeight(.medium)
                .foregroundColor(navyBlue)
            } else {
                Spacer()
                    .frame(width: 60)
            }
        }
    }
}

#Preview {
    OnboardingView(showOnboarding: .constant(true))
        .environmentObject(AppExperienceCoordinator())
}