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
        print("MODULE_TESTS \(failed == 0 ? "OK" : "FAILED")")
        if failed > 0 { exit(1) }
    }
}
