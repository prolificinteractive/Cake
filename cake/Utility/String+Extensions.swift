//
//  String+Extensions.swift
//  cake
//
//  Created by Christopher Jones on 3/17/16.
//  Copyright © 2016 Prolific Interactive. All rights reserved.
//

import Foundation

extension String {

    func stringByAppendingPathComponent(component: String) -> String {
        return (self as NSString).stringByAppendingPathComponent(component)
    }

    func trim() -> String {
        return stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
    }
    
}

extension Array where Element: StringLiteralConvertible {

    func filterEmpty() -> [String] {
        return map { String($0) }
            .map { $0.trim() }
            .filter { !$0.isEmpty }
    }

}