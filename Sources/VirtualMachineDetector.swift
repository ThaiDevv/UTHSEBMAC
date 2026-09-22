import Foundation

struct VirtualMachineDetectionResult {
    let isVirtualMachine: Bool
    let reason: String
}

enum VirtualMachineDetector {
    private static func commandOutput(_ launchPath: String, _ arguments: [String]) -> String {
        let process = Process()
        process.launchPath = launchPath
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
    
    static func detect() -> VirtualMachineDetectionResult {
        // 1. Check Hardware Profile and Model
        let hardwareInfo = commandOutput("/usr/sbin/system_profiler", ["SPHardwareDataType"])
        let cpuBrand = commandOutput("/usr/sbin/sysctl", ["machdep.cpu.brand_string"])
        
        if VirtualMachinePolicy.containsAny(hardwareInfo, terms: VirtualMachinePolicy.computerSystemTerms) {
            return VirtualMachineDetectionResult(
                isVirtualMachine: true,
                reason: "Hardware profile/model='\(hardwareInfo.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))'"
            )
        }
        
        if VirtualMachinePolicy.containsAny(cpuBrand, terms: VirtualMachinePolicy.computerSystemTerms) {
            return VirtualMachineDetectionResult(
                isVirtualMachine: true,
                reason: "Hardware profile/model='\(cpuBrand.trimmingCharacters(in: .whitespacesAndNewlines))'"
            )
        }
        
        // 2. Check Storage Profile
        let storageInfo = commandOutput("/usr/sbin/system_profiler", ["SPStorageDataType"])
        if VirtualMachinePolicy.containsAny(storageInfo, terms: VirtualMachinePolicy.diskTerms) {
            return VirtualMachineDetectionResult(
                isVirtualMachine: true,
                reason: "Storage profile contains virtual disk signature"
            )
        }
        
        // 3. Check Running Guest Processes
        let processList = commandOutput("/bin/ps", ["-axo", "comm"])
        let lines = processList.components(separatedBy: "\n")
        for line in lines {
            let proc = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !proc.isEmpty && VirtualMachinePolicy.containsAny(proc, terms: VirtualMachinePolicy.guestToolTerms) {
                return VirtualMachineDetectionResult(
                    isVirtualMachine: true,
                    reason: "Running guest tool process '\(proc)'"
                )
            }
        }
        
        return VirtualMachineDetectionResult(
            isVirtualMachine: false,
            reason: "Không tìm thấy dấu hiệu máy ảo."
        )
    }
}
