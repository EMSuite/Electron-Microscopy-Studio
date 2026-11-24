//
//  ProcessMemory.swift
//  Role: the app's own memory as the kernel counts it (`task_vm_info`): the physical footprint now and its peak since launch, which
//        get_window reports so the size table (#904, tools/parity/size-table) reads what opening a file cost from outside the app. The
//        footprint is what Activity Monitor's Memory column shows: resident and compressed anonymous pages and the graphics ledger.
//

import Darwin

nonisolated enum ProcessMemory {
    /// The footprint now and the highest it has been since the process started, in bytes; nil when the kernel does not answer.
    static func footprint() -> (now: Int, peak: Int)? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let now = Int(info.phys_footprint)
        return (now, max(now, Int(info.ledger_phys_footprint_peak)))
    }
}
