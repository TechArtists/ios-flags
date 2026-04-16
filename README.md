# TAFlags

`TAFlags` is a strongly typed feature flag package for Swift apps. It gives you typed flag declarations, immediate default values before the first remote fetch completes, Combine publishers for updates, and a small adaptor layer so the backend stays swappable.

The package currently ships with:

- `TAFlags`: the core flag system
- `TAFlagsAdaptorFirebaseRemoteConfig`: a Firebase Remote Config adaptor

## Highlights

- Strongly typed flag declarations
- Concise key-based API for reading and observing flags
- Immediate default values before bootstrap completes
- Async bootstrap and manual refresh APIs
- Provider-agnostic core API via `TAFlagsAdaptor`
- Built-in Firebase Remote Config support

## Requirements

- iOS 16+
- macOS 13+

## Supported Value Types

- `Bool`
- `String`
- `Int`
- `Double`
- `Float`
- `Data`
- `RawRepresentable` types backed by `String`

JSON-backed `Codable` values are also supported through `TAFlag.codable(...)`.

## Value Flow

Each flag moves through two representations:

- Provider value: the raw backend value returned by the adaptor as `TAFlagRawValue`
- Published value: the typed Swift value exposed by `TAFlag<Value>` and emitted through its publisher

Examples:

- Provider value `"true"` becomes published value `true`
- Provider value `"variant_b"` becomes published value `.variantB`
- Provider value JSON data becomes a published `Codable` model

## Quick Start

Define your flags once, register them with `TAFlags`, and start the system during app launch.

```swift
import TAFlags

enum OnboardingVariant: String {
    case control
    case streamlined
}

extension TAFlags.Keys {
    static let newPaywallEnabled = TAFlag<Bool>(
        "new_paywall_enabled",
        default: false
    )

    static let onboardingVariant = TAFlag<OnboardingVariant>(
        "onboarding_variant",
        default: .control
    )
}
```

```swift
import TAFlags
import TAFlagsAdaptorFirebaseRemoteConfig

@MainActor
let flags = TAFlags(
    config: .init(
        adaptor: FirebaseRemoteConfigFlagsAdaptor(),
        startupPolicy: .publishCurrentThenFetch,
        registeredFlags: [
            TAFlags.Keys.newPaywallEnabled,
            TAFlags.Keys.onboardingVariant
        ]
    )
)

Task { @MainActor in
    await flags.start()
}
```

By default, `start()` does three things:

1. Registers all default values with the adaptor.
2. Publishes any currently active values from the provider.
3. Performs an initial fetch and activation cycle.

This default behavior is controlled by `startupPolicy`, which defaults to
`.publishCurrentThenFetch`.

Terminology used below:

- `provider` means the backend/adaptor that supplies raw flag values, such as `FirebaseRemoteConfigFlagsAdaptor`
- `currently active provider values` means the values the backend would return right now, before doing a new fetch
- `publish` means decoding those raw backend values and sending the typed results into each flag's `publisher`, so app code and subscribers see the update

Available startup policies:

- `.publishCurrentThenFetch`: publish currently active provider values, then fetch fresh ones
- `.publishCurrentOnly`: publish currently active provider values and skip the initial fetch
- `.fetchOnly`: skip publishing currently active provider values and only perform the initial fetch

With Firebase Remote Config, "currently active" means the values that have already been
activated locally. Those may be:

- a previously activated remote value from an earlier app launch
- or the registered default value when no remote override has been activated yet

The policies therefore behave like this:

- `.publishCurrentThenFetch`
  1. Read Firebase's current active values.
  2. Publish those values into `TAFlags`.
  3. Call `fetchAndActivate()`.
  4. Publish any keys that changed after activation.
- `.publishCurrentOnly`
  1. Read Firebase's current active values.
  2. Publish those values into `TAFlags`.
  3. Stop.
- `.fetchOnly`
  1. Do not first read Firebase's current active values.
  2. Call `fetchAndActivate()`.
  3. Publish any keys that changed after activation.

In other words:

- Firebase `active value` = backend-side active value
- `TAFlags` `publish` = app-side update to a flag's `CurrentValueSubject`

You can safely read defaults before startup completes:

```swift
let isEnabled = flags[TAFlags.Keys.newPaywallEnabled]
```

## Reading Values

Read the current value with either subscript syntax or `value(...)`:

```swift
let isEnabled = flags[TAFlags.Keys.newPaywallEnabled]
let variant = flags.value(TAFlags.Keys.onboardingVariant)
```

## Observing Values

Subscribe to changes with Combine:

```swift
let cancellable = flags.publisher(TAFlags.Keys.onboardingVariant)
    .sink { variant in
        print("Updated onboarding variant:", variant)
    }
```

Subscribers receive the current value immediately because each flag is backed by a `CurrentValueSubject`.

## JSON Flags

Use `TAFlag.codable(...)` when a flag value is stored as JSON.

```swift
struct PaywallConfig: Codable, Equatable {
    let title: String
    let showTrial: Bool
}

extension TAFlags.Keys {
    static let paywallConfig = TAFlag<PaywallConfig>.codable(
        "paywall_config",
        default: .init(title: "Default", showTrial: false)
    )
}
```

`TAFlag.codable(...)` decodes from the provider's raw data and registers the default value as
JSON-encoded data.

## Bootstrap State

`TAFlags` exposes a `bootstrapState` you can use to drive launch UX:

- `.idle`
- `.bootstrapping`
- `.bootstrapped`
- `.failed(String)`

It also exposes `hasCompletedInitialBootstrap` for simple gating.

## Refreshing Flags

You can trigger a manual refresh at any time:

```swift
await flags.refresh()
```

If the flag system has not started yet, `refresh()` will start it first.

## Firebase Remote Config Adaptor

`FirebaseRemoteConfigFlagsAdaptor` wraps Firebase Remote Config and listens for runtime config updates.

```swift
let adaptor = FirebaseRemoteConfigFlagsAdaptor(
    configuration: .init(
        minimumFetchInterval: 60,
        fetchTimeout: 15
    )
)
```

Configuration options:

- `minimumFetchInterval`: defaults to `0` seconds in `#if DEBUG` builds and 12 hours otherwise
- `fetchTimeout`: defaults to 60 seconds

The adaptor:

- registers default values with Firebase Remote Config
- fetches and activates remote values on demand
- listens for live config updates
- only republishes keys that are registered with `TAFlags`

## Custom Adaptors

To plug in a different backend, implement `TAFlagsAdaptor`:

```swift
import Combine
import Foundation
import TAFlags

final class MyFlagsAdaptor: TAFlagsAdaptor, @unchecked Sendable {
    var updatesPublisher: AnyPublisher<Set<String>, Never> {
        updatesSubject.eraseToAnyPublisher()
    }

    private let updatesSubject = PassthroughSubject<Set<String>, Never>()

    func start() async throws {
        // Set up the client.
    }

    func register(defaults: [String: NSObject]) {
        // Store or forward defaults to the provider.
    }

    func rawValue(forKey key: String) -> TAFlagRawValue {
        // Return the provider's current value for this key.
        TAFlagRawValue(string: "")
    }

    func fetchAndActivate() async throws -> Set<String> {
        // Fetch new values and return the keys that changed.
        []
    }
}
```

The core package only requires five capabilities from an adaptor:

- startup
- default registration
- reading the current raw value for a key
- fetching and activating remote values while reporting changed keys
- publishing runtime updates for changed keys

## Decoding Behavior

If a remote value cannot be decoded into a flag's type, `TAFlags` logs the failure and keeps the last valid value instead of overwriting it with bad data.
