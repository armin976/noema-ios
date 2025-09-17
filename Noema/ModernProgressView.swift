// ModernProgressView.swift
import SwiftUI

/// A modern progress view with fluid animations
struct ModernProgressView: View {
    let value: Double
    var tint: Color = .blue
    var height: CGFloat = 4
    
    @State private var animatedValue: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: height)
                
                // Progress fill
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [tint, tint.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * animatedValue, height: height)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0), value: animatedValue)
                
                // Shimmer effect
                if animatedValue > 0 && animatedValue < 1 {
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0),
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * 0.3, height: height)
                        .offset(x: geometry.size.width * animatedValue - geometry.size.width * 0.15)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: height)
        .onAppear {
            animatedValue = value
        }
        .onChange(of: value) { newValue in
            animatedValue = newValue
        }
    }
}

/// A modern circular progress indicator
struct ModernCircularProgressView: View {
    @State private var rotation: Double = 0
    @State private var trimEnd: Double = 0.1
    var size: CGFloat = 40
    var lineWidth: CGFloat = 3
    var tint: Color = .blue
    
    var body: some View {
        Circle()
            .trim(from: 0, to: trimEnd)
            .stroke(
                LinearGradient(
                    gradient: Gradient(colors: [tint, tint.opacity(0.5)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
                
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    trimEnd = 0.8
                }
            }
    }
}

/// A download progress view with percentage
struct ModernDownloadProgressView: View {
    let progress: Double
    let speed: Double? // MB/s
    var showPercentage: Bool = true
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                if showPercentage {
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                
                Spacer()
                
                if let speed = speed, speed > 0 {
                    Text(Self.formattedSpeedText(speed))
                }
            }
            
            ModernProgressView(value: progress)
        }
    }
}

private extension ModernDownloadProgressView {
    static func formattedSpeedText(_ bytesPerSecond: Double) -> String {
        // Convert to KB/s or MB/s for display
        let kbps = bytesPerSecond / 1_024.0
        if kbps > 1_024.0 {
            return String(format: "%.1f MB/s", kbps / 1_024.0)
        }
        return String(format: "%.0f KB/s", kbps)
    }
}

// View modifier to easily apply modern progress styling
extension View {
    func modernProgress() -> some View {
        self.progressViewStyle(ModernProgressViewStyle())
    }
}

struct ModernProgressViewStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        if let fractionCompleted = configuration.fractionCompleted {
            ModernProgressView(value: fractionCompleted)
        } else {
            ModernCircularProgressView()
        }
    }
}