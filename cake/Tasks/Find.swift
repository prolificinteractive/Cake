//
//  Find.swift
//  cake
//
//  Created by Christopher Jones on 3/17/16.
//  Copyright © 2016 Prolific Interactive. All rights reserved.
//

import ReactiveCocoa

internal func find(path: String, pattern: String, filesOnly: Bool = false, additionalParams: [String] = []) -> SignalProducer<TaskEvent<NSData>, TaskError> {
    var args = [path, "-name", pattern ]
    if filesOnly {
        args.appendContentsOf(["-type", "f"])
    }

    args.appendContentsOf(additionalParams)

    let findTask = Task("/usr/bin/find", arguments: args)
    return launchTask(findTask)
}
