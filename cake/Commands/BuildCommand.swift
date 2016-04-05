//
//  BuildCommand.swift
//  cake
//
//  Created by Christopher Jones on 3/16/16.
//  Copyright © 2016 Prolific Interactive. All rights reserved.
//

import Commandant
import Foundation
import ReactiveCocoa
import Result

internal struct BuildCommand: CommandType {

    typealias Options = BuildOptions

    let verb = "build"
    let function = "Updates the dependencies in the Podfile and builds the frameworks.."

    func run(options: Options) -> Result<(), Options.ClientError> {
        let outputDirectory = "Cake"
        let buildDirectory = outputDirectory.stringByAppendingPathComponent("Build")
        let checkoutDirectory = outputDirectory.stringByAppendingPathComponent("Checkout")
        let podsProjectDirectory = checkoutDirectory.stringByAppendingPathComponent("Pods.xcodeproj")
        let podsScheme = "Pods"

        let simulatorOutputDirectory = buildDirectory.stringByAppendingPathComponent("simulator")
        let iphoneOutputDirectory = buildDirectory.stringByAppendingPathComponent("iphone")
        let buildOutputDirectory = buildDirectory.stringByAppendingPathComponent("iOS")

        let printOut = { (text: String) -> SignalProducer<(), TaskError> in
            return SignalProducer { (observer, _) in
                print(text)
                SignalProducer.empty.start(observer)
            }
        }

        return
            printOut("Preparing environment")
            .then(
                SignalProducer<TaskEvent<NSData>, TaskError> { (observer, _) in
                    guard options.clean else {
                        SignalProducer.empty.start(observer)
                        return
                    }

                    rm(outputDirectory)
                        .then( mkdir(outputDirectory) )
                        .start(observer)
                }
            )
            .then( printOut("Fetching dependencies") )
            .then(
                Pod.install()
                    .filter { _ in options.verbose }
                    .stream()
            )
            .then( printOut("Building Dependencies") )
            .then ( printOut("Architectures: \(options.sdks.reduce("") { $0 + " " + $1.rawValue })") )
            .then(
                fetchAllTargets("Pods/Pods.xcodeproj")
                    .flatMap(.Concat) { targets in
                        return diff(targets: targets, oldDirectory: "Pods", newDirectory: checkoutDirectory)
                }
                    .flatMap(.Concat) { targets in
                        return targets.reduce(SignalProducer<(), TaskError>.empty) { (current, next) in
                            current
                                .then ( printOut("> \(next)") )
                                .then (
                                    build(project: "Pods/Pods.xcodeproj", target: next, sdks: options.sdks, configurationBuildDir: "../Cake/Build/")
                                        .filter { _ in options.verbose }
                                        .stream()
                                        .then( cleanExtraFrameworks(inDirectory: simulatorOutputDirectory) )
                                        .then( cleanExtraFrameworks(inDirectory: iphoneOutputDirectory) )
                                        .map { _ in }
                            )
                        }
                }
            )
            .then( rm(checkoutDirectory) )
            .then( mkdir(buildOutputDirectory) )
            .then( mv("Pods", checkoutDirectory) )
            .then( printOut("Generating frameworks") )
            .then (
                generateFatBinaries(iphoneOutputDirectory,
                    simulatorPath: simulatorOutputDirectory,
                    outputDirectory: buildOutputDirectory)
            )
            .then( printOut("Copying dSYMs") )
            .then (
                copyDSYM(inDirectory: iphoneOutputDirectory, toDirectory: buildOutputDirectory)
            )
            .then( rm(simulatorOutputDirectory) )
            .then( rm(iphoneOutputDirectory) )
            .then( printOut("Copying fetched frameworks") )
            .then (
                copyFrameworks(podsProjectDirectory, scheme: podsScheme,
                    configuration: "Release", toDirectory: buildOutputDirectory)
            )
            .then( printOut("Copying static libraries") )
            .then (
                copyLibraries(podsProjectDirectory, scheme: podsScheme,
                    configuration: "Release", toDirectory: buildOutputDirectory)
            )
            .then ( printOut("Copying bundles") )
            .then(
                copyBundles(foundInDirectory: checkoutDirectory, toDirectory: buildOutputDirectory)
            )
            .then( printOut("Cleaning up") )
            .then (
                rm(buildDirectory.stringByAppendingPathComponent("Pods.build"))
            )
            .then ( rm("build") )
            .then( printOut("Build complete!") )
            .waitOnResult()
    }

}
