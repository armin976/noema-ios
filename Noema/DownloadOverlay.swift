// DownloadOverlay.swift
import SwiftUI

struct DownloadOverlay: View {
    @EnvironmentObject var controller: DownloadController

    var body: some View {
        if controller.showOverlay {
            Button(action: { controller.openList() }) {
                ZStack {
                    Circle()
                        .fill(.thinMaterial)
                        .frame(width: 50, height: 50)
                        .applyGlassIfAvailable()
                    if controller.allCompleted {
                        Image(systemName: "checkmark")
                            .font(.title2)
                            .foregroundColor(.green)
                    } else {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .frame(width: 40, height: 40)
                            Circle()
                                .trim(from: 0, to: CGFloat(controller.overallProgress))
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 40, height: 40)
                            Text("\(Int(controller.overallProgress * 100))%")
                                .font(.caption2)
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .padding(.bottom, 12)
        }
    }
}

private extension View {
    @ViewBuilder
    func applyGlassIfAvailable() -> some View {
        #if os(visionOS)
        self.background(.regularMaterial, in: Circle())
        #else
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: Circle())
        } else {
            self
        }
        #endif
    }
}
