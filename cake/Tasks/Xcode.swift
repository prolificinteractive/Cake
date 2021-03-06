//
//  Xcodebuild.swift
//  cake
//
//  Created by Christopher Jones on 3/16/16.
//  Copyright © 2016 Prolific Interactive. All rights reserved.
//

import ReactiveCocoa

private let xcodebuildPath = "/usr/bin/xcodebuild"
private let lipoPath = "/usr/bin/lipo"

internal enum SDK: String {

    case Simulator = "simulator"
    case iPhoneOS = "iphone"

    var buildParams: [String] {
        switch self {
        case .Simulator:
            return ["-destination", "platform=iOS Simulator,name=iPhone 6,OS=latest", "-sdk", "iphonesimulator"]
        case .iPhoneOS:
            return ["-sdk", "iphoneos"]
        }
    }

}

internal func fetchAllTargets(project: String) -> SignalProducer<[String], TaskError> {
    let task = Task(xcodebuildPath, arguments: ["-project", project, "-list"])

    return launchTask(task)
        .mapOutputToString()
        .split()
        .trim()
        .map { allOutput in
            guard let targetsIndex = allOutput.indexOf("Targets:")?.advancedBy(1) else {
                return []
            }

            guard let configsIndex = allOutput.indexOf("Build Configurations:")?.advancedBy(-1) else {
                return []
            }

            guard configsIndex > targetsIndex else {
                return []
            }

            let newArray = allOutput[targetsIndex...configsIndex]
            return Array(newArray)
    }
}

internal func diff(targets targets: [String], oldDirectory: String, newDirectory: String) -> SignalProducer<[String], TaskError> {

    return targets.reduce(SignalProducer<String, TaskError>.empty) { (current, next) -> SignalProducer<String, TaskError> in
        return current.concat(
            diff("\(oldDirectory)/\(next)", "\(newDirectory)/\(next)")
                .filter { $0 }
                .map { _ in next }
                .filter { $0 != "Pods" }
        )
    }
        .collect()
}

internal func diff(leftDirectory: String, _ rightDirectory: String) -> SignalProducer<Bool, TaskError> {
    let task = Task("/usr/bin/diff", arguments: ["-r", leftDirectory, rightDirectory])
    return launchTask(task)
        .mapOutput { data in
            return data.length > 0
        }
        .flatMapError { _ in SignalProducer(value: true) }
}

internal func build(project project: String, target: String, sdks: [SDK], configurationBuildDir: String) -> SignalProducer<TaskEvent<NSData>, TaskError> {
    let simulatorSignal = SignalProducer<TaskEvent<NSData>, TaskError> { (observer, _) in
        guard sdks.contains(.Simulator) else {
            SignalProducer.empty.start(observer)
            return
        }

        xcodebuild(project, target: target,
            sdk: .Simulator,
            configurationBuildDir: configurationBuildDir.stringByAppendingPathComponent(SDK.Simulator.rawValue)
        ).start(observer)
    }

    let iphoneSignal = SignalProducer<TaskEvent<NSData>, TaskError> { (observer, _) in
        guard sdks.contains(.iPhoneOS) else {
            SignalProducer.empty.start(observer)
            return
        }

        xcodebuild(
            project,
            target: target,
            sdk: .iPhoneOS,
            configurationBuildDir: configurationBuildDir.stringByAppendingPathComponent(SDK.iPhoneOS.rawValue)
        ).start(observer)
    }

    return simulatorSignal.concat(iphoneSignal)
}

internal func xcodebuild(project: String, target: String,
    sdk: SDK, configurationBuildDir: String) -> SignalProducer<TaskEvent<NSData>, TaskError> {

        let settings = XcodebuildSettings(project: project, target: target, configuration: "Release", sdk: sdk, configurationBuildDir: configurationBuildDir)

        let task = Task(xcodebuildPath, arguments: settings.toParams())
        return launchTask(task)
}

internal func cleanExtraFrameworks(inDirectory directory: String) -> SignalProducer<TaskEvent<NSData>, TaskError> {
    return rm(directory.stringByAppendingPathComponent("Pods.framework"))
}

internal func generatedSYM(forProjectsAtPath path: String)  -> SignalProducer<(), TaskError> {
    return find(path, pattern: ".framework")
        .mapOutputToString()
        .split()
        .flatMap(.Concat) { resultPaths -> SignalProducer<(), TaskError> in
            let dsymTask = { (path: String) -> Task in
                let frameworkFullName = (path as NSString).lastPathComponent
                let frameworkName = (frameworkFullName as NSString).stringByDeletingPathExtension
                let dsymOutputPath = (path as NSString).stringByAppendingPathExtension("dSYM")!
                let frameworkExePath = (path as NSString).stringByAppendingPathComponent(frameworkName)
                return Task("/usr/bin/xcrun", arguments: ["dsymutil", frameworkExePath, "-o", dsymOutputPath])
            }

            var signal = SignalProducer<(), TaskError>.empty
            for path in resultPaths {
                let task = dsymTask(path)
                signal =  signal.then(launchTask(task).stream().endOutput())
            }

            return signal
    }
}

internal func generateFatBinaries(osPath: String, simulatorPath: String, outputDirectory: String) -> SignalProducer<TaskEvent<NSData>, TaskError> {
    return find(osPath, pattern: "*.framework")
        .mapOutputToString()
        .split()
        .combineLatestWith( find(simulatorPath, pattern: "*.framework").mapOutputToString().split() )
        .flatMapError { _ in SignalProducer(value: ([], [])) }
        .flatMap(.Concat) { (osFrameworkPaths, simulatorFrameworkPaths) -> SignalProducer<TaskEvent<NSData>, TaskError> in
            let extractFrameworkInformation = { (fullPath: String) -> (fullName:String, name: String) in
                let frameworkFullName = (fullPath as NSString).lastPathComponent
                let frameworkName = (frameworkFullName as NSString).stringByDeletingPathExtension

                return (frameworkFullName, frameworkName)
            }

            var output = SignalProducer<TaskEvent<NSData>, TaskError>.empty
            for osFrameworkPath in osFrameworkPaths {
                let osFrameworkInformation = extractFrameworkInformation(osFrameworkPath)
                guard let simulatorFrameworkPath = simulatorFrameworkPaths
                        .filter({ extractFrameworkInformation($0).fullName == osFrameworkInformation.fullName }).first else {
                    continue
                }

                let osExecutablePath = osFrameworkPath.stringByAppendingPathComponent(osFrameworkInformation.name)
                let simulatorExecutablePath = simulatorFrameworkPath.stringByAppendingPathComponent(osFrameworkInformation.name)
                let outputLipoPath = outputDirectory.stringByAppendingPathComponent(osFrameworkInformation.name)
                let outputPath = outputDirectory.stringByAppendingPathComponent(osFrameworkInformation.fullName)

                let swiftModulePath = { (frameworkPath: String, frameworkName: String) -> String in
                    return frameworkPath.stringByAppendingPathComponent("Modules")
                        .stringByAppendingPathComponent("\(frameworkName).swiftmodule")
                }

                output = output.then( lipo(simulatorExecutablePath, secondPath: osExecutablePath, output: outputLipoPath) )
                    .then( rm (outputPath) )
                    .then( cp(osFrameworkPath, outputPath) )
                    .then( mv(outputLipoPath, outputPath) )
                    .then(
                        SignalProducer { (observer, _) in
                            let osModulePath = swiftModulePath(outputPath, osFrameworkInformation.name)
                            if NSFileManager.defaultManager().fileExistsAtPath(osModulePath) {
                                let simulatorModulePath = swiftModulePath(simulatorFrameworkPath, osFrameworkInformation.name)
                                find(simulatorModulePath, pattern: "*", filesOnly: true)
                                    .mapOutputToString()
                                    .split()
                                    .flatMap(.Concat) { files -> SignalProducer<TaskEvent<NSData>, TaskError> in
                                        var signal = SignalProducer<TaskEvent<NSData>, TaskError>.empty
                                        for file in files {
                                            signal = signal.then( cp(file, osModulePath) )
                                        }

                                        return signal
                                }
                                    .start(observer)
                            } else {
                                SignalProducer.empty.start(observer)
                            }
                        }
                )
            }

            return output
        }
}

internal func copyDSYM(inDirectory directory: String, toDirectory to: String) -> SignalProducer<TaskEvent<NSData>, TaskError> {
    return find(directory, pattern: "*.dSYM")
        .mapOutputToString()
        .split()
        .flatMapError { _ in SignalProducer(value: []) }
        .flatMap(.Concat) { dsymPaths -> SignalProducer<TaskEvent<NSData>, TaskError> in
            var outputSignal = SignalProducer<TaskEvent<NSData>, TaskError>.empty
            for dsymPath in dsymPaths {
                outputSignal = outputSignal.then( cp(dsymPath, to) )
            }

            return outputSignal
    }
}

internal func copyFrameworks(projectPath: String, scheme: String, configuration: String, toDirectory directory: String) -> SignalProducer<TaskEvent<NSData>, TaskError> {
    return buildSettings(projectPath, scheme: scheme, configuration: configuration)
        .flatMap(.Concat) { settings -> SignalProducer<[String], TaskError> in
            guard let frameworkSearchPaths = settings["FRAMEWORK_SEARCH_PATHS"] else {
                return SignalProducer.empty
            }

            return SignalProducer(value: frameworkSearchPaths.componentsSeparatedByString(" ").filter { $0.characters.count > 0 })
    }
        .flatMap(.Concat) { frameworkPaths -> SignalProducer<TaskEvent<NSData>, TaskError> in
            var output = SignalProducer<TaskEvent<NSData>, TaskError>.empty
            for frameworkPath in frameworkPaths {
                output = output.then(
                    find(frameworkPath, pattern: "*.framework")
                        .mapOutputToString()
                        .split()
                        .flatMap(.Concat) { frameworks -> SignalProducer<TaskEvent<NSData>, TaskError> in
                            var output = SignalProducer<TaskEvent<NSData>, TaskError>.empty
                            for framework in frameworks {
                                let name = (framework as NSString).lastPathComponent
                                output = output.then (
                                    rm ("\(directory)/\(name)")
                                        .then (
                                            mv(framework, directory)
                                        )
                                )
                            }

                            return output
                    }
                )
            }

            return output
    }
}

internal func copyLibraries(projectPath: String, scheme: String, configuration: String, toDirectory directory: String) -> SignalProducer<TaskEvent<NSData>, TaskError> {
    return buildSettings(projectPath, scheme: scheme, configuration: configuration)
        .flatMap(.Concat) { settings -> SignalProducer<[String], TaskError> in
            guard let frameworkSearchPaths = settings["LIBRARY_SEARCH_PATHS"] else {
                return SignalProducer.empty
            }

            return SignalProducer(value: frameworkSearchPaths.componentsSeparatedByString(" ").filter { $0.characters.count > 0 })
    }
        .flatMap(.Concat) { librarySearchPaths -> SignalProducer<TaskEvent<NSData>, TaskError> in
            return librarySearchPaths.reduce(SignalProducer<TaskEvent<NSData>, TaskError>.empty) { (signal, path) in
                let name = (path as NSString).lastPathComponent
                return signal
                    .then( rm("\(directory)/\(name)") )
                    .then( cp(path, directory) )
            }
    }
}

internal func copyBundles(foundInDirectory rootDirectory: String, toDirectory directory: String) -> SignalProducer<TaskEvent<NSData>, TaskError> {
    return find(rootDirectory, pattern: "*.bundle")
        .mapOutputToString()
        .split()
        .flatMap(.Concat) { files in
            return files.reduce(SignalProducer<TaskEvent<NSData>, TaskError>.empty) { (signal, file) in
                return signal.then(cp(file, directory))
            }
    }
}

internal func buildSettings(projectPath: String, scheme: String, configuration: String) -> SignalProducer<[String: String], TaskError> {
    let task = Task(xcodebuildPath,
        arguments: ["-project", projectPath, "-scheme", scheme, "-configuration", configuration, "-showBuildSettings"])
    return launchTask(task)
        .mapOutputToString()
        .split()
        .map { keyValueStrings in
            let tuples = keyValueStrings.map { string -> (String, String)? in
                let split = string.componentsSeparatedByString("=")
                guard split.count == 2 else {
                    return nil
                }

                return (split[0], split[1])
            }
                .flatMap { $0 }

            var output: [String: String] = [:]

            for tuple in tuples {
                output[tuple.0.trim().stringByReplacingOccurrencesOfString("\"", withString: "")] =
                    tuple.1.stringByReplacingOccurrencesOfString("\"", withString: "")
            }

            return output
    }
}

internal func isDynamicLibrary(path: String) -> SignalProducer<Bool, TaskError> {
    let fileTask = Task("/usr/bin/file", arguments: [path])
    return launchTask(fileTask).mapOutputToString()
            .map { $0.containsString("dynamically linked shared library") }
}

internal func lipo(firstPath: String, secondPath: String, output: String) -> SignalProducer<TaskEvent<NSData>, TaskError> {
    let task = Task(lipoPath, arguments: ["-create", firstPath, secondPath, "-output", output])
    return launchTask(task)
}

internal func architectures(forItemAtPath itemPath: String) -> SignalProducer<[String], TaskError> {
    let task = Task(lipoPath, arguments: ["-info", itemPath])
    return launchTask(task)
        .mapOutputToString()
        .map { resultString in
            let components = resultString.componentsSeparatedByString(":")
            guard components.count == 3 else {
                return []
            }

            let architectures = components.last!
            return architectures.componentsSeparatedByString(" ").filterEmpty()
    }
}

internal func stripArchitectures(architectures: [String], atPath path: String) -> SignalProducer<(), TaskError> {
    return architectures.reduce(SignalProducer<(), TaskError>.empty) { (signal, next) in
        let lipoTask = Task(lipoPath, arguments: ["-remove", next, "-output", path, path])
        return signal.then (
            launchTask(lipoTask)
                .ignoreTaskData()
                .flatMap(.Concat) { _ in SignalProducer.empty }
        )
    }
}

internal func codeSign(executablePath: String, codeSigningIdentity: String) -> SignalProducer<TaskEvent<NSData>, TaskError> {
    let task = Task("/usr/bin/codesign",
        arguments: [
            "--force",
            "--sign", codeSigningIdentity,
            "--preserve-metadata=identifier,entitlements",
            executablePath
        ])
    return launchTask(task)
}


private struct XcodebuildSettings {

    let project: String
    let target: String
    let configuration: String
    let sdk: SDK
    let configurationBuildDir: String

    func toParams() -> [String] {
        var args: [String] = [
            "-project", project,
            "-target", target,
            "-configuration", configuration,
        ]

        args.appendContentsOf(sdk.buildParams)
        args.appendContentsOf([
            "ONLY_ACTIVE_ARCH=NO",
            "CONFIGURATION_BUILD_DIR=\(configurationBuildDir)",
            "CODE_SIGNING_REQUIRED=NO",
            "CODE_SIGNING_ALLOWED=NO",
            "BITCODE_GENERATION_MODE=bitcode",
        ])

        return args
    }

}
