//
//  Logger.swift
//
//  Copyright (c) 2015-present Nike, Inc. (https://www.nike.com)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

/// The Logger class is a fully thread-safe, synchronous or asynchronous logging solution using dependency injection
/// to allow custom Modifiers and Writers. It also manages all the logic to determine whether to log a particular
/// message with a given log level.
///
/// Loggers can only be configured during initialization. If you need to change a logger at runtime, it is advised to
/// create an additional logger with a custom configuration to fit your needs.
open class Logger {

    // MARK: - Helper Types

    /// Defines the two types of execution methods used when logging a message.
    ///
    /// Logging operations can be expensive operations when there are hundreds of messages being generated or when
    /// it is computationally expensive to compute the message to log. Ideally, one would use the synchronous method
    /// in development, and the asynchronous method in production. This allows for easier debugging in the development
    /// environment, and better performance in production.
    ///
    /// - synchronous:  Logs messages synchronously once the recursive lock is available in serial order.
    /// - asynchronous: Logs messages asynchronously on the dispatch queue in a serial order.
    public enum ExecutionMethod {
        case synchronous(lock: NSRecursiveLock)
        case asynchronous(queue: DispatchQueue)

        /// Performs a block of work using the desired synchronization method (either locks or serial queues).
        /// - Parameter work: An escaping block of work that needs to be protected against data races.
        public func perform(work: @escaping () -> Void) {
            switch self {
            case .synchronous(lock: let lock):
                lock.lock()
                defer { lock.unlock() }
                work()

            case .asynchronous(queue: let queue):
                queue.async { work() }
            }
        }
    }

    // MARK: - Properties

    /// A logger that does not output any messages to writers.
    public static let disabled: Logger = NoOpLogger()

    /// Controls whether to allow log messages to be sent to the writers.
    open var enabled = true

    /// Log levels this logger is configured for.
    public private(set) var logLevels: LogLevel

    // This holds any message filters that have been provided.
    public private(set) var filters: [any LogFilter] = []

    /// The array of writers to use when messages are written.
    public let writers: [LogWriter]

    /// The execution method used when logging a message.
    public let executionMethod: ExecutionMethod

    // MARK: - Initialization

    /// Initializes a logger instance.
    ///
    /// - Parameters:
    ///   - logLevels:       The message levels that should be logged to the writers.
    ///   - writers:         Array of writers that messages should be sent to.
    ///   - executionMethod: The execution method used when logging a message. `.synchronous` by default.
    public init(
        logLevels: LogLevel,
        writers: [LogWriter],
        executionMethod: ExecutionMethod = .synchronous(lock: NSRecursiveLock()))
    {
        self.logLevels = logLevels
        self.writers = writers
        self.executionMethod = executionMethod
    }

    // MARK: -  Filtering & changing log levels

    /// Sets a new log level on the logger. Any previously logged messages will be emitted based on the setting
    /// at the time they were logged.
    /// - Parameter level: The new minimum log level
    public func setLogLevels(_ levels: LogLevel) {
        executionMethod.perform {
            // if this is an async serial queue, this work we are in will happen _after_
            // any of the previously enqueued log messages are written. Therefore, this
            // ensures that messages enqueued after this call will be using the new log level
            // filter.
            self.logLevels = levels
        }
    }

    /// Adds a log filter to the logger. A filter gives you dynamic control over whether logs are emitted or not, based on content in the ``LogMessage`` struct or message itself.
    /// - Parameter filter: A ``LogFilter`` instance to add.
    public func addFilter(_ filter: any LogFilter) {
        executionMethod.perform {
            self.filters.append(filter)
        }
    }

    /// Removes a named filter from the list of filters. Must have used a ``LogFilter`` that defines its own custom name.
    /// - Parameter name: The name of the log filter, defined in the ``LogFilter`` protocol conformance.
    public func removeFilter(named name: String) {
        executionMethod.perform {
            self.filters.removeAll(where: { $0.name == name })
        }
    }

    /// Removes all log filters from the logger instance.
    public func removeFilters() {
        executionMethod.perform {
            self.filters = []
        }
    }

    // MARK: - Log Messages

    /// Writes out the given message using the logger if the debug log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: An autoclosure returning the message to log.
    open func debug(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @autoclosure @escaping () -> LogMessage
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.debug, at: logSource)
    }

    /// Writes out the given message using the logger if the debug log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: A closure returning the message to log.
    open func debug(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @escaping () -> LogMessage
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.debug, at: logSource)
    }

    /// Writes out the given message using the logger if the info log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: An autoclosure returning the message to log.
    open func info(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @autoclosure @escaping () -> LogMessage
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.info, at: logSource)
    }

    /// Writes out the given message using the logger if the info log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: A closure returning the message to log.
    open func info(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @escaping () -> LogMessage
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.info, at: logSource)
    }

    /// Writes out the given message using the logger if the event log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: An autoclosure returning the message to log.
    open func event(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @autoclosure @escaping () -> LogMessage
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.event, at: logSource)
    }

    /// Writes out the given message using the logger if the event log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: A closure returning the message to log.
    open func event(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @escaping () -> LogMessage
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.event, at: logSource)
    }

    /// Writes out the given message using the logger if the warn log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: An autoclosure returning the message to log.
    open func warn(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @autoclosure @escaping () -> LogMessage
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.warn, at: logSource)
    }

    /// Writes out the given message using the logger if the warn log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: A closure returning the message to log.
    open func warn(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @escaping () -> LogMessage
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.warn, at: logSource)
    }

    /// Writes out the given message using the logger if the error log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: An autoclosure returning the message to log.
    open func error(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @autoclosure @escaping () -> LogMessage
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.error, at: logSource)
    }

    /// Writes out the given message using the logger if the error log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: A closure returning the message to log.
    open func error(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @escaping () -> LogMessage
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.error, at: logSource)
    }

    /// Writes out the given message closure string with the logger if the log level is allowed.
    ///
    /// - Parameters:
    ///   - message:   A closure returning the message to log.
    ///   - logLevel:  The log level associated with the message closure.
    ///   - logSource: The souce of the log message.
    open func logMessage(_ message: @escaping () -> (LogMessage), with logLevel: LogLevel, at logSource: LogSource) {
        guard enabled && logLevelAllowed(logLevel) else { return }

        switch executionMethod {
        case .synchronous(let lock):
            let message = message()
            lock.lock() ; defer { lock.unlock() }
            logMessage(message, with: logLevel, at: logSource)

        case .asynchronous(let queue):
            queue.async { self.logMessage(message(), with: logLevel, at: logSource) }
        }
    }

    // MARK: - Log String Messages

    /// Writes out the given message using the logger if the debug log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: An autoclosure returning the message to log.
    open func debugMessage(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @autoclosure @escaping () -> String
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.debug, at: logSource)
    }

    /// Writes out the given message using the logger if the debug log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: A closure returning the message to log.
    open func debugMessage(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @escaping () -> String
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.debug, at: logSource)
    }

    /// Writes out the given message using the logger if the info log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: An autoclosure returning the message to log.
    open func infoMessage(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @autoclosure @escaping () -> String
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.info, at: logSource)
    }

    /// Writes out the given message using the logger if the info log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: A closure returning the message to log.
    open func infoMessage(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @escaping () -> String
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.info, at: logSource)
    }

    /// Writes out the given message using the logger if the event log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: An autoclosure returning the message to log.
    open func eventMessage(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @autoclosure @escaping () -> String
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.event, at: logSource)
    }

    /// Writes out the given message using the logger if the event log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: A closure returning the message to log.
    open func eventMessage(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @escaping () -> String
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.event, at: logSource)
    }

    /// Writes out the given message using the logger if the warn log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: An autoclosure returning the message to log.
    open func warnMessage(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @autoclosure @escaping () -> String
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.warn, at: logSource)
    }

    /// Writes out the given message using the logger if the warn log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: A closure returning the message to log.
    open func warnMessage(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @escaping () -> String
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.warn, at: logSource)
    }

    /// Writes out the given message using the logger if the error log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: An autoclosure returning the message to log.
    open func errorMessage(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @autoclosure @escaping () -> String
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.error, at: logSource)
    }

    /// Writes out the given message using the logger if the error log level is set.
    ///
    /// - Parameter file: The name of the file where the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter function: The name of the function in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter line: The line number on which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter column: The column number in which the message is logged. Do not provide a value; keep the default instead.
    /// - Parameter message: A closure returning the message to log.
    open func errorMessage(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line,
        column: UInt = #column,
        _ message: @escaping () -> String
    ) {
        let logSource = LogSource(file: file, function: function, line: line, column: column)
        logMessage(message, with: LogLevel.error, at: logSource)
    }

    /// Writes out the given message closure string with the logger if the log level is allowed.
    ///
    /// - Parameters:
    ///   - message:    A closure returning the message to log.
    ///   - logLevel:   The log level associated with the message closure.
    ///   - logSource:  The souce of the log message.
    open func logMessage(_ message: @escaping () -> String, with logLevel: LogLevel, at logSource: LogSource) {
        guard enabled && logLevelAllowed(logLevel) else { return }

        switch executionMethod {
        case .synchronous(let lock):
            lock.lock() ; defer { lock.unlock() }
            logMessage(message(), with: logLevel, at: logSource)

        case .asynchronous(let queue):
            queue.async { self.logMessage(message(), with: logLevel, at: logSource) }
        }
    }

    // MARK: - Private - Log Message Helpers

    private func logLevelAllowed(_ logLevel: LogLevel) -> Bool {
        logLevels.contains(logLevel)
    }

    private func logMessage(_ message: String, with logLevel: LogLevel, at logSource: LogSource) {
        guard filters.allSatisfy({ $0.shouldInclude(message, level: logLevel) }) else { return }
        
        writers.forEach { $0.writeMessage(message, logLevel: logLevel, logSource: logSource) }
    }

    private func logMessage(_ message: LogMessage, with logLevel: LogLevel, at logSource: LogSource) {
        guard filters.allSatisfy({ $0.shouldInclude(message, level: logLevel) }) else { return }
        
        writers.forEach { $0.writeMessage(message, logLevel: logLevel, logSource: logSource) }
    }


    // MARK: - Private - No-Op Logger

    private final class NoOpLogger: Logger {
        init() {
            super.init(logLevels: .off, writers: [])
            enabled = false
        }

        override func logMessage(_ message: @escaping () -> String, with logLevel: LogLevel, at logSource: LogSource) {}
    }
}
