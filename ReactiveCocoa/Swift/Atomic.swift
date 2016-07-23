//
//  Atomic.swift
//  ReactiveCocoa
//
//  Created by Justin Spahr-Summers on 2014-06-10.
//  Copyright (c) 2014 GitHub. All rights reserved.
//

import Foundation

internal protocol MutexType: class {
	func lock()
	func unlock()
}

extension RecursiveLock: MutexType {}

final class PosixThreadMutex: MutexType {
	private var _mutex = pthread_mutex_t()

	init() {
		let result = pthread_mutex_init(&_mutex, nil)
		precondition(result == 0, "Failed to initialize mutex with error \(result).")
	}

	deinit {
		let result = pthread_mutex_destroy(&_mutex)
		precondition(result == 0, "Failed to destroy mutex with error \(result).")
	}

	func lock() {
		let result = pthread_mutex_lock(&_mutex)
		precondition(result == 0, "Failed to lock \(self) with error \(result).")
	}

	func unlock() {
		let result = pthread_mutex_unlock(&_mutex)
		precondition(result == 0, "Failed to unlock \(self) with error \(result).")
	}
}

/// An atomic variable.
public final class Atomic<Value> {
	private var _mutex: MutexType
	private var _value: Value
	
	/// Atomically get or set the value of the variable.
	public var value: Value {
		get {
			return withValue { $0 }
		}
	
		set(newValue) {
			swap(newValue)
		}
	}
	
	/// Initialize the variable with the given initial value.
	/// 
	/// - parameters:
	///   - value: Initial value for `self`.
	public convenience init(_ value: Value) {
		self.init(value, mutex: PosixThreadMutex())
	}

	/// Initializes the variable with the given initial value.
	internal init(_ value: Value, mutex: MutexType) {
		_value = value
		_mutex = mutex
	}

	private func lock() {
		_mutex.lock()
	}
	
	private func unlock() {
		_mutex.unlock()
	}
	
	/// Atomically replace the contents of the variable.
	///
	/// - parameters:
	///   - newValue: A new value for the variable.
	///
	/// - returns: The old value.
	@discardableResult
	public func swap(_ newValue: Value) -> Value {
		return modify { $0 = newValue }
	}

	/// Atomically modify the variable.
	///
	/// - parameters:
	///   - action: A closure that takes the current value.
	///
	/// - returns: The old value.
	@discardableResult
	public func modify(_ action: @noescape (inout Value) throws -> Void) rethrows -> Value {
		return try modify(action, completion: nil)
	}

	/// Atomically modifies the variable.
	///
	/// - parameters:
	///   - action: A closure that takes the current value.
	///   - completion: An optional closure that would be executed after the
	///                 returned value from `action` has been written back.
	///
	/// Returns the old value.
	public func modify(_ action: @noescape (inout Value) throws -> Void, completion: (@noescape (Value) -> ())?) rethrows -> Value {
		return try withValue { value in
			try action(&_value)
			completion?(_value)
			return value
		}
	}
	
	/// Atomically perform an arbitrary action using the current value of the
	/// variable.
	///
	/// - parameters:
	///   - action: A closure that takes the current value.
	///
	/// - returns: The result of the action.
	@discardableResult
	public func withValue<Result>(_ action: @noescape (Value) throws -> Result) rethrows -> Result {
		lock()
		defer { unlock() }

		return try action(_value)
	}
}
