//
//  CheckDependenciesOptions.swift
//  cake
//
//  Created by Christopher Jones on 3/18/16.
//  Copyright © 2016 Prolific Interactive. All rights reserved.
//

import Commandant
import Result

internal struct CheckDependenciesOptions: OptionsType {

    typealias ClientError = CakeError

    let strict: Bool

    static func evaluate(mode: CommandMode) -> Result<CheckDependenciesOptions, CommandantError<ClientError>> {
        return create
            <*> mode <| Option(key: "strict",
                defaultValue: false,
                usage: "Use this option to throw an error if a mismatch of dependencies is found. The default is to simply emit warnings.")
    }

    private static func create(strict: Bool) -> CheckDependenciesOptions {
        return CheckDependenciesOptions(strict: strict)
    }
}
