import Foundation
import Darwin

public enum JITManager {
    public static var isJITEnabled: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        // 1. Check csops CS_DEBUGGED (0x10000000)
        var flags: UInt32 = 0
        let CS_OPS_STATUS: UInt32 = 0
        let CS_DEBUGGED: UInt32 = 0x10000000

        typealias CsopsFunc = @convention(c) (pid_t, UInt32, UnsafeMutableRawPointer, Int) -> Int32
        if let handle = dlopen(nil, RTLD_LAZY),
           let sym = dlsym(handle, "csops") {
            let csops = unsafeBitCast(sym, to: CsopsFunc.self)
            if csops(getpid(), CS_OPS_STATUS, &flags, MemoryLayout<UInt32>.size) == 0 {
                if (flags & CS_DEBUGGED) != 0 {
                    return true
                }
            }
        }

        // 2. Fallback: Test allocate an executable page via vm_protect
        let size = vm_size_t(PAGE_SIZE)
        var addr: vm_address_t = 0
        let allocRes = vm_allocate(mach_task_self_, &addr, size, VM_FLAGS_ANYWHERE)
        guard allocRes == KERN_SUCCESS else { return false }
        defer { vm_deallocate(mach_task_self_, addr, size) }

        let protRes = vm_protect(mach_task_self_, addr, size, 0, VM_PROT_READ | VM_PROT_EXECUTE)
        return protRes == KERN_SUCCESS
        #endif
    }

    public static var statusDescription: String {
        isJITEnabled ? "Active" : "Restricted"
    }
}
