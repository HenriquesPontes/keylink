import Foundation

extension String {
    var isHexDigit: Bool {
        return self.allSatisfy { $0.isHexDigit }
    }
}

extension Character {
    var isHexDigit: Bool {
        return self.isNumber || (self >= "A" && self <= "F") || (self >= "a" && self <= "f")
    }
}

// Additional helpers can be added here
