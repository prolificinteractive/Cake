//
//  CP.swift
//  cake
//
//  Created by Christopher Jones on 3/18/16.
//  Copyright © 2016 Prolific Interactive. All rights reserved.
//

import ReactiveCocoa

internal func cp(from: String, _ to: String) -> SignalProducer<TaskEvent<NSData>, TaskError> {
    let task = Task("/bin/cp", arguments: ["-R", from, to])
    return launchTask(task)
}

internal func cpFiles(from: String, _ to: String) -> SignalProducer<TaskEvent<NSData>, TaskError> {
    let task = Task("/bin/cp", arguments: ["-r", from, to])
    return launchTask(task)
}
