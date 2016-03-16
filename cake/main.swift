 //
//  main.swift
//  cake
//
//  Created by Christopher Jones on 3/16/16.
//  Copyright © 2016 Prolific Interactive. All rights reserved.
//

import Commandant
import Result

 let registry = CommandRegistry<CakeError>()
 registry.register(BuildCommand())
 registry.register(CheckDependenciesCommand())
 registry.register(StripFrameworksCommand())

 let helpCommand = HelpCommand<CakeError>(registry: registry)
 registry.register(helpCommand)

 registry.main(defaultVerb: helpCommand.verb) { error in
    print(error.message)
 }