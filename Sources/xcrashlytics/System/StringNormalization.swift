//
//  StringNormalization.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 8.06.2026.
//

import Foundation

extension String {
    /// The trimmed value, or nil when empty after trimming.
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
