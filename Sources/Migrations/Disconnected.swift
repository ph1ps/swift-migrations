//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// Copied from the Synchronization module's `Disconnected` (SE-0538), which
// isn't available on this package's deployment targets. Modified: dropped
// availability and stdlib-only attributes, made internal, removed
// `exchange(newValue:)` and `withValue(body:)`. Replace with
// `Synchronization.Disconnected` once the deployment targets allow it.
//
// Source: https://github.com/swiftlang/swift/blob/1f6a97e43627e422337535c13cea1ebcb7b9845c/stdlib/public/Synchronization/Disconnected.swift

struct Disconnected<Value: ~Copyable>: ~Copyable, Sendable {
  // This is safe since the only values assigned are sent into `Disconnected`.
  nonisolated(unsafe) var _value: Value

  init(_ value: consuming sending Value) {
    self._value = value
  }

  consuming func consume() -> sending Value {
    let value = consume _value
    return value
  }
}
