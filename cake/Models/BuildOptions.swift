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
    let clean: Bool
    let sdks: [SDK]

    static func evaluate(m: CommandMode) -> Result<BuildOptions, CommandantError<ClientError>> {
        return create
            <*> m <| Option(key: "verbose", defaultValue: false, usage: "When specified, all output will be displyed.")
            <*> m <| Switch(key: "clean", usage: "Use to indicate that the entire Cake folder should be updated")
            <*> m <| Option(key: "sdk", defaultValue: nil, usage: "Specify an sdk to build for. By default, both simulator and iPhone architectures will be built. Use this to only build one architecture. Valid values:\n- simulator\n- iphone")
    }

    private static func create(verbose: Bool)(clean: Bool)(sdkString: String?) -> BuildOptions {
        let sdks: [SDK]
        if let sdkString = sdkString, sdk = SDK(rawValue: sdkString) {
            sdks = [sdk]
        } else {
            sdks = [.iPhoneOS, .Simulator]
        }

        return BuildOptions(verbose: verbose, clean: clean, sdks: sdks)
    }

}
