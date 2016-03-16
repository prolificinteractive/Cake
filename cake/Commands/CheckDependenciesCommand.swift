//
//  CheckDependencies.swift
//  cake
//
//  Created by Christopher Jones on 3/18/16.
//  Copyright © 2016 Prolific Interactive. All rights reserved.
//

import Commandant
import ReactiveCocoa
import Result

internal struct CheckDependenciesCommand: CommandType {

    typealias Options = CheckDependenciesOptions

    let verb = "check-dependencies"
    let function = "Checks that your dependencies are synced with the Podfile."

    func run(options: Options) -> Result<(), Options.ClientError> {
        let outputDirectory = "Cake"
        let checkoutDirectory = outputDirectory.stringByAppendingPathComponent("Checkout")

        let podfileLock = "Podfile.lock"
        let manifest = checkoutDirectory.stringByAppendingPathComponent("Manifest.lock")

        let diffTask = Task("/usr/bin/diff", arguments: [podfileLock, manifest])
        return launchTask(diffTask)
            .flatMapError { (error) in
                guard !options.strict else {
                    return SignalProducer(error: CakeError(message: "error: The Podfile.lock is not in sync with your Podfile. To resolve this issue, run `cake update` on your Podfile."))
                }

                print("warning: The dependencies you are building with are not in sync with the ones specified in your Podfile. Please run `cake update` in order to prevent any issues related to mismatched versions or missing frameworks.")
                return SignalProducer.empty
            }
        .wait()
    }

}
