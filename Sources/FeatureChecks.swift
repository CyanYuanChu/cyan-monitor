import Foundation
import AppKit
@MainActor enum FeatureChecks {
    static func run() async {
        var failed = 0
        func check(_ condition: Bool, _ name: String) { print((condition ? "PASS " : "FAIL ") + name); if !condition { failed += 1 } }
        check(ModuleMetadata.value["protocolVersion"] as? Int == 2, "module protocol metadata")
        check(!ModuleMetadata.id.contains("/"), "stable module identity")
        check(FileManager.default.fileExists(atPath: FeatureResources.bundle.resourcePath! + "/module.json"), "standalone manifest bundled")
        let monitor = SystemMonitor(); monitor.sample(); try? await Task.sleep(nanoseconds: 100_000_000); monitor.sample()
        check(monitor.reading.cpu != nil, "real CPU sample")
        check(monitor.reading.memoryUsed != nil, "real memory sample")
        check(!MenuMetric.allCases.map(\.rawValue).contains("codex"), "monitor has no Codex dependency")
        let feature = FeatureController(); let saved = feature.settings.enabled
        let expanded = feature.menuImage!.size.width
        feature.settings.enabled = []; let compact = feature.menuImage!.size.width
        check(compact < expanded || saved.isEmpty, "menu switches change native status image")
        feature.settings.enabled = saved
        check(feature.menuImage!.isTemplate, "native status image follows macOS appearance")
        print("MODULE_TESTS \(failed == 0 ? "OK" : "FAILED")")
        if failed > 0 { exit(1) }
    }
}
