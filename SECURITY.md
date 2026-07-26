# Security Policy

## Supported versions

MESA-iOS is pre-1.0. Only the latest released version receives fixes.

| Version | Supported |
|:---|:---|
| latest release | ✅ |
| older releases | ❌ |

## Reporting a vulnerability

Please report suspected vulnerabilities privately via
[GitHub Security Advisories](https://github.com/jkjamies/MESA-iOS/security/advisories/new)
rather than opening a public issue.

Include the affected library and version, what an attacker can achieve, and a reproduction if
you have one. You can expect an initial response within 7 days.

## Scope

MESA-iOS is a UI-architecture library. It performs no networking, no cryptography, and no
authentication, and it has no third-party dependencies. The most likely findings are therefore
memory-safety or data-race issues in the concurrency primitives (`Strata`, `TrapezioTaskBag`,
`ContinuationRegistry`) rather than classic vulnerabilities — those are in scope and welcome.

Out of scope:

- Issues in the `Counter` sample app that do not also affect the libraries. The sample is
  illustrative and is not intended for production use.
- Anything requiring push access to `main` (for example, the `VERSION` file feeding the release
  workflow).

## Notes for adopters

- `TrapezioScreen` conforms to `Codable`. If you decode a screen from a URL or any other
  untrusted source, validate its parameters before acting on them — the library does not do this
  for you, and there is currently no built-in deep-link entry point.
- `TrapezioNavigation` logs screen descriptions and result keys through `os.Logger`. Dynamic
  strings default to `.private` in the unified logging system, so those values are redacted in
  persisted logs. Do not change them to `.public`, and do not substitute `print`, without
  considering what your route parameters contain.
