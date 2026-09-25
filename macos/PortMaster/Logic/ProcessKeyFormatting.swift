import Foundation

enum ProcessKeyFormatting {
    static func id(for key: ProcessKey) -> String {
        if let usec = key.startUsec {
            return "\(key.pid)-\(key.startSec)-\(usec)"
        }
        return "\(key.pid)-\(key.startSec)-none"
    }
}
