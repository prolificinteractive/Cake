//
//  StripFrameworksCommand.swift
//  cake
//
//  Created by Christopher Jones on 3/18/16.
//  Copyright © 2016 Prolific Interactive. All rights reserved.
//

import Commandant
import ReactiveCocoa
import Result

internal struct StripFrameworksCommand: CommandType {

    typealias Options = StripFrameworksOptions

    let verb = "strip-frameworks"
    let function = "Checks all of the built dynamic frameworks in the compiled bundle and strips any invalid architectures. This fixes an App Store submission bug."

    func run(options: Options) -> Result<(), Options.ClientError> {
        return find(options.frameworksPath, pattern: "*", filesOnly: true, additionalParams: ["-perm", "+111"])
            .mapOutputToString()
            .split()
            .flatMap(.Concat) { frameworkPaths -> SignalProducer<(), TaskError> in
                return frameworkPaths.reduce(SignalProducer<(), TaskError>.empty) { (signal, next) in
                    return signal.then (
                        isDynamicLibrary(next)
                            .filter { $0 }
                            .flatMap(.Concat) { _ in architectures(forItemAtPath: next) }
                            .map { architectures in
                                return architectures.filter { !options.validArchitectures.contains($0) }
                            }
                            .filter { !$0.isEmpty }
                            .flatMap(.Concat) { architectures in
                                stripArchitectures(architectures, atPath: next)
                            }
                            .filter { options.codeSigningRequired }
                            .flatMap(.Concat) { _ in codeSign(next, codeSigningIdentity: options.codeSignIdentity) }
                            .flatMap(.Concat) { _ in SignalProducer<(), TaskError>.empty }
                    )
                }
            }
        .waitOnResult()
    }

}
