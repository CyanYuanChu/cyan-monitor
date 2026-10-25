import SwiftUI
import AppKit

@MainActor final class FeatureController: ObservableObject {
    let monitor = SystemMonitor(); let settings = MenuBarSettings(); let startup = StartupManager()
    var content: AnyView { AnyView(SystemSettingsView(monitor: monitor, settings: settings, startup: startup, p: GrovePalette())) }
    func start() { monitor.start() }
    func stop() { monitor.stop() }
    func refresh() { monitor.sample() }
    func perform(_ action: String) async {}
    var summary: [String:String] { let r = monitor.reading; return ["CPU": SystemReading.percent(r.cpu), "内存": SystemReading.memory(r.memoryUsed), "磁盘剩余": SystemReading.bytes(r.diskTotal.flatMap { total in r.diskUsed.map { total - $0 } }), "下载": SystemReading.rate(r.download), "上传": SystemReading.rate(r.upload)] }
    var menuImage: NSImage? { MenuBarBadgeRenderer.combined(reading: monitor.reading, enabled: settings.enabled) }
}

extension FeatureController { var previewContent: AnyView { content } }
