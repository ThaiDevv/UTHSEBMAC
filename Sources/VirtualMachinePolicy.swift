import Foundation

enum VirtualMachinePolicy {
    static let guestToolTerms: [String] = [
        "vmtools", "vmware tools", "vboxservice", "vboxtray", "virtualbox guest",
        "qemu-ga", "qemu guest", "xenservice", "xen guest", "prl_tools",
        "parallels tools", "prltoolsd"
    ]
    
    static let diskTerms: [String] = [
        "vmware", "vbox", "virtualbox", "virtual", "qemu", "kvm", "xen", "parallels"
    ]
    
    static let computerSystemTerms: [String] = [
        "vmware", "virtualbox", "innotek", "xen", "qemu", "kvm", "bochs",
        "parallels", "bhyve", "virtual machine", "virtualmac", "apple virtualization",
        "microsoft corporation"
    ]
    
    static func containsAny(_ text: String, terms: [String]) -> Bool {
        let lower = text.lowercased()
        for term in terms {
            if lower.contains(term) {
                return true
            }
        }
        return false
    }
    
    static func isVirtualComputerSystem(manufacturer: String?, model: String?) -> Bool {
        if let manufacturer = manufacturer, containsAny(manufacturer, terms: computerSystemTerms) {
            return true
        }
        if let model = model, containsAny(model, terms: computerSystemTerms) {
            return true
        }
        return false
    }
    
    static func isVirtualDisk(caption: String?, model: String?, manufacturer: String?) -> Bool {
        if let caption = caption, containsAny(caption, terms: diskTerms) {
            return true
        }
        if let model = model, containsAny(model, terms: diskTerms) {
            return true
        }
        if let manufacturer = manufacturer, containsAny(manufacturer, terms: diskTerms) {
            return true
        }
        return false
    }
}
