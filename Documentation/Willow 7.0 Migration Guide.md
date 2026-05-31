# Willow 7.0 Migration Guide

Willow 7.0 is the latest major release of Willow, a powerful, yet lightweight logging library for iOS, macOS, tvOS and watchOS written in Swift.
As a major release, following Semantic Versioning conventions, 7.0 introduces a small set of API-breaking changes that one should be aware of.

This guide is provided in order to ease the transition of existing applications using Willow 6.x to the latest APIs.

## Requirements

Willow 7.0 requires Xcode 16.0+ and Swift 6.0+. The package, the Xcode framework targets, and the CocoaPods podspec all build under Swift 6 language mode with strict concurrency checking enabled.

If you need to stay on Swift 5, use the latest tagged 6.x release.

---

## Why 7.0?

Willow 7.0 resolves [issue #75](https://github.com/Nike-Inc/Willow/issues/75) by making the library cleanly compatible with Swift 6 strict concurrency checking. The migration touches every public protocol and closure boundary, which is why a major-version bump is warranted even though the behavioral contract of the library — synchronous-or-asynchronous, lock-or-queue-serialized message dispatch, and the `LogSource` metadata that 6.x's `add-log-location-metadata` change threads through every writer / modifier callback — is unchanged.

---

## Breaking API Changes

### `LogMessage.attributes` is now `[String: any Sendable]`

The single source-breaking change for most callers is on the `LogMessage` protocol:

```swift
// Willow 6.x
public protocol LogMessage {
    var name: String { get }
    var attributes: [String: Any] { get }
}

// Willow 7.0
public protocol LogMessage: Sendable {
    var name: String { get }
    var attributes: [String: any Sendable] { get }
}
```

Every conformer must update its declared `attributes` return type to `[String: any Sendable]` and ensure every value it stores in the dictionary is itself `Sendable`. Most values you already store there (`String`, `Int`, `Double`, `URL`, `Date`, etc.) are already `Sendable` and the change is mechanical.

If you previously stored non-Sendable values (custom reference types, ad-hoc `NSError` instances, etc.), you have two paths:

1. **Preferred** — Convert at the call site to a Sendable representation (e.g. capture the error's `localizedDescription` and `code` as `String` / `Int`).
2. **Escape hatch** — If you cannot change the value type, declare your conformer `@unchecked Sendable` and ensure the value is effectively immutable. The bundled `Example/Frameworks/{Database,WebServices}/Logger.swift` enums take this path because they hold `Error` associated values, which `any Error` cannot prove `Sendable` for.

Conformers that read the attribute values still use `as?` to recover concrete types; the existential cast site does not change:

```swift
if let responseCode = logMessage.attributes["response_code"] as? Int {
    // ...
}
```

### Protocols now refine `Sendable`

The following protocols now inherit from `Sendable`:

- `LogMessage`
- `LogWriter`
- `LogModifierWriter`
- `LogModifier`
- `LogFilter`

Custom conformers must satisfy the `Sendable` contract. For struct conformers whose stored properties are all `Sendable`, conformance is automatic. For class conformers that hold mutable state guarded by an external synchronization mechanism (such as Willow's own `executionMethod`), declare the type `@unchecked Sendable`:

```swift
final class MyWriter: LogWriter, @unchecked Sendable {
    private var buffer: [String] = []

    func writeMessage(_ message: String, logLevel: LogLevel, logSource: LogSource) {
        // serialized through Logger.executionMethod
        buffer.append(message)
    }

    func writeMessage(_ message: LogMessage, logLevel: LogLevel, logSource: LogSource) {
        buffer.append("\(message.name)")
    }
}
```

`LogSource` itself is also `Sendable` (it stores only `StaticString` and `UInt`), so the existing `(message, logLevel, logSource)` writer / modifier callback signatures cross queue boundaries safely with no changes required on your side.

### Logging APIs require `@Sendable` closures

Every `@escaping` and `@autoclosure` closure parameter on `Logger`'s public logging APIs (`debug`, `info`, `event`, `warn`, `error`, `debugMessage`, …, `logMessage`) now carries `@Sendable`. The `file` / `function` / `line` / `column` parameters from the 6.x location-metadata APIs are unchanged. In most call sites this requires no change, because the closures capture only `Sendable` values:

```swift
log.eventMessage { "Request completed with status \(response.statusCode)" } // Still works
```

Call sites that previously captured non-Sendable values (typically `self` of a non-Sendable type, or a class instance that isn't `Sendable`) will now fail to compile. The fix is to capture the specific Sendable values you need into local constants before the closure:

```swift
// Willow 6.x — captures self
log.debugMessage { "id=\(self.requestID)" }

// Willow 7.0 — capture only the Sendable String you need
let requestID = self.requestID
log.debugMessage { "id=\(requestID)" }
```

If your enclosing type is itself `Sendable` (a value type with Sendable members, an actor, or `@unchecked Sendable`), this section requires no changes.

### `Logger` is `@unchecked Sendable`, not an `actor`

`Logger` remains an `open class`. It is now declared `@unchecked Sendable` with a class-level doc comment that documents the contract: all mutable state (`logLevels`, `filters`, and any subclass-added storage) must be mutated only through `executionMethod.perform`. Subclassers MUST preserve this invariant for any new stored properties they introduce.

`Logger.enabled` remains a deliberately lock-free `Bool` whose read/write is not synchronized through `executionMethod`. This is preserved verbatim from prior versions and is intentionally out of scope for the 7.0 migration; tightening the contract (for example by routing through `perform`, or by replacing the property with an `OSAllocatedUnfairLock`-backed value) is tracked as a follow-up.

### Module-level `Logger` globals need a Swift 6 isolation decision

If you previously declared a module-level mutable logger:

```swift
public var log: Logger = .disabled
```

Swift 6 will flag this as a non-isolated global variable. You have three options, in roughly decreasing order of convenience:

1. **`nonisolated(unsafe)`** — Recommended for the assigned-once-at-launch, read-everywhere pattern that the bundled `Example/` targets use. Document the contract in a comment.
   ```swift
   nonisolated(unsafe) public var log: Logger = .disabled
   ```
2. **`@MainActor`** — If your logger is configured and read only from the main thread.
3. **A `let` accessor** — Build the logger eagerly and hand it out via a `let` global or via a function.

The bundled `Example/` targets use option (1); see `Example/iOS Example/WillowConfiguration.swift` and the framework-level `Example/Frameworks/*/Logger.swift` files.

---

## Behavioral Changes

There are no intentional behavioral changes in Willow 7.0. The thread-safety contract, the autoclosure-based logging ergonomics, the `open class` extension story, the `ExecutionMethod` lock/queue dispatch semantics, and the `LogSource` location-metadata pipeline introduced in 6.x all remain identical.

---

## Build Configuration

- `Package.swift` now requires `// swift-tools-version:6.0` and pins the library and test targets to Swift 6 language mode via `.swiftSettings([.swiftLanguageMode(.v6)])`.
- `Willow.podspec` declares `s.swift_versions = ["6.0"]`.
- `Willow.xcodeproj` sets `SWIFT_VERSION = 6.0` on every shipped scheme (iOS, macOS, tvOS, watchOS).

If your downstream project is still on Swift 5, Willow 6.x remains available on the previous tagged release line and continues to satisfy that integration story.
