import Foundation
import Darwin

public final class QEMULoader {
    public typealias QemuInit = @convention(c) (Int32, UnsafePointer<UnsafePointer<CChar>?>?, UnsafePointer<UnsafePointer<CChar>?>?) -> Void
    public typealias QemuMainLoop = @convention(c) () -> Void
    public typealias QemuCleanup = @convention(c) () -> Void

    private var primaryHandle: UnsafeMutableRawPointer?
    private var dependencyHandles: [UnsafeMutableRawPointer] = []

    public private(set) var qemuInit: QemuInit?
    public private(set) var qemuMainLoop: QemuMainLoop?
    public private(set) var qemuCleanup: QemuCleanup?

    public init() {}

    deinit {
        unload()
    }

    public func load(architecture: Architecture) throws {
        guard let frameworksURL = Bundle.main.privateFrameworksURL else {
            throw NSError(domain: "QEMULoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Frameworks directory missing in bundle"])
        }

        let dependencies = [
            "ffi.8", "intl.8", "iconv.2",
            "glib-2.0.0", "gmodule-2.0.0", "gobject-2.0.0", "gthread-2.0.0", "gio-2.0.0",
            "pixman-1.0", "jpeg.62", "png16.16", "zstd.1", "slirp.0"
        ]

        for dep in dependencies {
            let path = frameworksURL.appendingPathComponent("\(dep).framework/\(dep)").path
            if FileManager.default.fileExists(atPath: path) {
                if let handle = dlopen(path, RTLD_LOCAL | RTLD_LAZY) {
                    dependencyHandles.append(handle)
                }
            }
        }

        let mainBinaryPath = frameworksURL.appendingPathComponent("\(architecture.qemuFrameworkName).framework/\(architecture.qemuFrameworkName)").path
        guard FileManager.default.fileExists(atPath: mainBinaryPath) else {
            throw NSError(domain: "QEMULoader", code: 2, userInfo: [NSLocalizedDescriptionKey: "QEMU framework not found: \(mainBinaryPath)"])
        }

        guard let handle = dlopen(mainBinaryPath, RTLD_LOCAL | RTLD_LAZY | RTLD_FIRST) else {
            let err = dlerror().map { String(cString: $0) } ?? "unknown error"
            throw NSError(domain: "QEMULoader", code: 3, userInfo: [NSLocalizedDescriptionKey: "dlopen failed: \(err)"])
        }
        self.primaryHandle = handle

        guard let initSym = dlsym(handle, "qemu_init"),
              let loopSym = dlsym(handle, "qemu_main_loop"),
              let cleanupSym = dlsym(handle, "qemu_cleanup") else {
            let err = dlerror().map { String(cString: $0) } ?? "missing entry symbols"
            throw NSError(domain: "QEMULoader", code: 4, userInfo: [NSLocalizedDescriptionKey: "dlsym failed: \(err)"])
        }

        self.qemuInit = unsafeBitCast(initSym, to: QemuInit.self)
        self.qemuMainLoop = unsafeBitCast(loopSym, to: QemuMainLoop.self)
        self.qemuCleanup = unsafeBitCast(cleanupSym, to: QemuCleanup.self)
    }

    public func unload() {
        if let h = primaryHandle {
            dlclose(h)
            primaryHandle = nil
        }
        for h in dependencyHandles {
            dlclose(h)
        }
        dependencyHandles.removeAll()

        qemuInit = nil
        qemuMainLoop = nil
        qemuCleanup = nil
    }
}
