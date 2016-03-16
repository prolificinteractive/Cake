//
//  MKDIR.swift
//  cake
//
//  Created by Christopher Jones on 3/16/16.
//  Copyright © 2016 Prolific Interactive. All rights reserved.
//

import ReactiveCocoa

internal func mkdir(dir: String) -> SignalProducer<TaskEvent<NSData>, TaskError> {
    let task = Task("/bin/mkdir", arguments: [dir])
    return launchTask(task)
}
