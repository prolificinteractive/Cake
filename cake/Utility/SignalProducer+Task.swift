//
//  Stream.swift
//  cake
//
//  Created by Christopher Jones on 3/16/16.
//  Copyright © 2016 Prolific Interactive. All rights reserved.
//

import ReactiveCocoa

extension SignalProducerType where Value: TaskEventType, Value.T: NSData {

    func stream() -> SignalProducer<Value, Error> {
        return producer.on(next: { taskEvent in
            let event = taskEvent.map { $0 }
            switch event {
            case let .StandardOutput(data):
                if let output = String(data: data, encoding: NSUTF8StringEncoding)  {
                    print (output)
                }
            default:
                break
            }
        })
    }

    func mapOutput<U>(transform: Value.T -> U) -> SignalProducer<U, Error> {
        return producer.ignoreTaskData().map(transform)
    }

    func mapOutputToString() -> SignalProducer<String, Error> {
        return mapOutput { String(data: $0, encoding: NSUTF8StringEncoding) }
                .ignoreNil()
    }

    func endOutput() -> SignalProducer<(), Error> {
        return producer.flatMap(.Latest) { _ in SignalProducer.empty }
    }

}

extension SignalProducerType where Value: StringLiteralConvertible {

    func split() -> SignalProducer<[String], Error> {
        return producer
            .map {
                String($0).componentsSeparatedByCharactersInSet(NSCharacterSet.newlineCharacterSet())
                    .filter { $0.characters.count > 0  }
        }
    }

}

extension SignalProducerType where Value == [String] {

    func trim() -> SignalProducer<[String], Error> {
        return producer
            .map {
                $0.map { $0.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet()) }
        }
    }

}
