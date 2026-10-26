import Foundation
import Darwin

public final class QEMUBinaryRunner {
    private typealias QemuInitFunc = @convention(c) (Int32, UnsafePointer<UnsafePointer<CChar>?>?, UnsafePointer<UnsafePointer<CChar>?>?) -> Int32
    private typealias QemuMainLoopFunc = @convention(c) () -> Void
    private typealias QemuCleanupFunc = @convention(c) () -> Void

    private var handle: UnsafeMutableRawPointer?
    private var supportingHandles: [UnsafeMutableRawPointer] = []
    private var qemu_init: QemuInitFunc?
    private var qemu_main_loop: QemuMainLoopFunc?
    private var qemu_cleanup: QemuCleanupFunc?

    public init() {}

    deinit {
        unload()
    }

    public func load(for architecture: Architecture) throws {
        guard let frameworksURL = Bundle.main.privateFrameworksURL else {
            throw NSError(domain: "QEMUBinaryRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bundle Frameworks directory not found"])
        }

        // Preload core supporting frameworks with RTLD_GLOBAL so QEMU symbols resolve cleanly
        let preloads = [
            "ffi.8", "intl.8", "iconv.2",
            "glib-2.0.0", "gmodule-2.0.0", "gobject-2.0.0", "gthread-2.0.0", "gio-2.0.0",
            "pixman-1.0", "jpeg.62", "png16.16", "zstd.1", "slirp.0"
        ]

        for name in preloads {
            let fwPath = frameworksURL.appendingPathComponent("\(name).framework/\(name)").path
            if FileManager.default.fileExists(atPath: fwPath) {
                if let h = dlopen(fwPath, RTLD_NOW | RTLD_GLOBAL) {
                    supportingHandles.append(h)
                }
            }
        }

        let frameworkName = (architecture == .arm64) ? "qemu-aarch64-softmmu" : "qemu-x86_64-softmmu"
        let frameworkURL = frameworksURL.appendingPathComponent("\(frameworkName).framework/\(frameworkName)")

        guard FileManager.default.fileExists(atPath: frameworkURL.path) else {
            throw NSError(domain: "QEMUBinaryRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: "QEMU binary framework missing at \(frameworkURL.path)"])
        }

        guard let handle = dlopen(frameworkURL.path, RTLD_NOW | RTLD_GLOBAL) else {
            let err = dlerror().map { String(cString: $0) } ?? "unknown error"
            throw NSError(domain: "QEMUBinaryRunner", code: 3, userInfo: [NSLocalizedDescriptionKey: "dlopen failed: \(err)"])
        }
        self.handle = handle

        guard let initSym = dlsym(handle, "qemu_init"),
              let loopSym = dlsym(handle, "qemu_main_loop"),
              let cleanSym = dlsym(handle, "qemu_cleanup") else {
            let err = dlerror().map { String(cString: $0) } ?? "missing entry symbols"
            throw NSError(domain: "QEMUBinaryRunner", code: 4, userInfo: [NSLocalizedDescriptionKey: "dlsym failed: \(err)"])
        }

        self.qemu_init = unsafeBitCast(initSym, to: QemuInitFunc.self)
        self.qemu_main_loop = unsafeBitCast(loopSym, to: QemuMainLoopFunc.self)
        self.qemu_cleanup = unsafeBitCast(cleanSym, to: QemuCleanupFunc.self)
    }

    public func run(arguments: [String]) throws {
        guard let qemu_init = qemu_init,
              let qemu_main_loop = qemu_main_loop,
              let qemu_cleanup = qemu_cleanup else {
            throw NSError(domain: "QEMUBinaryRunner", code: 5, userInfo: [NSLocalizedDescriptionKey: "QEMU runner not loaded"])
        }

        let cArgs = arguments.map { strdup($0) }
        var argv: [UnsafePointer<CChar>?] = cArgs.map { UnsafePointer($0) }
        argv.append(nil)

        let argc = Int32(arguments.count)

        let initResult = argv.withUnsafeBufferPointer { buffer in
            qemu_init(argc, buffer.baseAddress, nil)
        }

        for ptr in cArgs {
            free(ptr)
        }

        guard initResult == 0 else {
            throw NSError(domain: "QEMUBinaryRunner", code: Int(initResult), userInfo: [NSLocalizedDescriptionKey: "qemu_init returned non-zero exit code \(initResult)"])
        }

        qemu_main_loop()
        qemu_cleanup()
    }

    public func unload() {
        if let h = handle {
            dlclose(h)
            handle = nil
        }
        for h in supportingHandles {
            dlclose(h)
        }
        supportingHandles.removeAll()

        qemu_init = nil
        qemu_main_loop = nil
        qemu_cleanup = nil
    }
}
