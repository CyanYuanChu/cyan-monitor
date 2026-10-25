import Foundation
import AppKit
import Combine
import Darwin

struct SystemReading {
    var cpu: Double?; var memoryUsed: Double?; var memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
    var diskUsed: Double?; var diskTotal: Double?; var download: Double?; var upload: Double?
    var date = Date()
    static func rate(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        if value >= 1_000_000 { return String(format: "%.1f MB/s", value / 1_000_000) }
        return String(format: "%.0f KB/s", value / 1_000)
    }
    static func memory(_ value: Double?) -> String { value.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) } ?? "—" }
    static func bytes(_ value: Double?) -> String { value.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "—" }
    static func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", min(100,max(0,$0))) } ?? "—" }
}

@MainActor final class SystemMonitor: ObservableObject {
    @Published var reading = SystemReading()
    @Published var history: [Double] = []
    private var previousCPU: (UInt64, UInt64)?
    private var previousNetwork: [String: (UInt32, UInt32)] = [:]
    private var previousTime: TimeInterval?
    private var timer: Timer?
    func start() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.sample() } }
    }
    func sample() {
        var value = SystemReading()
        var cpu = host_cpu_load_info(); var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let cpuResult = withUnsafeMutablePointer(to: &cpu) { ptr in ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) } }
        if cpuResult == KERN_SUCCESS {
            let ticks = cpu.cpu_ticks
            let active = UInt64(ticks.0) + UInt64(ticks.1) + UInt64(ticks.3), total = active + UInt64(ticks.2)
            if let old = previousCPU, total > old.1, active >= old.0 { value.cpu = Double(active - old.0) / Double(total - old.1) * 100 }
            previousCPU = (active,total)
        }
        var vm = vm_statistics64(); var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) { ptr in ptr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount) } }
        if vmResult == KERN_SUCCESS {
            let pages = Double(vm.active_count) + Double(vm.inactive_count) + Double(vm.wire_count) + Double(vm.compressor_page_count) - Double(vm.purgeable_count) - Double(vm.external_page_count)
            value.memoryUsed = min(value.memoryTotal, max(0, pages * Double(vm_kernel_page_size)))
        }
        if let disk = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()), let total = disk[.systemSize] as? NSNumber, let free = disk[.systemFreeSize] as? NSNumber {
            value.diskTotal = total.doubleValue; value.diskUsed = max(0,total.doubleValue-free.doubleValue)
        }
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        var network: [String:(UInt32,UInt32)] = [:]
        if getifaddrs(&interfaces) == 0 {
            var cursor = interfaces
            while let current = cursor {
                let item = current.pointee
                let name = String(cString: item.ifa_name)
                if name.hasPrefix("en"), item.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), (item.ifa_flags & UInt32(IFF_UP)) != 0, let data = item.ifa_data {
                    let link = data.assumingMemoryBound(to: if_data.self).pointee
                    network[name] = (link.ifi_ibytes, link.ifi_obytes)
                }
                cursor = item.ifa_next
            }
            freeifaddrs(interfaces)
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let previousTime, now > previousTime, !network.isEmpty {
            let matched = network.filter { previousNetwork[$0.key] != nil }
            if !matched.isEmpty {
                value.download = matched.reduce(0) { $0 + Double($1.value.0 &- previousNetwork[$1.key]!.0) } / (now-previousTime)
                value.upload = matched.reduce(0) { $0 + Double($1.value.1 &- previousNetwork[$1.key]!.1) } / (now-previousTime)
            }
        }
        previousTime = now; previousNetwork = network; reading = value
        if let cpu = value.cpu { history = Array((history + [cpu]).suffix(60)) }
    }
}

enum MenuMetric: String, CaseIterable, Identifiable {
    case cpu, memory, disk, network
    var id: String { rawValue }
    var title: String { switch self { case .cpu: "CPU 使用率"; case .memory: "内存占用"; case .disk: "磁盘剩余空间"; case .network: "网络上下行" } }
    var icon: String { switch self { case .cpu: "cpu"; case .memory: "memorychip"; case .disk: "internaldrive"; case .network: "network" } }
}
@MainActor final class MenuBarSettings: ObservableObject {
    @Published var enabled: Set<String> { didSet { UserDefaults.standard.set(Array(enabled), forKey: "cyan.menu.metrics") } }
    init() { enabled = Set(UserDefaults.standard.stringArray(forKey: "cyan.menu.metrics") ?? MenuMetric.allCases.map(\.rawValue)) }
    func set(_ metric: MenuMetric, _ value: Bool) { if value { enabled.insert(metric.rawValue) } else { enabled.remove(metric.rawValue) } }
}

// Template images inherit the native menu bar tint and menu highlight.
enum MenuBarBadgeRenderer {
    static func compactRate(_ bytes: Double?) -> String {
        guard let bytes, bytes.isFinite, bytes >= 0 else { return "—" }
        let divisor: Double
        let unit: String
        switch bytes {
        case 1_000_000_000...: divisor = 1_000_000_000; unit = "G/s"
        case 1_000_000...: divisor = 1_000_000; unit = "M/s"
        case 1_000...: divisor = 1_000; unit = "K/s"
        default: divisor = 1; unit = "B/s"
        }
        let value = bytes / divisor
        if value >= 999.5 { return "999" + unit }
        return String(format: value < 10 && divisor > 1 ? "%.1f" : "%.0f", value) + unit
    }

    private static let valueFontSize: CGFloat = 10.5

    static func percentage(symbol: String, value: Double?, stale: Bool = false) -> NSImage {
        badge(symbol: symbol, text: SystemReading.percent(value), reserve: "100%", stale: stale)
    }

    static func capacityText(bytes: Double?, memory: Bool = false) -> String {
        guard let bytes, bytes.isFinite, bytes >= 0 else { return "—" }
        let gb = bytes / (memory ? 1_073_741_824 : 1_000_000_000)
        if memory { return String(format: "%.1fGB", gb) }
        if gb >= 1_000 { return String(format: "%.1fTB", gb / 1_000) }
        return String(format: gb < 10 ? "%.1fGB" : "%.0fGB", gb)
    }

    static func capacity(symbol: String, bytes: Double?, memory: Bool = false) -> NSImage {
        badge(symbol: symbol, text: capacityText(bytes: bytes, memory: memory), reserve: memory ? "99.9GB" : "999GB")
    }

    // Every metric lives in one NSStatusItem; macOS cannot insert padding between them.
    static func combined(reading: SystemReading, enabled: Set<String>, stale: Bool = false) -> NSImage {
        var system: [NSImage] = []
        if enabled.contains("cpu") {
            system.append(column(symbol: "cpu", text: SystemReading.percent(reading.cpu), reserve: "100%"))
        }
        if enabled.contains("memory") {
            system.append(column(symbol: "memorychip", text: capacityText(bytes: reading.memoryUsed, memory: true), reserve: "99.9GB"))
        }
        if enabled.contains("disk") {
            let free = reading.diskUsed.flatMap { used in reading.diskTotal.map { max(0, $0 - used) } }
            system.append(column(symbol: "internaldrive", text: capacityText(bytes: free), reserve: "999GB"))
        }
        var groups: [NSImage] = []
        if !system.isEmpty { groups.append(join(system, gap: 3)) }
        if enabled.contains("network") { groups.append(network(download: reading.download, upload: reading.upload)) }
        if groups.isEmpty {
            return template(width: 16) { _ in drawSymbol("leaf", in: NSRect(x: 1, y: 4, width: 14, height: 14), pointSize: 13) }
        }
        return join(groups, gap: 7, separators: true)
    }

    private static func column(symbol: String, text: String, reserve: String, stale: Bool = false) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let width = ceil(max((text as NSString).size(withAttributes: [.font: font]).width,
                             (reserve as NSString).size(withAttributes: [.font: font]).width)) + 1
        return template(width: width) { rect in
            drawSymbol(symbol, in: NSRect(x: (width - 9) / 2, y: 12, width: 9, height: 9), pointSize: 9)
            let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
            drawText(text, in: NSRect(x: (width - textWidth) / 2, y: 0, width: textWidth, height: 11), fontSize: 9)
            if stale {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: width - 3, y: 17, width: 2, height: 2)).fill()
            }
        }
    }

    private static func join(_ images: [NSImage], gap: CGFloat, separators: Bool = false) -> NSImage {
        let width = images.reduce(0) { $0 + $1.size.width } + CGFloat(max(0, images.count - 1)) * gap
        return template(width: width) { _ in
            var x: CGFloat = 0
            for (index, image) in images.enumerated() {
                if index > 0 {
                    if separators {
                        NSColor.black.withAlphaComponent(0.22).setFill()
                        NSBezierPath(rect: NSRect(x: x + gap / 2 - 0.25, y: 5, width: 0.5, height: 12)).fill()
                    }
                    x += gap
                }
                image.draw(in: NSRect(x: x, y: 0, width: image.size.width, height: 22))
                x += image.size.width
            }
        }
    }

    private static func badge(symbol: String, text: String, reserve: String, stale: Bool = false) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: valueFontSize, weight: .medium)
        let width = ceil(max((text as NSString).size(withAttributes: [.font: font]).width,
                             (reserve as NSString).size(withAttributes: [.font: font]).width))
        return template(width: 14 + width) { rect in
            drawSymbol(symbol, in: NSRect(x: 0, y: 5.5, width: 11, height: 11), pointSize: 10.5)
            drawText(text, in: NSRect(x: 14, y: 0, width: width, height: rect.height), fontSize: valueFontSize)
            if stale {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 0, y: 1, width: 2, height: 2)).fill()
            }
        }
    }

    static func network(download: Double?, upload: Double?) -> NSImage {
        template(width: 48) { _ in
            drawSymbol("arrow.up", in: NSRect(x: 0, y: 12, width: 6, height: 8), pointSize: 7)
            drawSymbol("arrow.down", in: NSRect(x: 0, y: 2, width: 6, height: 8), pointSize: 7)
            drawText(compactRate(upload), in: NSRect(x: 9, y: 11, width: 39, height: 10), fontSize: 9)
            drawText(compactRate(download), in: NSRect(x: 9, y: 1, width: 39, height: 10), fontSize: 9)
        }
    }

    private static func template(width: CGFloat, draw: @escaping (NSRect) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { rect in
            draw(rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawSymbol(_ name: String, in rect: NSRect, pointSize: CGFloat) {
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .medium))
        symbol?.draw(in: rect)
    }

    private static func drawText(_ text: String, in rect: NSRect, fontSize: CGFloat) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        let line = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
        let size = line.size()
        line.draw(at: NSPoint(x: rect.minX, y: rect.midY - size.height / 2))
    }
}

