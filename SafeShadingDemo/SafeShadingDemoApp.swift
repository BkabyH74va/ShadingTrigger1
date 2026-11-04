import SwiftUI
import UIKit

@main
struct SafeShadingDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var pdfURL: URL?
    @State private var errorMessage: String?

    private let colors: [Color] = [
        Color(red: 0.10, green: 0.35, blue: 0.85),
        Color(red: 0.20, green: 0.75, blue: 0.65),
        Color(red: 0.95, green: 0.65, blue: 0.20)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Text("PDF Shading Demo")
                    .font(.largeTitle.bold())

                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 220)
                    .overlay {
                        Text("Valid Core Graphics gradient")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                    }

                Text("This demo draws a normal, bounded gradient and exports it as a standards-compliant PDF.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button {
                    exportPDF()
                } label: {
                    Label("Generate sample PDF", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Label("Share generated PDF", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Safe Demo")
        }
    }

    private func exportPDF() {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: page)

        do {
            let data = renderer.pdfData { context in
                context.beginPage()
                let cg = context.cgContext
                let rect = CGRect(x: 56, y: 180, width: 500, height: 300)

                let cgColors = [
                    UIColor(red: 0.10, green: 0.35, blue: 0.85, alpha: 1).cgColor,
                    UIColor(red: 0.20, green: 0.75, blue: 0.65, alpha: 1).cgColor,
                    UIColor(red: 0.95, green: 0.65, blue: 0.20, alpha: 1).cgColor
                ] as CFArray

                if let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: cgColors,
                    locations: [0.0, 0.5, 1.0]
                ) {
                    cg.saveGState()
                    cg.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 24).cgPath)
                    cg.clip()
                    cg.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: rect.minX, y: rect.minY),
                        end: CGPoint(x: rect.maxX, y: rect.maxY),
                        options: []
                    )
                    cg.restoreGState()
                }

                let title = "Safe PDF Shading Demo" as NSString
                title.draw(
                    at: CGPoint(x: 56, y: 90),
                    withAttributes: [
                        .font: UIFont.boldSystemFont(ofSize: 26),
                        .foregroundColor: UIColor.black
                    ]
                )

                let subtitle = "A valid, bounded Core Graphics gradient." as NSString
                subtitle.draw(
                    at: CGPoint(x: 56, y: 510),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 14),
                        .foregroundColor: UIColor.darkGray
                    ]
                )
            }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("SafeShadingDemo.pdf")
            try data.write(to: url, options: .atomic)
            pdfURL = url
            errorMessage = nil
        } catch {
            errorMessage = "PDF export failed: \(error.localizedDescription)"
        }
    }
}
