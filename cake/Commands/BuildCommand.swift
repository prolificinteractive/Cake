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
            .then( rm(outputDirectory) )
            .then( printOut("Fetching dependencies") )
            .then(
                Pod.install()
                    .filter { _ in options.verbose }
                    .stream()
            )
            .then( mv("Pods", "tmp") )
            .then( mkdir(outputDirectory) )
            .then( mv("tmp", outputDirectory.stringByAppendingPathComponent("Checkout")) )
            .then( printOut("Building dependencies") )
            .then(
                xcodebuild(podsProjectDirectory, scheme: podsScheme, sdk: .Simulator, configurationBuildDir: "../Build/simulator")
                    .filter { _ in options.verbose }
                    .stream()
                    .then(cleanExtraFrameworks(inDirectory: simulatorOutputDirectory))
            )
            .then(
                xcodebuild(podsProjectDirectory, scheme: podsScheme, sdk: .iPhoneOS, configurationBuildDir: "../Build/iphone")
                    .filter { _ in options.verbose }
                    .stream()
                    .then(cleanExtraFrameworks(inDirectory: iphoneOutputDirectory))
            )
            .then( mkdir(buildOutputDirectory) )
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
             .then( printOut("Cleaning up") )
            .then (
                rm(buildDirectory.stringByAppendingPathComponent("Pods.build"))
            )
            .then( printOut("Build complete!") )
            .waitOnResult()
    }



}
