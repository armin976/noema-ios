// DatasetFileViewer.swift
import SwiftUI
import Foundation
#if canImport(PDFKit)
import PDFKit
#endif
import QuickLook

struct DatasetFileViewer: View {
    let url: URL
    @State private var content: String = ""
    @State private var error: String?
    @State private var isMarkdown = false
    private var isPDF: Bool { url.pathExtension.lowercased() == "pdf" }
    private var isEPUB: Bool { url.pathExtension.lowercased() == "epub" }

    var body: some View { contentView.navigationTitle(url.lastPathComponent) }

    @ViewBuilder
    private var contentView: some View {
        if isPDF {
            #if canImport(PDFKit)
            PDFViewer(url: url)
            #else
            Text("PDF viewing not supported on this platform")
            #endif
        } else if isEPUB {
            EPUBQuickLook(url: url)
        } else {
            ScrollView {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else if isMarkdown {
                    Text((try? AttributedString(markdown: content, options: .init(interpretedSyntax: .full))) ?? AttributedString(content))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                } else {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
            }
            .task { load() }
        }
    }

    private func load() {
        if isPDF || isEPUB { return }
        let ext = url.pathExtension.lowercased()
        guard let data = try? Data(contentsOf: url) else {
            error = "Unable to load file"
            return
        }
        switch ext {
        case "md":
            isMarkdown = true
            content = String(decoding: data, as: UTF8.self)
        case "json":
            if let obj = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
               let str = String(data: pretty, encoding: .utf8) {
                content = str
            } else {
                content = String(decoding: data, as: UTF8.self)
            }
        case "jsonl":
            let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map { line -> String in
                if let objData = line.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: objData),
                   let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
                   let str = String(data: pretty, encoding: .utf8) {
                    return str
                } else {
                    return String(line)
                }
            }
            content = lines.joined(separator: "\n\n")
        default:
            if let str = String(data: data, encoding: .utf8) {
                content = str
            } else {
                content = String(decoding: data, as: UTF8.self)
            }
        }
    }
}

#if canImport(PDFKit)
private struct PDFViewer: View {
    let url: URL
    var body: some View {
        #if canImport(UIKit)
        PDFKitRepresentable(url: url)
            .ignoresSafeArea(edges: .bottom)
        #elseif canImport(AppKit)
        PDFKitRepresentableMac(url: url)
            .ignoresSafeArea(edges: .bottom)
        #else
        Text("PDF viewing not supported on this platform")
        #endif
    }
}

#if canImport(UIKit)
private struct PDFKitRepresentable: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayDirection = .vertical
        v.displayMode = .singlePageContinuous
        v.document = PDFDocument(url: url)
        return v
    }
    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}
#elseif canImport(AppKit)
private struct PDFKitRepresentableMac: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayDirection = .vertical
        v.displayMode = .singlePageContinuous
        v.document = PDFDocument(url: url)
        return v
    }
    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}
#endif

// MARK: - EPUB Quick Look

private struct EPUBQuickLook: View {
    let url: URL
    var body: some View {
        #if canImport(UIKit)
        QLPreviewRepresentable(url: url)
            .ignoresSafeArea(edges: .bottom)
        #elseif canImport(AppKit)
        QLPreviewRepresentableMac(url: url)
            .ignoresSafeArea(edges: .bottom)
        #else
        Text("EPUB viewing not supported on this platform")
        #endif
    }
}

#if canImport(UIKit)
import UIKit
import QuickLook
private struct QLPreviewRepresentable: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return url as NSURL
        }
    }
}
#elseif canImport(AppKit)
import AppKit
import Quartz
private struct QLPreviewRepresentableMac: NSViewControllerRepresentable {
    let url: URL
    func makeNSViewController(context: Context) -> QLPreviewPanelHostController {
        return QLPreviewPanelHostController(url: url)
    }
    func updateNSViewController(_ nsViewController: QLPreviewPanelHostController, context: Context) {}
}

final class QLPreviewPanelHostController: NSViewController, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    let url: URL
    init(url: URL) { self.url = url; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidAppear() {
        super.viewDidAppear()
        if let panel = QLPreviewPanel.shared() {
            panel.dataSource = self
            panel.delegate = self
            panel.makeKeyAndOrderFront(nil)
        }
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem {
        return url as NSURL
    }
}
#endif
#endif
