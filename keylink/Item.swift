//
//  Item.swift
//  keylink
//
//  Created by Henriques on 7/30/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
