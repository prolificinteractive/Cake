//
//  StripFrameworksOptions.swift
//  cake
//
//  Created by Christopher Jones on 3/18/16.
//  Copyright © 2016 Prolific Interactive. All rights reserved.
//

import Commandant
import Result

internal struct StripFrameworksOptions: OptionsType {

    typealias ClientError = CakeError

    let frameworksPath: String
    let codeSignIdentity: String
    let codeSigningRequired: Bool
    let validArchitectures: [String]

    static func evaluate(mode: CommandMode) -> Result<StripFrameworksOptions, CommandantError<ClientError>> {
        guard let buildDirectory = NSProcessInfo.processInfo().environment["CONFIGURATION_BUILD_DIR"],
            frameworksDirectory = NSProcessInfo.processInfo().environment["FRAMEWORKS_FOLDER_PATH"],
            codeSignIdentity = NSProcessInfo.processInfo().environment["EXPANDED_CODE_SIGN_IDENTITY"],
            validArchitectures = NSProcessInfo.processInfo().environment["VALID_ARCHS"]
        else {
                return .Failure(
                    CommandantError.UsageError(description: "The CONFIGURATION_BUILD_DIR or FRAMEWORKS_FOLDER_PATH environment variables were not found. These variables are required to run `strip-frameworks`.")
            )
        }

        let codeSigningRequired: Bool = {
            if let envVar = NSProcessInfo.processInfo().environment["CODE_SIGNING_REQUIRED"] {
                return (envVar as NSString).boolValue
            }

            return false
        }()

        return .Success(
            StripFrameworksOptions(
                frameworksPath: buildDirectory.stringByAppendingPathComponent(frameworksDirectory),
                codeSignIdentity: codeSignIdentity,
                codeSigningRequired: codeSigningRequired,
                validArchitectures: validArchitectures
                    .componentsSeparatedByString(" ")
                    .filterEmpty()
                    .map { $0.trim() }
            )
        )
    }

}
