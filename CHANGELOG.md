# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2025-11-26

### Added

#### Extended Time Modifiers (Phase 2)
- **`ply/2`** - Repeat each event N times within its duration for drum rolls and stutters
- **`compress/3`** - Fit pattern into time segment [start, end] creating rhythmic gaps
- **`zoom/3`** - Extract and expand time segment (inverse of compress)
- **`linger/2`** - Repeat fraction of pattern to fill cycle (also known as fastgap in Strudel)

#### Conditional Modifiers (Cycle-Aware)
- **`iter/2`** - Rotate pattern start position each cycle for evolving patterns
- **`iter_back/2`** - Rotate backwards each cycle (TidalCycles iter')

#### Infrastructure
- Added transform types `{:iter, n}` and `{:iter_back, n}` to Pattern typespec
- Implemented `apply_transform/3` handlers for cycle-aware iter functions
- GitHub Actions CI workflow with test matrix (Elixir 1.14-1.16, OTP 25-26)
- Code quality tools: Credo, Dialyzer, ExCoveralls
- Comprehensive test coverage (52 tests, 100% passing)

#### Documentation
- Added Phase 2 examples section to README showcasing new capabilities
- Updated ROADMAP.md with Phase 2 completion status
- Created CHANGELOG.md for version tracking
- Created CONTRIBUTING.md with contribution guidelines
- Enhanced ExDoc configuration with module grouping

### Changed
- Updated version to 0.2.0
- Updated Elixir requirement to ~> 1.14 (from ~> 1.17) for broader compatibility
- Enhanced package description with new function names
- Updated ROADMAP.md to mark Phase 2 as implemented

### Technical Details
- All new functions maintain event properties (sound, sample, params)
- Immediate transforms modify events directly: `ply`, `compress`, `zoom`, `linger`
- Deferred transforms resolved at query time: `iter`, `iter_back`
- Based on [Strudel.js time modifiers](https://strudel.cc/learn/time-modifiers/)

## [0.1.0] - 2025-11-26

### Added

#### Core Infrastructure
- `Pattern` struct with events and transforms
- `new/1` - Create pattern from mini-notation string
- `from_events/1` - Create pattern from event list
- `query/2` - Get events for a specific cycle (resolves cycle-aware transforms)
- `events/1` - Extract raw events without resolution

#### Time Modifiers
- `fast/2` - Speed up pattern by factor
- `slow/2` - Slow down pattern by factor
- `rev/1` - Reverse pattern
- `early/2` - Shift pattern earlier (wraps around)
- `late/2` - Shift pattern later (wraps around)

#### Combinators
- `stack/1` - Play patterns simultaneously
- `cat/1` - Play patterns sequentially
- `palindrome/1` - Create forward then backward pattern

#### Conditional Modifiers (Cycle-Aware)
- `every/3` - Apply function every N cycles
- `sometimes_by/3` - Apply with custom probability
- `sometimes/2` - Apply with 50% probability
- `often/2` - Apply with 75% probability
- `rarely/2` - Apply with 25% probability

#### Degradation
- `degrade/1` - Remove ~50% of events randomly
- `degrade_by/2` - Remove events with custom probability

#### Stereo
- `jux/2` - Apply function to right channel (stereo spread)

#### Documentation
- Comprehensive README with examples
- ROADMAP tracking Strudel.js feature parity
- HANDOFF guide for architecture and integration
- ExDoc documentation generation

[Unreleased]: https://github.com/rpmessner/uzu_pattern/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/rpmessner/uzu_pattern/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rpmessner/uzu_pattern/releases/tag/v0.1.0
