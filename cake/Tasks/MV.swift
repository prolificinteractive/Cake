//
//  MV.swift
//  cake
//
//  Created by Christopher Jones on 3/16/16.
//  Copyright © 2016 Prolific Interactive. All rights reserved.
//

import ReactiveCocoa

internal func mv(from: String, _ to: String) -> SignalProducer<TaskEvent<NSData>, TaskError> {
    let task = Task("/bin/mv", arguments: [from, to])
    return launchTask(task)
}
