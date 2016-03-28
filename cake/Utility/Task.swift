//
//  Task.swift
//  ReactiveTask
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import ReactiveCocoa
import Result

/// Describes how to execute a shell command.
public struct Task {
    /// The path to the executable that should be launched.
    public var launchPath: String

    /// Any arguments to provide to the executable.
    public var arguments: [String]

    /// The path to the working directory in which the process should be
    /// launched.
    ///
    /// If nil, the launched task will inherit the working directory of its
    /// parent.
    public var workingDirectoryPath: String?

    /// Environment variables to set for the launched process.
    ///
    /// If nil, the launched task will inherit the environment of its parent.
    public var environment: [String: String]?

    public init(_ launchPath: String, arguments: [String] = [], workingDirectoryPath: String? = nil, environment: [String: String]? = nil) {
        self.launchPath = launchPath
        self.arguments = arguments
        self.workingDirectoryPath = workingDirectoryPath
        self.environment = environment
    }

    /// A GCD group which to wait completion
    private static let group = dispatch_group_create()

    /// wait for all task termination
    public static func waitForAllTaskTermination() {
        dispatch_group_wait(Task.group, DISPATCH_TIME_FOREVER)
    }
}

extension Task: CustomStringConvertible {
    public var description: String {
        return "\(launchPath) \(arguments.joinWithSeparator(" "))"
    }
}

extension Task: Hashable {
    public var hashValue: Int {
        var result = launchPath.hashValue ^ (workingDirectoryPath?.hashValue ?? 0)
        for argument in arguments {
            result ^= argument.hashValue
        }
        for (key, value) in environment ?? [:] {
            result ^= key.hashValue ^ value.hashValue
        }
        return result
    }
}

private func ==<Key: Equatable, Value: Equatable>(lhs: [Key: Value]?, rhs: [Key: Value]?) -> Bool {
    switch (lhs, rhs) {
    case let (lhs?, rhs?):
        return lhs == rhs

    case (.None, .None):
        return true

    default:
        return false
    }
}

public func ==(lhs: Task, rhs: Task) -> Bool {
    return lhs.launchPath == rhs.launchPath && lhs.arguments == rhs.arguments && lhs.workingDirectoryPath == rhs.workingDirectoryPath && lhs.environment == rhs.environment
}


/// An error originating from ReactiveTask.
public enum TaskError: ErrorType, Equatable {
    /// A shell task exited unsuccessfully.
    case ShellTaskFailed(Task, exitCode: Int32, standardError: String?)

    /// An error was returned from a POSIX API.
    case POSIXError(Int32)
}

extension TaskError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .ShellTaskFailed(task, exitCode, standardError):
            var description = "A shell task (\(task)) failed with exit code \(exitCode)"
            if let standardError = standardError {
                description += ":\n\(standardError)"
            }

            return description

        case let .POSIXError(code):
            return NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: nil).description
        }
    }
}

public func == (lhs: TaskError, rhs: TaskError) -> Bool {
    switch (lhs, rhs) {
    case let (.ShellTaskFailed(lhsTask, lhsCode, lhsErr), .ShellTaskFailed(rhsTask, rhsCode, rhsErr)):
        return lhsTask == rhsTask && lhsCode == rhsCode && lhsErr == rhsErr
        
    case let (.POSIXError(lhsCode), .POSIXError(rhsCode)):
        return lhsCode == rhsCode
        
    default:
        return false
    }
}

/// A private class used to encapsulate a Unix pipe.
private final class Pipe {
    /// The file descriptor for reading data.
    let readFD: Int32

    /// The file descriptor for writing data.
    let writeFD: Int32

    /// A GCD queue upon which to deliver I/O callbacks.
    let queue: dispatch_queue_t

    /// A GCD group which to wait completion
    let group: dispatch_group_t

    /// Creates an NSFileHandle corresponding to the `readFD`. The file handle
    /// will not automatically close the descriptor.
    var readHandle: NSFileHandle {
        return NSFileHandle(fileDescriptor: readFD, closeOnDealloc: false)
    }

    /// Creates an NSFileHandle corresponding to the `writeFD`. The file handle
    /// will not automatically close the descriptor.
    var writeHandle: NSFileHandle {
        return NSFileHandle(fileDescriptor: writeFD, closeOnDealloc: false)
    }

    /// Initializes a pipe object using existing file descriptors.
    init(readFD: Int32, writeFD: Int32, queue: dispatch_queue_t, group: dispatch_group_t) {
        precondition(readFD >= 0)
        precondition(writeFD >= 0)

        self.readFD = readFD
        self.writeFD = writeFD
        self.queue = queue
        self.group = group
    }

    /// Instantiates a new descriptor pair.
    class func create(queue: dispatch_queue_t, _ group: dispatch_group_t) -> Result<Pipe, TaskError> {
        var fildes: [Int32] = [ 0, 0 ]
        if pipe(&fildes) == 0 {
            return .Success(self.init(readFD: fildes[0], writeFD: fildes[1], queue: queue, group: group))
        } else {
            return .Failure(.POSIXError(errno))
        }
    }

    /// Closes both file descriptors of the receiver.
    func closePipe() {
        close(readFD)
        close(writeFD)
    }

    /// Creates a signal that will take ownership of the `readFD` using
    /// dispatch_io, then read it to completion.
    ///
    /// After starting the returned producer, `readFD` should not be used
    /// anywhere else, as it may close unexpectedly.
    func transferReadsToProducer() -> SignalProducer<NSData, TaskError> {
        return SignalProducer { observer, disposable in
            dispatch_group_enter(self.group)
            let channel = dispatch_io_create(DISPATCH_IO_STREAM, self.readFD, self.queue) { error in
                if error == 0 {
                    observer.sendCompleted()
                } else if error == ECANCELED {
                    observer.sendInterrupted()
                } else {
                    observer.sendFailed(.POSIXError(error))
                }

                close(self.readFD)
                dispatch_group_leave(self.group)
            }

            dispatch_io_set_low_water(channel, 1)
            dispatch_io_read(channel, 0, Int.max, self.queue) { (done, data, error) in
                if let data = data {
                    observer.sendNext(data as! NSData)
                }

                if error == ECANCELED {
                    observer.sendInterrupted()
                } else if error != 0 {
                    observer.sendFailed(.POSIXError(error))
                }

                if done {
                    dispatch_io_close(channel, 0)
                }
            }

            disposable.addDisposable {
                dispatch_io_close(channel, DISPATCH_IO_STOP)
            }
        }
    }

    /// Creates a dispatch_io channel for writing all data that arrives on
    /// `signal` into `writeFD`, then closes `writeFD` when the input signal
    /// terminates.
    ///
    /// After starting the returned producer, `writeFD` should not be used
    /// anywhere else, as it may close unexpectedly.
    ///
    /// Returns a producer that will complete or error.
    func writeDataFromProducer(producer: SignalProducer<NSData, NoError>) -> SignalProducer<(), TaskError> {
        return SignalProducer { observer, disposable in
            dispatch_group_enter(self.group)
            let channel = dispatch_io_create(DISPATCH_IO_STREAM, self.writeFD, self.queue) { error in
                if error == 0 {
                    observer.sendCompleted()
                } else if error == ECANCELED {
                    observer.sendInterrupted()
                } else {
                    observer.sendFailed(.POSIXError(error))
                }

                close(self.writeFD)
                dispatch_group_leave(self.group)
            }

            producer.startWithSignal { signal, producerDisposable in
                disposable.addDisposable(producerDisposable)

                signal.observe(Observer(next: { data in
                    let dispatchData = dispatch_data_create(data.bytes, data.length, self.queue, nil)

                    dispatch_io_write(channel, 0, dispatchData, self.queue) { (done, data, error) in
                        if error == ECANCELED {
                            observer.sendInterrupted()
                        } else if error != 0 {
                            observer.sendFailed(.POSIXError(error))
                        }
                    }
                    }, completed: {
                        dispatch_io_close(channel, 0)
                    }, interrupted: {
                        observer.sendInterrupted()
                }))
            }

            disposable.addDisposable {
                dispatch_io_close(channel, DISPATCH_IO_STOP)
            }
        }
    }
}

public protocol TaskEventType {
    /// The type of value embedded in a `Success` event.
    typealias T

    /// The resulting value, if the event is `Success`.
    var value: T? { get }

    /// Maps over the value embedded in a `Success` event.
    func map<U>(@noescape transform: T -> U) -> TaskEvent<U>

    /// Convenience operator for mapping TaskEvents to SignalProducers.
    func producerMap<U, Error>(@noescape transform: T -> SignalProducer<U, Error>) -> SignalProducer<TaskEvent<U>, Error>
}

/// Represents events that can occur during the execution of a task that is
/// expected to terminate with a result of type T (upon success).
public enum TaskEvent<T>: TaskEventType {
    /// The task is about to be launched.
    case Launch(Task)

    /// Some data arrived from the task on `stdout`.
    case StandardOutput(NSData)

    /// Some data arrived from the task on `stderr`.
    case StandardError(NSData)

    /// The task exited successfully (with status 0), and value T was produced
    /// as a result.
    case Success(T)

    /// The resulting value, if the event is `Success`.
    public var value: T? {
        if case let .Success(value) = self {
            return value
        }
        return nil
    }

    /// Maps over the value embedded in a `Success` event.
    public func map<U>(@noescape transform: T -> U) -> TaskEvent<U> {
        switch self {
        case let .Launch(task):
            return .Launch(task)

        case let .StandardOutput(data):
            return .StandardOutput(data)

        case let .StandardError(data):
            return .StandardError(data)

        case let .Success(value):
            return .Success(transform(value))
        }
    }

    /// Convenience operator for mapping TaskEvents to SignalProducers.
    public func producerMap<U, Error>(@noescape transform: T -> SignalProducer<U, Error>) -> SignalProducer<TaskEvent<U>, Error> {
        switch self {
        case let .Launch(task):
            return .init(value: .Launch(task))

        case let .StandardOutput(data):
            return .init(value: .StandardOutput(data))

        case let .StandardError(data):
            return .init(value: .StandardError(data))

        case let .Success(value):
            return transform(value).map(TaskEvent<U>.Success)
        }
    }
}

public func == <T: Equatable>(lhs: TaskEvent<T>, rhs: TaskEvent<T>) -> Bool {
    switch (lhs, rhs) {
    case let (.Launch(left), .Launch(right)):
        return left == right

    case let (.StandardOutput(left), .StandardOutput(right)):
        return left == right

    case let (.StandardError(left), .StandardError(right)):
        return left == right

    case let (.Success(left), .Success(right)):
        return left == right

    default:
        return false
    }
}

extension TaskEvent: CustomStringConvertible {
    public var description: String {
        func dataDescription(data: NSData) -> String {
            return NSString(data: data, encoding: NSUTF8StringEncoding).map { $0 as String } ?? data.description
        }

        switch self {
        case let .Launch(task):
            return "launch: \(task)"

        case let .StandardOutput(data):
            return "stdout: " + dataDescription(data)

        case let .StandardError(data):
            return "stderr: " + dataDescription(data)

        case let .Success(value):
            return "success(\(value))"
        }
    }
}

extension SignalProducer where Value: TaskEventType {
    /// Maps the values inside a stream of TaskEvents into new SignalProducers.
    public func flatMapTaskEvents<U>(strategy: FlattenStrategy, transform: Value.T -> SignalProducer<U, Error>) -> SignalProducer<TaskEvent<U>, Error> {
        return self.flatMap(strategy) { taskEvent in
            return taskEvent.producerMap(transform)
        }
    }

    /// Ignores incremental standard output and standard error data from the given
    /// task, sending only a single value with the final, aggregated result.
    public func ignoreTaskData() -> SignalProducer<Value.T, Error> {
        return lift { $0.ignoreTaskData() }
    }
}

extension Signal where Value: TaskEventType {
    /// Ignores incremental standard output and standard error data from the given
    /// task, sending only a single value with the final, aggregated result.
    public func ignoreTaskData() -> Signal<Value.T, Error> {
        return self
            .map { event in
                return event.value
            }
            .ignoreNil()
    }
}

/// Launches a new shell task.
///
/// - Parameters:
///   - task:          The task to launch.
///   - standardInput: Data to stream to standard input of the launched process. If nil, stdin will
///                    be inherited from the parent process.
///
/// - Returns: A producer that will launch the task when started, then send
/// `TaskEvent`s as execution proceeds.
public func launchTask(task: Task, standardInput: SignalProducer<NSData, NoError>? = nil) -> SignalProducer<TaskEvent<NSData>, TaskError> {
    return SignalProducer { observer, disposable in
        let queue = dispatch_queue_create(task.description, DISPATCH_QUEUE_SERIAL)
        let group = Task.group

        let rawTask = NSTask()
        rawTask.launchPath = task.launchPath
        rawTask.arguments = task.arguments

        if let cwd = task.workingDirectoryPath {
            rawTask.currentDirectoryPath = cwd
        }

        if let env = task.environment {
            rawTask.environment = env
        }

        var stdinProducer: SignalProducer<(), TaskError> = .empty

        if let input = standardInput {
            switch Pipe.create(queue, group) {
            case let .Success(pipe):
                rawTask.standardInput = pipe.readHandle

                stdinProducer = pipe.writeDataFromProducer(input).on(started: {
                    close(pipe.readFD)
                })

            case let .Failure(error):
                observer.sendFailed(error)
                return
            }
        }

        SignalProducer(result: Pipe.create(queue, group) &&& Pipe.create(queue, group))
            .flatMap(.Merge) { stdoutPipe, stderrPipe -> SignalProducer<TaskEvent<NSData>, TaskError> in
                let stdoutProducer = stdoutPipe.transferReadsToProducer()
                let stderrProducer = stderrPipe.transferReadsToProducer()

                return SignalProducer { observer, disposable in
                    let (stdoutAggregated, stdoutAggregatedObserver) = SignalProducer<NSData, TaskError>.buffer(1)
                    let (stderrAggregated, stderrAggregatedObserver) = SignalProducer<NSData, TaskError>.buffer(1)

                    stdoutProducer.startWithSignal { signal, signalDisposable in
                        disposable += signalDisposable
                        
                        let aggregate = NSMutableData()
                        signal.observe(Observer(next: { data in
                            observer.sendNext(.StandardOutput(data))
                            aggregate.appendData(data)
                            }, failed: { error in
                                observer.sendFailed(error)
                                stdoutAggregatedObserver.sendFailed(error)
                            }, completed: {
                                stdoutAggregatedObserver.sendNext(aggregate)
                                stdoutAggregatedObserver.sendCompleted()
                            }, interrupted: stdoutAggregatedObserver.sendInterrupted
                            ))
                    }
                    
                    stderrProducer.startWithSignal { signal, signalDisposable in
                        disposable += signalDisposable
                        
                        let aggregate = NSMutableData()
                        signal.observe(Observer(next: { data in
                            observer.sendNext(.StandardError(data))
                            aggregate.appendData(data)
                            }, failed: { error in
                                observer.sendFailed(error)
                                stderrAggregatedObserver.sendFailed(error)
                            }, completed: {
                                stderrAggregatedObserver.sendNext(aggregate)
                                stderrAggregatedObserver.sendCompleted()
                            }, interrupted: stderrAggregatedObserver.sendInterrupted
                            ))
                    }
                    
                    rawTask.standardOutput = stdoutPipe.writeHandle
                    rawTask.standardError = stderrPipe.writeHandle
                    
                    dispatch_group_enter(group)
                    rawTask.terminationHandler = { nstask in
                        let terminationStatus = nstask.terminationStatus
                        if terminationStatus == EXIT_SUCCESS {
                            // Wait for stderr to finish, then pass
                            // through stdout.
                            disposable += stderrAggregated
                                .then(stdoutAggregated)
                                .map(TaskEvent.Success)
                                .start(observer)
                        } else {
                            // Wait for stdout to finish, then pass
                            // through stderr.
                            disposable += stdoutAggregated
                                .then(stderrAggregated)
                                .flatMap(.Concat) { data -> SignalProducer<TaskEvent<NSData>, TaskError> in
                                    let errorString = (data.length > 0 ? NSString(data: data, encoding: NSUTF8StringEncoding) as? String : nil)
                                    return SignalProducer(error: .ShellTaskFailed(task, exitCode: terminationStatus, standardError: errorString))
                                }
                                .start(observer)
                        }
                        dispatch_group_leave(group)
                    }
                    
                    observer.sendNext(.Launch(task))
                    rawTask.launch()
                    close(stdoutPipe.writeFD)
                    close(stderrPipe.writeFD)
                    
                    stdinProducer.startWithSignal { signal, signalDisposable in
                        disposable += signalDisposable
                    }
                    
                    disposable.addDisposable {
                        rawTask.terminate()
                    }
                }
            }
            .startWithSignal { signal, taskDisposable in
                disposable.addDisposable(taskDisposable)
                signal.observe(observer)
        }
    }
}