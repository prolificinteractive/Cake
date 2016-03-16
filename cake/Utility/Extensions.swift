//
//  Extensions.swift
//  cake
//
//  Created by Christopher Jones on 3/16/16.
//  Copyright © 2016 Prolific Interactive. All rights reserved.
//

import ReactiveCocoa
import Result

extension SignalProducerType where Error == TaskError {

    func waitOnResult() -> Result<(), CakeError> {
        let result = producer
            .then(SignalProducer<(), TaskError>.empty)
            .flatMapError { taskError in
                return SignalProducer(error: CakeError(message: taskError.description))
        }
            .wait()

        Task.waitForAllTaskTermination()
        return result
    }

}
