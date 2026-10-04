//
//  Array+NilIfEmpty.swift
//  xcrashlytics
//

public extension Array {
    var nilIfEmpty: Self? {
        isEmpty ? nil : self
    }
}
