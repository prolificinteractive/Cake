//
//  BuildOptions.swift
//  cake
//
//  Created by Christopher Jones on 3/19/16.
//  Copyright © 2016 Prolific Interactive. All rights reserved.
//

import Commandant
import Result

internal struct BuildOptions: OptionsType {

    typealias ClientError = CakeError

    let verbose: Bool

    static func evaluate(m: CommandMode) -> Result<BuildOptions, CommandantError<ClientError>> {
        return create
            <*> m <| Option(key: "verbose", defaultValue: false, usage: "When specified, all output will be displyed.")
    }

    private static func create(verbose: Bool) -> BuildOptions {
        return BuildOptions(verbose: verbose)
    }

}
