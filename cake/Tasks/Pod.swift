//
//  Pod.swift
//  cake
//
//  Created by Christopher Jones on 3/16/16.
//  Copyright © 2016 Prolific Interactive. All rights reserved.
//

import ReactiveCocoa

internal struct Pod {

    static func install() -> SignalProducer<TaskEvent<NSData>, TaskError> {
        return runWithArgs(["install", "--no-integrate"])
    }

    private static func runWithArgs(args: [String]) -> SignalProducer<TaskEvent<NSData>, TaskError> {
        let launchPath = "/usr/local/bin/pod"
        let task = Task(launchPath, arguments: args)

        return launchTask(task)
    }
}
