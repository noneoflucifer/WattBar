import AppKit
import SwiftUI
import Combine
import Darwin
import Security

func appIsEnglish() -> Bool {
    let v = UserDefaults.standard.integer(forKey: "PWLanguage")
    switch v {
    case 2: return true
    case 1: return false
    default:
        return (Locale.preferredLanguages.first ?? "").hasPrefix("en")
    }
}

func L(_ zh: String, _ en: String) -> String { appIsEnglish() ? en : zh }
import ServiceManagement
import IOKit
import IOKit.ps

// MARK: - 主题

struct PWTheme {
    let name: String
    let bgTop: Color
    let bgBottom: Color
    let accent: Color
    let text: Color
    let sub: Color
    let warn: Color
    let isLight: Bool

    var accentDim: Color { accent.opacity(0.55) }

    static let all: [PWTheme] = [
        PWTheme(name: "黑金",
                bgTop: Color(red: 0.09, green: 0.09, blue: 0.10),
                bgBottom: Color(red: 0.15, green: 0.15, blue: 0.17),
                accent: Color(red: 0.90, green: 0.76, blue: 0.46),
                text: Color(red: 0.96, green: 0.94, blue: 0.90),
                sub: Color(red: 0.63, green: 0.61, blue: 0.57),
                warn: Color(red: 0.92, green: 0.66, blue: 0.36),
                isLight: false),
        PWTheme(name: "深蓝",
                bgTop: Color(red: 0.05, green: 0.09, blue: 0.16),
                bgBottom: Color(red: 0.09, green: 0.17, blue: 0.28),
                accent: Color(red: 0.47, green: 0.71, blue: 1.00),
                text: Color(red: 0.93, green: 0.96, blue: 1.00),
                sub: Color(red: 0.58, green: 0.66, blue: 0.78),
                warn: Color(red: 0.95, green: 0.66, blue: 0.35),
                isLight: false),
        PWTheme(name: "酒红",
                bgTop: Color(red: 0.16, green: 0.06, blue: 0.08),
                bgBottom: Color(red: 0.25, green: 0.10, blue: 0.14),
                accent: Color(red: 0.93, green: 0.63, blue: 0.55),
                text: Color(red: 1.00, green: 0.95, blue: 0.92),
                sub: Color(red: 0.75, green: 0.62, blue: 0.59),
                warn: Color(red: 0.96, green: 0.72, blue: 0.42),
                isLight: false),
        PWTheme(name: "森绿",
                bgTop: Color(red: 0.05, green: 0.12, blue: 0.09),
                bgBottom: Color(red: 0.09, green: 0.21, blue: 0.15),
                accent: Color(red: 0.62, green: 0.85, blue: 0.69),
                text: Color(red: 0.93, green: 0.98, blue: 0.94),
                sub: Color(red: 0.58, green: 0.70, blue: 0.63),
                warn: Color(red: 0.93, green: 0.72, blue: 0.42),
                isLight: false),
        PWTheme(name: "银白",
                bgTop: Color(red: 0.97, green: 0.97, blue: 0.98),
                bgBottom: Color(red: 0.90, green: 0.90, blue: 0.93),
                accent: Color(red: 0.60, green: 0.45, blue: 0.18),
                text: Color(red: 0.11, green: 0.11, blue: 0.12),
                sub: Color(red: 0.45, green: 0.45, blue: 0.48),
                warn: Color(red: 0.76, green: 0.45, blue: 0.10),
                isLight: true)
    ]
}

struct PWThemeKey: EnvironmentKey {
    static let defaultValue = PWTheme.all[0]
}

struct PWScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var pwTheme: PWTheme {
        get { self[PWThemeKey.self] }
        set { self[PWThemeKey.self] = newValue }
    }
    var uiScale: CGFloat {
        get { self[PWScaleKey.self] }
        set { self[PWScaleKey.self] = newValue }
    }
}

// MARK: - 数据模型

struct Snapshot {
    var inputW: Double = 0
    var inputV: Double = 0
    var inputA: Double = 0
    var loadW: Double = 0
    var batteryW: Double = 0
    var soc: Int = 0
    var isCharging = false
    var external = false
    var remainingMin: Int? = nil
    var fullMin: Int? = nil
    var adapterWatts = 0
    var adapterVmV = 0
    var adapterAmA = 0
    var adapterName: String? = nil
    var adapterSerial: String? = nil
    var adapterFW: String? = nil
    var adapterID: Int? = nil
    var adapterDesc: String? = nil
    var magsafeAuth: UInt32? = nil
    var magsafeAuthDesc: String? = nil
    var magsafePresent = false
    // 电池容量
    var designMAh: Double = 0
    var maxMAh: Double = 0
    var remainMAh: Double = 0
    var battV: Double = 0
}

struct ProcItem: Identifiable {
    let id: Int
    let name: String
    let value: Double
}

struct PowerSample: Codable, Identifiable {
    var t: Double
    var w: Double
    var b: Double
    var soc: Int
    var id: Double { t }
}

final class HistoryStore {
    static let shared = HistoryStore()
    private(set) var samples: [PowerSample] = []
    private let file: URL
    private let queue = DispatchQueue(label: "powerwatch.history")
    private var handle: FileHandle?
    private var migrated = false

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PowerWatch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("history.jsonl")
        let legacy = dir.appendingPathComponent("history.json")

        if let data = try? Data(contentsOf: file), !data.isEmpty,
           let text = String(data: data, encoding: .utf8) {
            samples = text.split(separator: "\n").compactMap { line in
                guard let d = line.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(PowerSample.self, from: d)
            }
        } else if let data = try? Data(contentsOf: legacy),
                  let arr = try? JSONDecoder().decode([PowerSample].self, from: data) {
            samples = arr
            migrated = true
        }
        if samples.count > 10080 {
            samples.removeFirst(samples.count - 10080)
            migrated = true
        }
        if migrated {
            let keep = samples
            queue.async { [weak self] in self?.rewrite(keep) }
        }
    }

    func append(_ s: PowerSample) {
        samples.append(s)
        if samples.count > 10080 { samples.removeFirst(samples.count - 10080) }
        guard let line = try? JSONEncoder().encode(s) else { return }
        queue.async { [weak self] in self?.write(line) }
    }

    private func write(_ line: Data) {
        if handle == nil {
            if !FileManager.default.fileExists(atPath: file.path) {
                FileManager.default.createFile(atPath: file.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: file)
            handle?.seekToEndOfFile()
        }
        handle?.write(line)
        handle?.write(Data([0x0A]))
    }

    private func rewrite(_ list: [PowerSample]) {
        handle?.closeFile()
        handle = nil
        var data = Data()
        let encoder = JSONEncoder()
        for s in list {
            if let line = try? encoder.encode(s) {
                data.append(line)
                data.append(0x0A)
            }
        }
        try? data.write(to: file, options: .atomic)
        handle = try? FileHandle(forWritingTo: file)
        handle?.seekToEndOfFile()
    }
}

struct Cand {
    let pid: Int
    let name: String
    let path: String
    let memMB: Double
    let cpu: Double
}

// MARK: - 电源读取

final class PowerReader {
    private var lastSlow = Date.distantPast
    private let queue = DispatchQueue(label: "powerwatch.slow")
    private(set) var cachedAuth: UInt32? = nil
    private(set) var cachedAuthDesc: String? = nil
    private(set) var cachedPortPresent = false

    func run(_ path: String, _ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return data
    }

    func runStatus(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    private func s64(_ any: Any?) -> Int64 {
        guard let n = any as? NSNumber else {
            if let i = any as? Int { return Int64(i) }
            return 0
        }
        return Int64(bitPattern: n.uint64Value)
    }

    private func batteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        let kr = IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
        guard kr == KERN_SUCCESS, let cf = props?.takeRetainedValue() else { return nil }
        return cf as? [String: Any]
    }

    func read() -> Snapshot? {
        guard let d = batteryProperties() else { return nil }

        var s = Snapshot()
        if let t = d["PowerTelemetryData"] as? [String: Any] {
            s.inputW = Double(s64(t["SystemPowerIn"])) / 1000.0
            s.inputV = Double(s64(t["SystemVoltageIn"])) / 1000.0
            s.inputA = Double(s64(t["SystemCurrentIn"])) / 1000.0
            s.loadW = Double(s64(t["SystemLoad"])) / 1000.0
            s.batteryW = Double(s64(t["BatteryPower"])) / 1000.0
        }
        if let b = d["BatteryData"] as? [String: Any] {
            s.soc = Int(s64(b["CurrentCapacity"]))
            s.designMAh = Double(s64(b["DesignCapacity"]))
            s.maxMAh = Double(s64(b["FullChargeCapacity"]))
            s.remainMAh = Double(s64(b["RemainingCapacity"]))
            let tte = Int(s64(b["AvgTimeToEmpty"]))
            if tte > 0 && tte < 65535 { s.remainingMin = tte }
        }
        if let v = d["Voltage"] as? NSNumber { s.battV = Double(v.intValue) / 1000.0 }
        if let a = d["AdapterDetails"] as? [String: Any], let w = a["Watts"] as? NSNumber, w.intValue > 0 {
            s.adapterWatts = w.intValue
            if let v = a["AdapterVoltage"] as? NSNumber { s.adapterVmV = v.intValue }
            if let c = a["Current"] as? NSNumber { s.adapterAmA = c.intValue }
            s.adapterName = a["Name"] as? String
            s.adapterSerial = a["SerialString"] as? String
            s.adapterFW = a["FwVersion"] as? String
            s.adapterDesc = a["Description"] as? String
            if let id = a["AdapterID"] as? NSNumber { s.adapterID = id.intValue }
        }
        s.isCharging = (d["IsCharging"] as? Bool) ?? ((d["IsCharging"] as? NSNumber)?.boolValue ?? false)
        s.external = (d["ExternalConnected"] as? Bool) ?? ((d["ExternalConnected"] as? NSNumber)?.boolValue ?? false)
        let ttf = Int(s64(d["AvgTimeToFull"]))
        if ttf > 0 && ttf < 65535 { s.fullMin = ttf }
        if s.fullMin == nil && s.isCharging {
            let tr = Int(s64(d["TimeRemaining"]))
            if tr > 0 && tr < 65535 { s.fullMin = tr }
        }
        s.magsafeAuth = cachedAuth
        s.magsafeAuthDesc = cachedAuthDesc
        s.magsafePresent = cachedPortPresent
        refreshSlowIfNeeded()
        return s
    }

    private func refreshSlowIfNeeded() {
        guard Date().timeIntervalSince(lastSlow) > 30 else { return }
        lastSlow = Date()
        queue.async {
            var auth: UInt32? = nil
            var desc: String? = nil
            var present = false

            if let d = self.run("/usr/sbin/ioreg", ["-c", "AppleTCControllerType11", "-r", "-l", "-w0"]),
               let txt = String(data: d, encoding: .utf8), txt.contains("Port-MagSafe 3") {
                present = true
                if let re = try? NSRegularExpression(pattern: #""AuthenticationStatusDescription" = "([^"]+)""#),
                   let m = re.firstMatch(in: txt, range: NSRange(txt.startIndex..., in: txt)),
                   m.numberOfRanges > 1,
                   let rr = Range(m.range(at: 1), in: txt) {
                    desc = String(txt[rr])
                }
            }
            if let d = self.run("/usr/sbin/ioreg", ["-l", "-w0"]),
               let txt = String(data: d, encoding: .utf8),
               let r = txt.range(of: #""magsafe-auth" = <([0-9a-fA-F]+)>"#, options: .regularExpression) {
                let line = String(txt[r])
                if let lt = line.firstIndex(of: "<"), let gt = line.firstIndex(of: ">") {
                    let hex = String(line[line.index(after: lt)..<gt])
                    let bytes = stride(from: 0, to: hex.count, by: 2).compactMap { i -> UInt8? in
                        let s = hex.index(hex.startIndex, offsetBy: i)
                        let e = hex.index(s, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
                        return UInt8(hex[s..<e], radix: 16)
                    }
                    if bytes.count >= 4 {
                        auth = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
                    } else if !bytes.isEmpty {
                        auth = UInt32(bytes[0])
                    }
                }
            }
            DispatchQueue.main.async {
                self.cachedAuth = auth
                self.cachedAuthDesc = desc
                self.cachedPortPresent = present
            }
        }
    }
}

// MARK: - CPU / 内存

final class SystemMeter {
    private var prev: [UInt32] = []

    func cpuPercent() -> Double {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info = info else { return 0 }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let stride = Int(CPU_STATE_MAX)
        var cur: [UInt32] = []
        cur.reserveCapacity(Int(cpuCount) * stride)
        var busy = 0.0
        var total = 0.0
        let hasPrev = prev.count == Int(cpuCount) * stride
        for i in 0..<Int(cpuCount) {
            let b = i * stride
            let u = UInt32(bitPattern: info[b + Int(CPU_STATE_USER)])
            let s = UInt32(bitPattern: info[b + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(bitPattern: info[b + Int(CPU_STATE_IDLE)])
            let nice = UInt32(bitPattern: info[b + Int(CPU_STATE_NICE)])
            if hasPrev {
                let du = Double(u &- prev[b])
                let ds = Double(s &- prev[b + 1])
                let di = Double(idle &- prev[b + 2])
                let dn = Double(nice &- prev[b + 3])
                busy += du + ds + dn
                total += du + ds + dn + di
            }
            cur.append(contentsOf: [u, s, idle, nice])
        }
        prev = cur
        guard hasPrev, total > 0 else { return 0 }
        return min(100, max(0, busy / total * 100))
    }

    func memory() -> (usedGB: Double, totalGB: Double, percent: Double, reclaimGB: Double) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        guard kr == KERN_SUCCESS else { return (0, totalBytes / 1073741824.0, 0, 0) }
        let page = Double(vm_kernel_page_size)
        let usedBytes = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        let reclaimBytes = (Double(stats.inactive_count) + Double(stats.purgeable_count) + Double(stats.speculative_count)) * page
        return (usedBytes / 1073741824.0, totalBytes / 1073741824.0,
                usedBytes / totalBytes * 100, reclaimBytes / 1073741824.0)
    }
}

// MARK: - 进程采样

final class ProcessSampler {
    private let queue = DispatchQueue(label: "powerwatch.proc")
    private var busy = false
    private let reader = PowerReader()

    func sample(tab: Int, completion: @escaping ([ProcItem]) -> Void) {
        if busy { return }
        busy = true
        queue.async {
            let items: [ProcItem]
            switch tab {
            case 1: items = self.parseTop(metric: "cpu")
            case 2: items = self.topMemory()
            default: items = self.parseTop(metric: "power")
            }
            self.busy = false
            DispatchQueue.main.async { completion(items) }
        }
    }

    private func name(_ comm: String) -> String {
        let n = (comm as NSString).lastPathComponent
        return n.isEmpty ? comm : n
    }

    private func aggregate(_ raw: [(Int, String, Double)]) -> [ProcItem] {
        var sums: [String: Double] = [:]
        for (_, n, v) in raw {
            if n == "PowerWatch" || n == "ps" || n == "top" || n.hasPrefix("top") { continue }
            sums[n, default: 0] += v
        }
        return sums.map { ProcItem(id: abs($0.key.hashValue), name: $0.key, value: $0.value) }
            .sorted { $0.value > $1.value }
    }

    private func parseTop(metric: String) -> [ProcItem] {
        guard let d = reader.run("/usr/bin/top", ["-l", "2", "-s", "1", "-stats", "pid,command,\(metric)",
                                                   "-o", metric, "-n", "12"]),
              let txt = String(data: d, encoding: .utf8) else { return [] }
        let lines = txt.split(separator: "\n")
        guard let header = lines.lastIndex(where: { $0.hasPrefix("PID") }) else { return [] }
        var raw: [(Int, String, Double)] = []
        for line in lines[(header + 1)...] {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3, let pid = Int(parts[0]), let last = parts.last, let v = Double(last) else { continue }
            let comm = parts[1..<(parts.count - 1)].joined(separator: " ").trimmingCharacters(in: .whitespaces)
            raw.append((pid, name(comm), v))
        }
        return Array(aggregate(raw).prefix(8))
    }

    private func topMemory() -> [ProcItem] {
        guard let d = reader.run("/bin/ps", ["-axo", "pid,pcpu,rss,comm", "-m"]),
              let txt = String(data: d, encoding: .utf8) else { return [] }
        var raw: [(Int, String, Double)] = []
        for line in txt.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4, let pid = Int(parts[0]), let _ = Double(parts[1]), let rss = Double(parts[2]) else { continue }
            raw.append((pid, name(parts[3...].joined(separator: " ")), rss / 1048576.0))
        }
        return Array(aggregate(raw).prefix(8))
    }
}

// MARK: - 配置存储

enum ConfigStore {
    private static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PowerWatch", isDirectory: true)
    }
    private static var file: URL { dir.appendingPathComponent("config.json") }

    static func saveKey(_ key: String) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var cfg: [String: String] = [:]
        if let d = try? Data(contentsOf: file),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: String] {
            cfg = obj
        }
        cfg["key"] = obfuscate(key)
        if let data = try? JSONSerialization.data(withJSONObject: cfg) {
            try? data.write(to: file, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    static func loadKey() -> String {
        guard let d = try? Data(contentsOf: file),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: String],
              let enc = obj["key"] else { return "" }
        return obfuscate(enc)
    }

    private static func obfuscate(_ s: String) -> String {
        guard !s.isEmpty else { return "" }
        if let data = Data(base64Encoded: s) {
            let decoded = data.map { $0 ^ 0x5A }
            if let str = String(data: Data(decoded), encoding: .utf8) { return str }
        }
        let bytes = s.utf8.map { $0 ^ 0x5A }
        return Data(bytes).base64EncodedString()
    }
}

// MARK: - DeepSeek

struct APIConfig {
    var base: String
    var model: String
    var key: String
}

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class DeepSeekClient {
    func chat(config: APIConfig, system: String, user: String, maxTokens: Int = 400,
              completion: @escaping (Result<String, Error>) -> Void) {
        var base = config.base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            completion(.failure(APIError(message: "接口地址为空")))
            return
        }
        if base.hasSuffix("/") { base.removeLast() }
        if !base.hasSuffix("/chat/completions") { base += "/chat/completions" }
        guard let url = URL(string: base) else {
            completion(.failure(APIError(message: "接口地址无效")))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.key)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": config.model,
            "messages": [["role": "system", "content": system],
                         ["role": "user", "content": user]],
            "temperature": 0.2,
            "max_tokens": maxTokens
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err {
                DispatchQueue.main.async { completion(.failure(err)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(APIError(message: "无响应"))) }
                return
            }
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let msg = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async { completion(.failure(APIError(message: "HTTP \(http.statusCode): \(msg.prefix(160))"))) }
                return
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let msg = choices.first?["message"] as? [String: Any],
                  let content = msg["content"] as? String else {
                DispatchQueue.main.async { completion(.failure(APIError(message: "返回格式异常"))) }
                return
            }
            DispatchQueue.main.async { completion(.success(content)) }
        }.resume()
    }
}

// MARK: - AI 清理

final class AICleaner {
    private let runner = PowerReader()
    private let meter = SystemMeter()
    private let client = DeepSeekClient()

    private let protectedNames: Set<String> = [
        "WindowServer", "kernel_task", "launchd", "loginwindow", "Finder", "Dock",
        "SystemUIServer", "ControlCenter", "NotificationCenter", "coreaudiod", "cfprefsd",
        "distnoted", "securityd", "tccd", "powerd", "configd", "mds", "mds_stores",
        "mdsync", "Spotlight", "secd", "apsd", "bluetoothd", "sharingd", "rapportd",
        "identityservicesd", "nsurlsessiond", "cloudd", "bird", "fileproviderd",
        "UserEventAgent", "watchdogd", "logd", "syslogd", "opendirectoryd", "diskarbitrationd",
        "PowerWatch"
    ]

    func clean(config: APIConfig, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let before = self.meter.memory()
            let cands = self.candidates()
            guard !cands.isEmpty else {
                DispatchQueue.main.async { completion(.success("没有可清理的候选进程")) }
                return
            }
            let list = cands.map {
                "\($0.name) | \($0.path) | \(String(format: "%.0f", $0.memMB))MB | \(String(format: "%.1f", $0.cpu))%"
            }.joined(separator: "\n")

            let system = """
            你是 macOS 内存管理专家。根据进程列表,挑选可以安全终止的后台辅助进程来释放内存。
            硬性规则:
            1. 绝不能选择用户正在使用的 GUI 应用(浏览器、微信、聊天工具、编辑器、终端、任何 .app 主进程)。
            2. 绝不能选择系统关键进程(WindowServer、kernel_task、launchd、Finder、Dock、loginwindow、coreaudiod、cfprefsd、mds_stores 等)。
            3. 只能选择可自动重启、不承载用户数据的后台守护/辅助进程(例如照片分析、Spotlight 索引 worker、Siri 知识库、建议服务、缩略图代理等)。
            4. 最多选择 8 个,优先内存占用大的;拿不准就不要选。
            只输出 JSON,不要任何其他文字:{"kill":["进程名",...],"reason":"不超过40字的中文说明"}
            """
            let user = "进程列表(name | path | 内存 | CPU):\n" + list
            self.client.chat(config: config, system: system, user: user, maxTokens: 3000) { result in
                switch result {
                case .failure(let err):
                    completion(.failure(err))
                case .success(let content):
                    let parsed = self.parse(content)
                    DispatchQueue.global(qos: .userInitiated).async {
                        let killed = self.kill(names: parsed.kill, cands: cands)
                        Thread.sleep(forTimeInterval: 2.0)
                        let after = self.meter.memory()
                        let freed = max(0, (before.usedGB - after.usedGB) * 1024)
                        var msg: String
                        if killed == 0 {
                            msg = L("AI 判断无需清理", "AI found nothing to clean")
                        } else {
                            msg = L(String(format: "AI 清理 %d 个进程 · 释放约 %.0f MB", killed, freed), String(format: "AI cleaned %d processes · freed ~%.0f MB", killed, freed))
                        }
                        if !parsed.reason.isEmpty { msg += " · \(parsed.reason)" }
                        DispatchQueue.main.async { completion(.success(msg)) }
                    }
                }
            }
        }
    }

    private func candidates() -> [Cand] {
        guard let d = runner.run("/bin/ps", ["-axo", "pid,uid,pcpu,rss,comm", "-m"]),
              let txt = String(data: d, encoding: .utf8) else { return [] }
        let uid = getuid()
        var out: [Cand] = []
        for line in txt.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 5,
                  let pid = Int(parts[0]),
                  let puid = UInt32(parts[1]), puid == uid,
                  let cpu = Double(parts[2]),
                  let rss = Double(parts[3]) else { continue }
            let path = parts[4...].joined(separator: " ")
            if path.contains("/Applications/") || path.contains("/System/Applications/") { continue }
            let name = (path as NSString).lastPathComponent
            if protectedNames.contains(name) { continue }
            guard rss > 25000 else { continue }
            out.append(Cand(pid: pid, name: name, path: path, memMB: rss / 1024.0, cpu: cpu))
            if out.count >= 30 { break }
        }
        return out
    }

    private func parse(_ content: String) -> (kill: [String], reason: String) {
        var t = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = t.range(of: "{"), let e = t.range(of: "}", options: .backwards) {
            t = String(t[s.lowerBound..<e.upperBound])
        }
        guard let data = t.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], "")
        }
        let kill = (obj["kill"] as? [String]) ?? []
        let reason = (obj["reason"] as? String) ?? ""
        return (kill, reason)
    }

    private func kill(names: [String], cands: [Cand]) -> Int {
        var killed = 0
        for name in names.prefix(8) {
            for c in cands where c.name == name {
                if runner.runStatus("/bin/kill", ["-15", "\(c.pid)"]) == 0 { killed += 1 }
            }
        }
        return killed
    }
}

// MARK: - SwiftUI 模型

final class PowerModel: ObservableObject {
    @Published var snap = Snapshot()
    @Published var age = 0
    @Published var tab: Int {
        didSet { UserDefaults.standard.set(tab, forKey: "PowerWatchTab") }
    }
    @Published var cpuPct: Double = 0
    @Published var memPct: Double = 0
    @Published var memUsed: Double = 0
    @Published var memTotal: Double = 0
    @Published var memReclaim: Double = 0
    @Published var cpuList: [ProcItem] = []
    @Published var memList: [ProcItem] = []
    @Published var powerList: [ProcItem] = []

    @Published var aiBase: String
    @Published var aiModel: String
    @Published var aiKey: String
    @Published var history: [PowerSample] = []
    @Published var chartHours: Int = 6
    @Published var themeIndex: Int {
        didSet { UserDefaults.standard.set(themeIndex, forKey: "PWTheme") }
    }
    @Published var fontLevel: Int {
        didSet { UserDefaults.standard.set(fontLevel, forKey: "PWFont") }
    }
    @Published var language: Int {
        didSet { UserDefaults.standard.set(language, forKey: "PWLanguage") }
    }
    @Published var aiStatus: String = L("未配置", "Not configured")
    @Published var aiCleaning = false
    @Published var aiResult: String? = nil
    @Published var launchAtLogin = false
    @Published var loginMessage: String? = nil

    var onCopy: () -> Void = {}
    var onQuit: () -> Void = {}
    var onTabChange: (Int) -> Void = { _ in }
    var onAIClean: () -> Void = {}
    var onSaveConfig: () -> Void = {}
    var onTestConfig: () -> Void = {}
    var onToggleLaunchAtLogin: () -> Void = {}

    init() {
        let saved = UserDefaults.standard.integer(forKey: "PowerWatchTab")
        tab = (0...5).contains(saved) ? saved : 0
        aiBase = UserDefaults.standard.string(forKey: "AIBase") ?? "https://api.deepseek.com/v1"
        var savedModel = UserDefaults.standard.string(forKey: "AIModel") ?? "deepseek-flash"
        if savedModel == "deepseek-v4.1-flash" { savedModel = "deepseek-flash" }
        aiModel = savedModel
        aiKey = ConfigStore.loadKey()
        history = HistoryStore.shared.samples
        let savedTheme = UserDefaults.standard.integer(forKey: "PWTheme")
        themeIndex = (0..<PWTheme.all.count).contains(savedTheme) ? savedTheme : 0
        let savedFont = UserDefaults.standard.integer(forKey: "PWFont")
        fontLevel = (1...4).contains(savedFont) ? savedFont : 2
        let savedLang = UserDefaults.standard.integer(forKey: "PWLanguage")
        language = (0...2).contains(savedLang) ? savedLang : 0
    }
}

// MARK: - SwiftUI 视图

private let gold = Color(red: 0.90, green: 0.76, blue: 0.46)
private let goldDim = Color(red: 0.90, green: 0.76, blue: 0.46).opacity(0.55)
private let ivory = Color(red: 0.96, green: 0.94, blue: 0.90)
private let warmGray = Color(red: 0.63, green: 0.61, blue: 0.57)
private let amber = Color(red: 0.92, green: 0.66, blue: 0.36)

struct GoldChip: View {
    @Environment(\.pwTheme) private var th
    @Environment(\.uiScale) private var sc
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 9.5 * sc, weight: .medium))
            .foregroundStyle(th.accent)
            .padding(.horizontal, 7 * sc)
            .padding(.vertical, 2.5 * sc)
            .overlay(Capsule().stroke(th.accentDim, lineWidth: 0.8))
    }
}

struct InfoRow: View {
    @Environment(\.pwTheme) private var th
    @Environment(\.uiScale) private var sc
    let label: String
    let value: String
    var color: Color? = nil
    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 10.5 * sc))
                .foregroundStyle(th.sub)
                .frame(width: (appIsEnglish() ? 100 : 78) * sc, alignment: .leading)
            Text(value)
                .font(.system(size: 12 * sc, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color ?? th.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .frame(height: 17 * sc)
    }
}

struct ProcRow: View {
    @Environment(\.pwTheme) private var th
    @Environment(\.uiScale) private var sc
    let name: String
    let value: String
    var body: some View {
        HStack(spacing: 6 * sc) {
            Text(name)
                .font(.system(size: 10.5 * sc))
                .foregroundStyle(th.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 10.5 * sc, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(th.accent)
        }
        .frame(height: 16 * sc)
    }
}

struct HairLine: View {
    @Environment(\.pwTheme) private var th
    var body: some View {
        Rectangle()
            .fill(th.accent.opacity(0.16))
            .frame(height: 0.5)
    }
}

struct RatioBar: View {
    @Environment(\.pwTheme) private var th
    @Environment(\.uiScale) private var sc
    let ratio: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(th.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.07))
                Capsule()
                    .fill(LinearGradient(colors: [th.accent.opacity(0.55), th.accent.opacity(0.95)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(3, geo.size.width * min(1, max(0, ratio))))
            }
        }
        .frame(height: 3 * sc)
    }
}

struct PowerChartView: View {
    @Environment(\.pwTheme) private var th
    @Environment(\.uiScale) private var sc
    let points: [PowerSample]
    let hours: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let now = Date().timeIntervalSince1970
            let start = now - Double(hours) * 3600
            let visible = points.filter { $0.t >= start }.sorted { $0.t < $1.t }
            let vals = visible.flatMap { [$0.w, $0.b] }
            let maxV = max(60.0, (vals.max() ?? 0) * 1.15)
            let minV = min(0.0, (visible.map { $0.b }.min() ?? 0) * 1.15)
            let span = max(1.0, maxV - minV)
            let inset: CGFloat = 28 * sc
            let plotW = max(1, w - inset)
            let x: (Double) -> CGFloat = { t in inset + plotW * CGFloat((t - start) / max(1, now - start)) }
            let y: (Double) -> CGFloat = { v in h - h * CGFloat((v - minV) / span) }
            let zeroY = y(0)
            let ticks: [Double] = {
                var a = [0.0, maxV, maxV / 2]
                if minV < -1 { a.append(minV) }
                return a.sorted()
            }()
            let gridColor = th.isLight ? Color.black.opacity(0.07) : Color.white.opacity(0.07)
            let zeroColor = th.isLight ? Color.black.opacity(0.14) : Color.white.opacity(0.14)

            ZStack(alignment: .topLeading) {
                ForEach(ticks, id: \.self) { v in
                    Path { p in
                        p.move(to: CGPoint(x: inset, y: y(v)))
                        p.addLine(to: CGPoint(x: w, y: y(v)))
                    }
                    .stroke(abs(v) < 0.5 ? zeroColor : gridColor, lineWidth: 0.5)
                    Text(String(format: "%.0f", v))
                        .font(.system(size: 7.5 * sc))
                        .foregroundStyle(th.sub.opacity(0.8))
                        .frame(width: max(1, inset - 4 * sc), alignment: .trailing)
                        .position(x: max(1, inset - 4 * sc) / 2, y: min(max(y(v), 6 * sc), h - 6 * sc))
                }
                if visible.count >= 2 {
                    let wpts: [CGPoint] = visible.map { CGPoint(x: x($0.t), y: y($0.w)) }
                    let bpts: [CGPoint] = visible.map { CGPoint(x: x($0.t), y: y($0.b)) }
                    Path { p in
                        p.move(to: CGPoint(x: wpts[0].x, y: zeroY))
                        for pt in wpts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: wpts.last!.x, y: zeroY))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [th.accent.opacity(0.22), th.accent.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: wpts[0])
                        for pt in wpts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(th.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    Path { p in
                        p.move(to: bpts[0])
                        for pt in bpts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(th.warn, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                } else {
                    Text(L("正在记录… 每分钟一个点", "Recording… one point per minute"))
                        .font(.system(size: 9 * sc))
                        .foregroundStyle(th.sub)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(height: 108 * sc)
    }
}

struct PowerCard: View {
    @ObservedObject var model: PowerModel
    private var tabs: [String] {
        [L("电源", "Power"), "CPU", L("内存", "Mem"), "AI", L("曲线", "Curve"), L("外观", "Theme")]
    }

    private var th: PWTheme { PWTheme.all[min(model.themeIndex, PWTheme.all.count - 1)] }
    private var sc: CGFloat {
        let base: [CGFloat] = [0.88, 1.0, 1.12, 1.26]
        return base[min(max(model.fontLevel - 1, 0), 3)]
    }
    private func fs(_ x: CGFloat) -> CGFloat { x * sc }
    private var segFill: Color { th.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.09) }
    private var segBG: Color { th.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.04) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * sc) {
            header
            segmented
            Group {
                if model.tab == 0 { powerTab }
                else if model.tab == 1 { cpuTab }
                else if model.tab == 2 { memTab }
                else if model.tab == 3 { aiTab }
                else if model.tab == 4 { chartTab }
                else { appearanceTab }
            }
            footer
        }
        .padding(16 * sc)
        .frame(width: 300 * sc)
        .background(
            ZStack {
                LinearGradient(colors: [th.bgTop, th.bgBottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [th.isLight ? Color.black.opacity(0.03) : Color.white.opacity(0.045), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 220)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [th.accent.opacity(0.55), th.accent.opacity(0.12), th.accent.opacity(0.42)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
        )
        .environment(\.colorScheme, th.isLight ? .light : .dark)
        .environment(\.pwTheme, th)
        .environment(\.uiScale, sc)
    }

    private var header: some View {
        let s = model.snap
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 5) {
                Image(systemName: s.inputW > 1 ? "bolt.fill" : "battery.75")
                    .font(.system(size: fs(14), weight: .semibold))
                    .foregroundStyle(th.accent)
                    .frame(width: 17)
                Text(String(format: "%.1f", s.inputW > 1 ? s.inputW : abs(s.batteryW)))
                    .font(.system(size: fs(27), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(th.text)
                Text("W")
                    .font(.system(size: fs(12), weight: .medium))
                    .foregroundStyle(th.sub)
                Spacer(minLength: 4)
                if s.adapterWatts > 0 && s.inputW > 1 { GoldChip(text: L("\(s.adapterWatts) W 档", "\(s.adapterWatts) W")) }
            }
            HStack(spacing: 10) {
                Text(s.inputW > 1 ? L("输入功率 · 进入 Mac", "Input power") : L("电池放电", "On battery"))
                    .font(.system(size: fs(9.5)))
                    .foregroundStyle(th.sub)
                Text("CPU \(String(format: "%.0f", model.cpuPct))%")
                    .font(.system(size: fs(9.5), weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(th.text)
                Text(L("内存", "MEM") + " \(String(format: "%.0f", model.memPct))%")
                    .font(.system(size: fs(9.5), weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(th.text)
            }
        }
    }

    private var segmented: some View {
        HStack(spacing: 3) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { idx, name in
                Button(action: {
                    model.tab = idx
                    model.onTabChange(idx)
                }) {
                    Text(name)
                        .font(.system(size: fs(10.5), weight: .medium))
                        .foregroundStyle(model.tab == idx ? th.accent : th.sub)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4 * sc)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(model.tab == idx ? segFill : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3 * sc)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(segBG))
    }

    // 电源页
    private var powerTab: some View {
        let s = model.snap
        let identified = s.adapterName != nil || s.adapterSerial != nil
        return VStack(alignment: .leading, spacing: 3 * sc) {
            InfoRow(label: L("电压 × 电流", "Voltage × Current"),
                    value: (s.inputV > 0.1 || s.inputA > 0.01)
                        ? String(format: "%.2f V × %.2f A", s.inputV, s.inputA) : "—",
                    color: s.inputV > 0.1 ? th.text : th.sub)
            InfoRow(label: L("电池", "Battery"),
                    value: s.batteryW >= 0 ? String(format: "+%.1f W", s.batteryW) : String(format: "%.1f W", s.batteryW),
                    color: s.batteryW >= 0 ? th.accent : th.warn)
            InfoRow(label: L("电池容量", "Capacity"), value: capacityText(s), color: th.text)
            InfoRow(label: L("系统负载", "System load"), value: String(format: "%.1f W", s.loadW))
            HairLine().padding(.vertical, 1)

            InfoRow(label: L("充电器", "Charger"),
                    value: s.adapterWatts > 0 ? (s.adapterName ?? L("未识别（\(s.adapterDesc ?? "PD")）", "Unrecognized (\(s.adapterDesc ?? "PD"))")) : L("未接电源", "No power"),
                    color: s.adapterWatts > 0 ? (identified ? th.text : th.warn) : th.sub)
            InfoRow(label: "PD",
                    value: s.adapterWatts > 0
                        ? String(format: "%d V × %.2f A · %d W", s.adapterVmV / 1000, Double(s.adapterAmA) / 1000.0, s.adapterWatts)
                        : "—",
                    color: s.adapterWatts > 0 ? th.text : th.sub)
            InfoRow(label: L("认证", "Auth"),
                    value: s.adapterWatts > 0 ? (identified ? L("✅ 原装已识别", "✅ Genuine adapter") : L("⚠️ 未识别（第三方/改装）", "⚠️ Unrecognized (3rd-party)")) : "—",
                    color: s.adapterWatts > 0 ? (identified ? th.accent : th.warn) : th.sub)
            InfoRow(label: L("身份", "Identity"), value: identLine(s), color: s.adapterWatts > 0 ? th.text : th.sub)
            HairLine().padding(.vertical, 1)

            HStack {
                Text(L("耗电应用", "Energy apps"))
                    .font(.system(size: fs(10)))
                    .foregroundStyle(th.sub)
                Spacer()
                Text(L("能源影响", "Impact"))
                    .font(.system(size: fs(9)))
                    .foregroundStyle(th.sub.opacity(0.7))
            }
            if model.powerList.isEmpty {
                Text(L("采样中…", "Sampling…"))
                    .font(.system(size: fs(10)))
                    .foregroundStyle(th.sub)
                    .frame(height: 16)
            } else {
                ForEach(Array(model.powerList.prefix(3))) { p in
                    ProcRow(name: p.name, value: String(format: "%.1f", p.value))
                }
            }
        }
    }

    // CPU 页
    private var cpuTab: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("总 CPU 占用", "Total CPU"))
                    .font(.system(size: fs(10)))
                    .foregroundStyle(th.sub)
                Spacer()
                Text(String(format: "%.1f%%", model.cpuPct))
                    .font(.system(size: fs(19), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(th.accent)
            }
            RatioBar(ratio: model.cpuPct / 100)
            HStack {
                Text(L("进程", "Process"))
                    .font(.system(size: fs(10)))
                    .foregroundStyle(th.sub)
                Spacer()
                Text(L("CPU（单核）", "CPU (per-core)"))
                    .font(.system(size: fs(9)))
                    .foregroundStyle(th.sub.opacity(0.7))
            }
            .padding(.top, 2)
            if model.cpuList.isEmpty {
                Text(L("采样中…", "Sampling…")).font(.system(size: fs(10))).foregroundStyle(th.sub).frame(height: 16)
            } else {
                ForEach(Array(model.cpuList.prefix(6))) { p in
                    ProcRow(name: p.name, value: String(format: "%.1f%%", p.value))
                }
            }
        }
    }

    // 内存页
    private var memTab: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("内存占用", "Memory usage"))
                    .font(.system(size: fs(10)))
                    .foregroundStyle(th.sub)
                Spacer()
                Text(String(format: "%.1f%%", model.memPct))
                    .font(.system(size: fs(19), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(th.accent)
            }
            HStack {
                Text(String(format: "%.1f / %.1f GB", model.memUsed, model.memTotal))
                    .font(.system(size: fs(10), weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(th.text)
                Spacer()
                Text(L(String(format: "可回收 %.1f GB", model.memReclaim), String(format: "Reclaimable %.1f GB", model.memReclaim)))
                    .font(.system(size: fs(9), design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(th.sub)
            }
            RatioBar(ratio: model.memPct / 100)
            if let r = model.aiResult {
                Text(r)
                    .font(.system(size: fs(9)))
                    .foregroundStyle(th.accent.opacity(0.9))
                    .lineLimit(2)
            }
            HStack {
                Text(L("进程", "Process"))
                    .font(.system(size: fs(10)))
                    .foregroundStyle(th.sub)
                Spacer()
                Text(L("内存", "Memory"))
                    .font(.system(size: fs(9)))
                    .foregroundStyle(th.sub.opacity(0.7))
            }
            .padding(.top, 2)
            if model.memList.isEmpty {
                Text(L("采样中…", "Sampling…")).font(.system(size: fs(10))).foregroundStyle(th.sub).frame(height: 16)
            } else {
                ForEach(Array(model.memList.prefix(6))) { p in
                    ProcRow(name: p.name, value: String(format: "%.2f GB", p.value))
                }
            }
        }
    }

    // AI 设置页
    private var aiTab: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(L("AI 清理设置", "AI cleanup settings"))
                    .font(.system(size: fs(10)))
                    .foregroundStyle(th.sub)
                Spacer()
                Text(model.aiStatus)
                    .font(.system(size: fs(9)))
                    .foregroundStyle((model.aiStatus.contains("失败") || model.aiStatus.contains("Failed")) ? th.warn : th.accent.opacity(0.85))
                    .lineLimit(1)
            }
            configField(L("接口", "Endpoint"), text: $model.aiBase)
            configField(L("模型", "Model"), text: $model.aiModel)
            configField(L("密钥", "API key"), text: $model.aiKey, secure: true)
            HStack(spacing: 8) {
                smallButton(L("保存", "Save")) { model.onSaveConfig() }
                smallButton(L("测试连接", "Test")) { model.onTestConfig() }
                Spacer()
                Text(L("仅上传进程名与占用", "Names & usage only"))
                    .font(.system(size: fs(8.5)))
                    .foregroundStyle(th.sub.opacity(0.7))
            }
        }
    }

    // 曲线页
    private var chartTab: some View {
        let now = Date().timeIntervalSince1970
        let cutoff = now - Double(model.chartHours) * 3600
        let pts = model.history.filter { $0.t >= cutoff }
        let powerPts = pts.filter { $0.w > 1 }
        let maxW = powerPts.map { $0.w }.max() ?? 0
        let avgW = powerPts.isEmpty ? 0 : powerPts.map { $0.w }.reduce(0, +) / Double(powerPts.count)
        let currentW = model.snap.inputW
        let currentB = model.snap.batteryW
        let batteryText: String = currentB > 0.5
            ? L(String(format: "+%.1f W 电池", currentB), String(format: "+%.1f W battery", currentB))
            : (currentB < -0.5 ? L(String(format: "%.1f W 放电", currentB), String(format: "%.1f W discharging", currentB)) : L("0.0 W 电池", "0.0 W battery"))
        return VStack(alignment: .leading, spacing: 6 * sc) {
            HStack {
                Text(L("功率曲线", "Power curve"))
                    .font(.system(size: fs(10)))
                    .foregroundStyle(th.sub)
                Spacer()
                HStack(spacing: 3) {
                    ForEach([1, 6, 24], id: \.self) { h in
                        Button("\(h)h") { model.chartHours = h }
                            .buttonStyle(.plain)
                            .font(.system(size: fs(9), weight: .medium))
                            .foregroundStyle(model.chartHours == h ? th.accent : th.sub)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4)
                                .fill(model.chartHours == h ? segFill : Color.clear))
                            .contentShape(Rectangle())
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(String(format: "%.1f", currentW))
                    .font(.system(size: fs(19), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(th.accent)
                Text(L("W 输入", "W input"))
                    .font(.system(size: fs(9)))
                    .foregroundStyle(th.sub)
                Text(batteryText)
                    .font(.system(size: fs(9.5), weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(currentB > 0.5 ? th.accent.opacity(0.9) : (currentB < -0.5 ? th.warn : th.sub))
                Spacer()
            }
            HStack(spacing: 8) {
                Circle().fill(th.accent).frame(width: 5, height: 5)
                Text(L("输入", "Input")).font(.system(size: fs(8.5))).foregroundStyle(th.sub)
                Circle().fill(th.warn).frame(width: 5, height: 5)
                Text(L("电池", "Battery")).font(.system(size: fs(8.5))).foregroundStyle(th.sub)
                Spacer()
                Text(L("输入 平均 \(Int(avgW.rounded())) · 最高 \(Int(maxW.rounded())) W", "Input avg \(Int(avgW.rounded())) · max \(Int(maxW.rounded())) W"))
                    .font(.system(size: fs(8.5)))
                    .foregroundStyle(th.sub)
            }
            PowerChartView(points: model.history, hours: model.chartHours)
            HStack {
                Text(model.chartHours == 24 ? L("24 小时前", "24h ago") : L("\(model.chartHours) 小时前", "\(model.chartHours)h ago"))
                    .font(.system(size: fs(8.5)))
                    .foregroundStyle(th.sub.opacity(0.7))
                Spacer()
                Text(L("现在", "Now"))
                    .font(.system(size: fs(8.5)))
                    .foregroundStyle(th.sub.opacity(0.7))
            }
            Text(L("每分钟采样 · \(pts.count) 个点", "One sample/min · \(pts.count) points"))
                .font(.system(size: fs(8.5)))
                .foregroundStyle(th.sub.opacity(0.7))
        }
    }

    // 外观设置页
    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 8 * sc) {
            Text(L("主题", "Theme"))
                .font(.system(size: fs(10)))
                .foregroundStyle(th.sub)
            HStack(spacing: 5 * sc) {
                ForEach(0..<PWTheme.all.count, id: \.self) { i in
                    Button {
                        model.themeIndex = i
                    } label: {
                        VStack(spacing: 3 * sc) {
                            Circle()
                                .fill(PWTheme.all[i].accent)
                                .frame(width: 13 * sc, height: 13 * sc)
                                .overlay(
                                    Circle().stroke(PWTheme.all[i].isLight ? Color.black.opacity(0.25) : Color.white.opacity(0.35),
                                                    lineWidth: model.themeIndex == i ? 2 : 0.6)
                                )
                            Text(L(PWTheme.all[i].name, ["Black Gold", "Midnight", "Burgundy", "Forest", "Silver"][i]))
                                .font(.system(size: fs(8.5)))
                                .foregroundStyle(model.themeIndex == i ? th.accent : th.sub)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(L("字号", "Font size"))
                .font(.system(size: fs(10)))
                .foregroundStyle(th.sub)
                .padding(.top, 2 * sc)
            HStack(spacing: 3) {
                ForEach(1...4, id: \.self) { lv in
                    Button {
                        model.fontLevel = lv
                    } label: {
                        Text([L("小", "Small"), L("标准", "Standard"), L("大", "Large"), L("特大", "XL")][lv - 1])
                            .font(.system(size: fs(9.5)))
                            .foregroundStyle(model.fontLevel == lv ? th.accent : th.sub)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4 * sc)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(model.fontLevel == lv ? segFill : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3 * sc)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(segBG))

            Text(L("语言", "Language"))
                .font(.system(size: fs(10)))
                .foregroundStyle(th.sub)
                .padding(.top, 2 * sc)
            HStack(spacing: 3) {
                ForEach(0...2, id: \.self) { v in
                    Button {
                        model.language = v
                    } label: {
                        Text([L("跟随系统", "System"), "中文", "English"][v])
                            .font(.system(size: fs(9.5)))
                            .foregroundStyle(model.language == v ? th.accent : th.sub)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4 * sc)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(model.language == v ? segFill : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3 * sc)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(segBG))

            Text(L("面板尺寸随字号同步缩放", "Panel scales with font size"))
                .font(.system(size: fs(8.5)))
                .foregroundStyle(th.sub.opacity(0.7))
        }
    }

    private func configField(_ label: String, text: Binding<String>, secure: Bool = false) -> some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.system(size: fs(9)))
                .foregroundStyle(th.sub)
                .frame(width: 30, alignment: .leading)
            Group {
                if secure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: fs(10.5)))
            .foregroundStyle(th.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.06)))
        }
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: fs(10), weight: .medium))
                .foregroundStyle(th.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .overlay(Capsule().stroke(th.accentDim, lineWidth: 0.8))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HairLine()
            HStack(spacing: 0) {
                Text(stateText())
                    .font(.system(size: fs(10)))
                    .foregroundStyle(th.sub)
                Spacer()
                Text(L("\(model.age) 秒未变", "unchanged \(model.age)s"))
                    .font(.system(size: fs(9)))
                    .foregroundStyle(th.sub.opacity(0.65))
            }
            if let msg = model.loginMessage {
                Text(msg)
                    .font(.system(size: fs(8.5)))
                    .foregroundStyle(th.sub)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                if model.tab == 2 {
                    smallButton(model.aiCleaning ? L("AI 分析中…", "Analyzing…") : L("AI 清理", "AI Clean")) {
                        model.onAIClean()
                    }
                    .disabled(model.aiCleaning)
                }
                smallButton(model.launchAtLogin ? L("开机自启 ✓", "Startup ✓") : L("开机自启", "Startup")) {
                    model.onToggleLaunchAtLogin()
                }
                Button(L("复制诊断", "Copy info")) { model.onCopy() }
                    .buttonStyle(.plain)
                    .font(.system(size: fs(10.5), weight: .medium))
                    .foregroundStyle(th.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3.5)
                    .overlay(Capsule().stroke(th.accentDim, lineWidth: 0.8))
                    .contentShape(Capsule())
                Spacer()
                Button(L("退出", "Quit")) { model.onQuit() }
                    .buttonStyle(.plain)
                    .font(.system(size: fs(10.5)))
                    .foregroundStyle(th.sub)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
            }
        }
    }

    private func capacityText(_ s: Snapshot) -> String {
        guard s.maxMAh > 0, s.battV > 0 else { return "—" }
        let maxWh = s.maxMAh * s.battV / 1000.0
        let curWh = s.remainMAh * s.battV / 1000.0
        return L(String(format: "满 %.1f · 现 %.1f Wh", maxWh, curWh), String(format: "Full %.1f · Now %.1f Wh", maxWh, curWh))
    }

    private func identLine(_ s: Snapshot) -> String {
        guard s.adapterWatts > 0 else { return "—" }
        var t = ""
        if let sn = s.adapterSerial {
            t = "SN …\(String(sn.suffix(4)))"
            if let fw = s.adapterFW, let n = Int(fw) { t += " · FW \(n)" }
        } else {
            t = "ID " + (s.adapterID.map { String(format: "0x%04X", $0) } ?? "—")
        }
        if s.magsafePresent && !appIsEnglish() {
            var m = "MagSafe"
            if let a = s.magsafeAuth { m += " 0x\(String(a, radix: 16))" }
            t += " · \(m)"
        }
        return t
    }

    private func stateText() -> String {
        let s = model.snap
        var t = "\(s.soc)%"
        if s.isCharging { t += L(" · 充电中", " · charging") }
        else if s.external { t += s.soc >= 100 ? L(" · 已充满", " · full") : L(" · 未充电", " · not charging") }
        else { t += L(" · 放电中", " · discharging") }
        if s.isCharging, let m = s.fullMin {
            t += L(String(format: " · %d:%02d 后充满", m / 60, m % 60), String(format: " · %d:%02d to full", m / 60, m % 60))
        } else if let m = s.remainingMin {
            t += L(String(format: " · %d:%02d 后耗尽", m / 60, m % 60), String(format: " · %d:%02d left", m / 60, m % 60))
        }
        return t
    }
}

// MARK: - 面板

final class PowerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

final class PanelController {
    let panel = PowerPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 360),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
    let model = PowerModel()
    private var hosting: NSHostingView<PowerCard>!
    private var cancellables: Set<AnyCancellable> = []

    init() {
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: PWTheme.all[model.themeIndex].isLight ? .aqua : .darkAqua)
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        hosting = NSHostingView(rootView: PowerCard(model: model))
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)

        model.onCopy = { [weak self] in self?.copyDiag() }
        model.onQuit = { NSApp.terminate(nil) }

        model.$tab
            .removeDuplicates()
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &cancellables)

        Publishers.Merge(model.$themeIndex, model.$fontLevel)
            .dropFirst()
            .sink { [weak self] _ in
                guard let self = self else { return }
                let t = PWTheme.all[self.model.themeIndex]
                self.panel.appearance = NSAppearance(named: t.isLight ? .aqua : .darkAqua)
                self.relayout()
            }
            .store(in: &cancellables)
    }

    func relayout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.resize()
        }
    }

    private func resize() {
        hosting.layoutSubtreeIfNeeded()
        let fit = hosting.fittingSize
        guard fit.height > 100 else { return }
        let old = panel.frame
        guard abs(fit.height - old.height) > 0.5 else { return }
        let top = old.maxY
        panel.setContentSize(fit)
        panel.setFrameOrigin(NSPoint(x: old.minX, y: top - fit.height))
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard let win = button.window else { return }
        hosting.layoutSubtreeIfNeeded()
        let fit = hosting.fittingSize
        if fit.height > 100 { panel.setContentSize(fit) }
        let btn = win.frame
        let screen = (win.screen ?? NSScreen.main!).visibleFrame
        let size = panel.frame.size
        var x = btn.midX - size.width / 2
        x = min(max(screen.minX + 8, x), screen.maxX - size.width - 8)
        let y = btn.minY - size.height - 5
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak panel] in
            panel?.makeFirstResponder(nil)
        }
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if panel.isVisible { panel.orderOut(nil) } else { show(relativeTo: button) }
    }

    private func copyDiag() {
        let s = model.snap
        var lines: [String] = []
        lines.append(L("PowerWatch 诊断 \(Date())", "PowerWatch diagnostics \(Date())"))
        lines.append(L(String(format: "输入 %.1f W  %.2f V × %.2f A", s.inputW, s.inputV, s.inputA),
                        String(format: "Input %.1f W  %.2f V × %.2f A", s.inputW, s.inputV, s.inputA)))
        lines.append(L(String(format: "电池 %+.1f W  %d%%  充电:%@", s.batteryW, s.soc, s.isCharging ? "是" : "否"),
                        String(format: "Battery %+.1f W  %d%%  charging:%@", s.batteryW, s.soc, s.isCharging ? "yes" : "no")))
        lines.append(L(String(format: "电池容量 满 %.1f Wh / 现 %.1f Wh  设计 %.1f Wh",
                              s.maxMAh * s.battV / 1000, s.remainMAh * s.battV / 1000, s.designMAh * s.battV / 1000),
                        String(format: "Capacity full %.1f Wh / now %.1f Wh  design %.1f Wh",
                               s.maxMAh * s.battV / 1000, s.remainMAh * s.battV / 1000, s.designMAh * s.battV / 1000)))
        lines.append(L(String(format: "CPU %.1f%%  内存 %.1f%% (%.1f/%.1f GB)", model.cpuPct, model.memPct, model.memUsed, model.memTotal),
                        String(format: "CPU %.1f%%  Memory %.1f%% (%.1f/%.1f GB)", model.cpuPct, model.memPct, model.memUsed, model.memTotal)))
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let reader = PowerReader()
    let meter = SystemMeter()
    let sampler = ProcessSampler()
    let aiCleaner = AICleaner()
    let client = DeepSeekClient()
    let history = HistoryStore.shared
    var lastSampleTime: Date? = nil
    let controller = PanelController()
    var timer: Timer?
    var lastTuple: (Double, Double, Double)? = nil
    var lastChangeTime = Date()
    var tickCount = 0
    var forceModelUpdate = false
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var lastIconKey = ""

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let b = statusItem.button {
            b.image = batteryImage(soc: 50, charging: false)
            b.imagePosition = .imageLeading
            b.title = " —"
            b.target = self
            b.action = #selector(togglePanel)
        }

        let m = controller.model
        m.onTabChange = { [weak self] tab in
            guard let self = self, tab <= 2 else { return }
            self.sampler.sample(tab: tab) { items in self.apply(items, tab: tab) }
        }
        m.onSaveConfig = { [weak self] in
            guard let m = self?.controller.model else { return }
            UserDefaults.standard.set(m.aiBase, forKey: "AIBase")
            UserDefaults.standard.set(m.aiModel, forKey: "AIModel")
            ConfigStore.saveKey(m.aiKey)
            m.aiStatus = L("已保存", "Saved")
        }
        m.onTestConfig = { [weak self] in
            guard let self = self else { return }
            let m = self.controller.model
            guard !m.aiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
                m.aiStatus = L("请先填写 API Key", "Enter an API key first")
                return
            }
            m.aiStatus = L("测试中…", "Testing…")
            let cfg = APIConfig(base: m.aiBase, model: m.aiModel, key: m.aiKey)
            self.client.chat(config: cfg, system: "你是连接测试助手。", user: "只回复 OK", maxTokens: 200) { result in
                switch result {
                case .success: m.aiStatus = L("连接成功", "Connected")
                case .failure(let e): m.aiStatus = L("失败：", "Failed: ") + e.localizedDescription
                }
                self.controller.relayout()
            }
        }
        m.onAIClean = { [weak self] in
            guard let self = self else { return }
            let m = self.controller.model
            guard !m.aiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
                m.tab = 3
                m.aiStatus = L("请先填写 API Key", "Enter an API key first")
                self.controller.relayout()
                return
            }
            guard !m.aiCleaning else { return }
            m.aiCleaning = true
            m.aiResult = nil
            m.aiStatus = L("AI 分析中…", "AI analyzing…")
            let cfg = APIConfig(base: m.aiBase, model: m.aiModel, key: m.aiKey)
            self.aiCleaner.clean(config: cfg) { result in
                m.aiCleaning = false
                switch result {
                case .success(let msg):
                    m.aiResult = msg
                    m.aiStatus = L("完成", "Done")
                case .failure(let e):
                    m.aiStatus = L("失败：", "Failed: ") + e.localizedDescription
                }
                self.tick()
                self.controller.relayout()
            }
        }

        m.launchAtLogin = hasLaunchAgent
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                m.launchAtLogin = true
            case .requiresApproval:
                m.loginMessage = L("请在系统设置 > 登录项中允许 PowerWatch", "Allow PowerWatch in System Settings > Login Items")
            default:
                break
            }
        }
        m.onToggleLaunchAtLogin = { [weak self] in
            guard let self = self else { return }
            let m = self.controller.model
            let enable = !m.launchAtLogin
            if !enable {
                if #available(macOS 13.0, *) {
                    try? SMAppService.mainApp.unregister()
                }
                self.removeLaunchAgent()
                m.launchAtLogin = false
                m.loginMessage = L("已关闭开机自启", "Launch at login disabled")
                self.controller.relayout()
                return
            }
            var enabled = false
            var needsApproval = false
            if #available(macOS 13.0, *) {
                do {
                    try SMAppService.mainApp.register()
                    let st = SMAppService.mainApp.status
                    if st == .enabled {
                        self.removeLaunchAgent()
                        enabled = true
                        m.loginMessage = L("已开启开机自启", "Launch at login enabled")
                    } else if st == .requiresApproval {
                        needsApproval = true
                        m.loginMessage = L("请在系统设置 > 登录项中允许 PowerWatch", "Allow PowerWatch in System Settings > Login Items")
                    }
                } catch {
                    // fall through to the LaunchAgent fallback
                }
            }
            if !enabled && !needsApproval {
                do {
                    try self.installLaunchAgent()
                    enabled = true
                    m.loginMessage = L("已开启开机自启（LaunchAgent）", "Launch at login enabled (LaunchAgent)")
                } catch {
                    m.loginMessage = L("开机自启失败：", "Failed to enable launch at login: ") + error.localizedDescription
                }
            }
            m.launchAtLogin = enabled
            self.controller.relayout()
        }

        tick()
        let t = Timer(timeInterval: 1.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
        startPowerSourceNotifications()

        if !CommandLine.arguments.contains("--pinned") {
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.controller.panel.orderOut(nil)
            }
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] e in
                if let self = self, self.controller.panel.isVisible, e.window !== self.controller.panel {
                    self.controller.panel.orderOut(nil)
                }
                return e
            }
        }

        if CommandLine.arguments.contains("--demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self = self, let b = self.statusItem.button else { return }
                self.controller.show(relativeTo: b)
            }
        }
        if CommandLine.arguments.contains("--demo-clean") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.controller.model.onAIClean()
            }
        }
    }

    private func startPowerSourceNotifications() {
        let callback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { context in
            guard let context = context else { return }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { delegate.tick() }
        }
        if let unmanaged = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque()) {
            let source = unmanaged.takeRetainedValue()
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            powerSourceRunLoopSource = source
        }
    }

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/local.yt.powerwatch.plist")
    }

    private var hasLaunchAgent: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    private func installLaunchAgent() throws {
        let dir = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dict: [String: Any] = [
            "Label": "local.yt.powerwatch",
            "ProgramArguments": ["/Applications/PowerWatch.app/Contents/MacOS/PowerWatch"],
            "RunAtLoad": true,
            "ProcessType": "Interactive"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: launchAgentURL, options: .atomic)
    }

    private func removeLaunchAgent() {
        try? FileManager.default.removeItem(at: launchAgentURL)
    }

    private func apply(_ items: [ProcItem], tab: Int) {
        switch tab {
        case 1: controller.model.cpuList = items
        case 2: controller.model.memList = items
        default: controller.model.powerList = items
        }
    }

    @objc func togglePanel() {
        guard let b = statusItem.button else { return }
        if controller.panel.isVisible {
            controller.toggle(relativeTo: b)
            return
        }
        forceModelUpdate = true
        tick()
        controller.toggle(relativeTo: b)
        let tab = controller.model.tab
        if tab <= 2 {
            sampler.sample(tab: tab) { [weak self] items in self?.apply(items, tab: tab) }
        }
    }

    @objc func tick() {
        tickCount += 1
        guard let s = reader.read() else {
            statusItem.button?.title = L(" 读取失败", " Read failed")
            return
        }

        if let b = statusItem.button {
            let key = "\(s.soc)-\(s.isCharging)"
            if key != lastIconKey {
                lastIconKey = key
                b.image = batteryImage(soc: s.soc, charging: s.isCharging)
            }
            let title = " \(Int((s.inputW > 1 ? s.inputW : abs(s.batteryW)).rounded()))W"
            if b.title != title { b.title = title }
        }

        let tup = (s.inputW, s.batteryW, s.loadW)
        if let last = lastTuple, last != tup { lastChangeTime = Date() }
        if lastTuple == nil { lastChangeTime = Date() }
        lastTuple = tup

        let visible = controller.panel.isVisible || forceModelUpdate
        forceModelUpdate = false
        if visible {
            controller.model.snap = s
            controller.model.age = Int(Date().timeIntervalSince(lastChangeTime))
            controller.model.cpuPct = meter.cpuPercent()
            let mem = meter.memory()
            controller.model.memUsed = mem.usedGB
            controller.model.memTotal = mem.totalGB
            controller.model.memPct = mem.percent
            controller.model.memReclaim = mem.reclaimGB
        }

        if lastSampleTime == nil || Date().timeIntervalSince(lastSampleTime!) >= 60 {
            lastSampleTime = Date()
            history.append(PowerSample(t: Date().timeIntervalSince1970, w: s.inputW, b: s.batteryW, soc: s.soc))
        }

        if visible {
            controller.model.history = history.samples
            let tab = controller.model.tab
            if (tab == 1 || tab == 2) && tickCount % 2 == 0 {
                sampler.sample(tab: tab) { [weak self] items in self?.apply(items, tab: tab) }
            }
            if tab == 0 && tickCount % 6 == 0 {
                sampler.sample(tab: 0) { [weak self] items in self?.apply(items, tab: 0) }
            }
        }
    }

    // 电池图标：内部嵌入当前电量百分比
    private func batteryImage(soc: Int, charging: Bool) -> NSImage {
        // 2x 位图绘制，Retina 屏上边缘与数字才清晰
        let scale: CGFloat = 2
        let w: CGFloat = 31, h: CGFloat = 14.5
        let pxW = Int(w * scale), pxH = Int(h * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            return NSImage(size: NSSize(width: w, height: h))
        }
        rep.size = NSSize(width: w, height: h)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.cgContext.scaleBy(x: scale, y: scale)
        ctx.shouldAntialias = true

        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill(using: .copy)

        let bodyW: CGFloat = 26.0
        let bodyRect = NSRect(x: 0, y: 0.5, width: bodyW, height: h - 1)
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 4.4, yRadius: 4.4)

        // 灰色轨道
        NSColor.white.withAlphaComponent(0.30).setFill()
        bodyPath.fill()

        // 按电量填充
        let ratio = CGFloat(min(100, max(0, soc))) / 100
        if ratio > 0.01 {
            NSGraphicsContext.saveGraphicsState()
            bodyPath.addClip()
            let fill = NSRect(x: 0, y: 0.5, width: bodyW * ratio, height: h - 1)
            NSColor.white.withAlphaComponent(1.0).setFill()
            fill.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        // 右侧凸点
        let cap = NSBezierPath(roundedRect: NSRect(x: bodyW + 0.7, y: h / 2 - 2.4, width: 1.7, height: 4.8),
                               xRadius: 0.85, yRadius: 0.85)
        NSColor.white.withAlphaComponent(0.30).setFill()
        cap.fill()

        // 数字：深灰实心，和白胶囊形成高对比；充电时左边加闪电
        let ink = NSColor(white: 0.35, alpha: 1.0)
        let fontSize: CGFloat = charging ? (soc >= 100 ? 8.4 : 9.4) : (soc >= 100 ? 9.2 : 10.4)
        let str = NSAttributedString(string: "\(soc)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: ink
        ])
        let tsize = str.size()

        var boltW: CGFloat = 0
        var gap: CGFloat = 0
        if charging { boltW = 5.0; gap = 1.4 }

        let groupW = boltW + gap + tsize.width
        let gx = ((bodyW - groupW) / 2 * scale).rounded() / scale

        if charging {
            let bh: CGFloat = 8.6
            let by = (h - bh) / 2
            func bp(_ nx: CGFloat, _ ny: CGFloat) -> NSPoint {
                NSPoint(x: gx + nx * boltW, y: by + (1 - ny) * bh)
            }
            let bolt = NSBezierPath()
            bolt.move(to: bp(0.58, 0.0))
            bolt.line(to: bp(0.10, 0.58))
            bolt.line(to: bp(0.42, 0.58))
            bolt.line(to: bp(0.26, 1.0))
            bolt.line(to: bp(0.90, 0.40))
            bolt.line(to: bp(0.54, 0.40))
            bolt.line(to: bp(0.80, 0.0))
            bolt.close()
            ink.setFill()
            bolt.fill()
        }

        let tx = ((gx + boltW + gap) * scale).rounded() / scale
        let ty = ((h - tsize.height) / 2 * scale).rounded() / scale + 0.3
        str.draw(in: NSRect(x: tx, y: ty, width: tsize.width, height: tsize.height))

        NSGraphicsContext.restoreGraphicsState()

        let img = NSImage(size: NSSize(width: w, height: h))
        img.addRepresentation(rep)
        img.isTemplate = false
        return img
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
