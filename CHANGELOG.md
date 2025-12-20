# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.8.0] - 2025-12-20

### Changed
- Updated dependencies to use published Hex packages:
  - `uzu_parser` ~> 0.6.0
  - `harmony` ~> 0.2.0
  - `real_book` ~> 0.1.0

### Fixed
- Grouped `set_param/3` function clauses to eliminate compiler warning
- Updated test assertions to use correct Strudel/SuperDirt parameter names:
  - `lpf` function sets `:cutoff` parameter
  - `hpf` function sets `:hcutoff` parameter

## [0.7.0] - 2025-12-07

### Changed
- Updated uzu_parser dependency to ~> 0.5.0 (NimbleParsec rewrite with source position tracking)
- Fixed mix.exs deprecation warning for preferred_cli_env

### Infrastructure
- CI matrix updated for valid Elixir/OTP combinations (1.17+OTP27, 1.18+OTP27, 1.19+OTP27/28)
- Added lefthook for pre-commit formatting
- Added CLAUDE.md project documentation

## [0.6.0] - 2025-11-27

### Added

#### Advanced Rhythm (Phase 6)
- **`euclid/3`** - Generate Euclidean rhythms using Bjorklund's algorithm (N pulses over M steps)
- **`euclid_rot/4`** - Euclidean rhythm with rotation offset for pattern variations
- **`swing/2`** - Add swing timing with 1/3 delay (convenience function)
- **`swing_by/3`** - Parameterized swing timing with custom delay amount

#### Infrastructure
- 10 new tests for rhythm functions (107 total, 100% passing)
- Bjorklund's algorithm implementation for optimal pulse distribution
- Swing timing delays events in second half of slices for shuffle feel

### Changed
- Updated version to 0.6.0
- Updated ROADMAP.md to mark Phase 6 as implemented

### Technical Details
- Euclidean rhythms filter events based on generated binary patterns
- Rotation offset shifts rhythm pattern for variations
- Swing modifies event timing within their time slices
- Based on [Strudel.js rhythm functions](https://strudel.cc/) and TidalCycles

## [0.5.0] - 2025-11-27

### Added

#### Advanced Combinators (Phase 5)
- **`jux_by/3`** - Parameterized jux with custom stereo separation amount (Strudel's `juxBy`)
- **`append/2`** - Append second pattern after first completes (Strudel's `append`)
- **`superimpose/2`** - Stack pattern with transformed version (Strudel's `superimpose`)
- **`off/3`** - Create delayed copy with transformation (Strudel's `off`)
- **`echo/3`** - Multiple delayed copies with decay (Strudel's `echo`)
- **`striate/2`** - Interleave time-sliced segments (Strudel's `striate`)
- **`chop/2`** - Slice pattern into pieces and rearrange (Strudel's `chop`)

#### Infrastructure
- 14 new tests for combinator functions (97 total, 100% passing)
- All combinators support method chaining
- Moved jux_by to Stereo section in documentation

### Changed
- Updated version to 0.5.0
- Updated ROADMAP.md to mark Phase 5 as implemented

### Technical Details
- All combinators are immediate transforms (modify events directly)
- Echo uses exponential gain decay for natural sound
- Striate and chop use time slicing for rhythmic variation
- Based on [Strudel.js combinators](https://strudel.cc/)

## [0.4.0] - 2025-11-26

### Added

#### Effects & Parameters (Phase 4)
- **`gain/2`** - Set volume/gain parameter for all events
- **`pan/2`** - Set stereo pan position (0.0 = left, 1.0 = right, 0.5 = center)
- **`speed/2`** - Set playback speed multiplier (1.0 = normal, 2.0 = double, 0.5 = half)
- **`cut/2`** - Set cut group for event stopping (same group stops previous events)
- **`room/2`** - Set reverb amount (0.0 = dry, 1.0 = wet)
- **`delay/2`** - Set delay amount (0.0 = dry, 1.0 = wet)
- **`lpf/2`** - Set low-pass filter cutoff frequency (0-20000 Hz)
- **`hpf/2`** - Set high-pass filter cutoff frequency (0-20000 Hz)

#### Infrastructure
- 18 new tests for parameter functions (83 total, 100% passing)
- All parameter functions modify event params map
- Support for chaining multiple effects

### Changed
- Updated version to 0.4.0
- Updated ROADMAP.md to mark Phase 4 as implemented

### Technical Details
- All parameter functions are immediate transforms (modify events directly)
- Parameters stored in event params map for downstream audio processing
- Validation: pan (0.0-1.0), speed (> 0.0), cut (≥ 0), room (0.0-1.0), delay (0.0-1.0), filters (0-20000 Hz)
- Based on [Strudel.js audio effects](https://strudel.cc/learn/effects/)

## [0.3.0] - 2025-11-26

### Added

#### Advanced Conditional Modifiers (Phase 3)
- **`first_of/3`** - Apply function on first of N cycles (Strudel's `firstOf`)
- **`last_of/3`** - Apply function on last of N cycles (Strudel's `lastOf`)
- **`when_fn/3`** - Apply function when condition function returns true (Strudel's `when`)
- **`chunk/3`** - Divide pattern into N parts, applying function to each part in turn per cycle
- **`chunk_back/3`** - Like chunk but cycles through parts in reverse order (TidalCycles `chunk'`)

#### Structural Filtering
- **`struct_fn/2`** - Apply rhythmic structure pattern (uses 'x' for events, '~' for rests)
- **`mask/2`** - Silence events based on binary pattern (0 or '~' = silence, others = keep)

#### Infrastructure
- Added transform types for Phase 3: `{:first_of, n, fun}`, `{:last_of, n, fun}`, `{:when_fn, condition_fn, fun}`, `{:chunk, n, fun}`, `{:chunk_back, n, fun}`
- Implemented `apply_transform/3` handlers for all new cycle-aware functions
- Comprehensive test coverage (65 tests, 100% passing)

### Changed
- Updated version to 0.3.0
- Updated ROADMAP.md to mark Phase 3 as implemented
- Enhanced typespec with new transform types

### Technical Details
- Cycle-aware conditional modifiers: `first_of`, `last_of`, `when_fn`, `chunk`, `chunk_back`
- Immediate structural filters: `struct_fn`, `mask`
- All functions maintain pattern properties and support chaining
- Based on [Strudel.js conditional modifiers](https://strudel.cc/learn/conditional-modifiers/)

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

[Unreleased]: https://github.com/rpmessner/uzu_pattern/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/rpmessner/uzu_pattern/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/rpmessner/uzu_pattern/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/rpmessner/uzu_pattern/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/rpmessner/uzu_pattern/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/rpmessner/uzu_pattern/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/rpmessner/uzu_pattern/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/rpmessner/uzu_pattern/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rpmessner/uzu_pattern/releases/tag/v0.1.0
