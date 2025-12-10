# CLAUDE.md - UzuPattern

## Project Overview

**uzu_pattern** is a pattern transformation library for Elixir live coding. It interprets AST from UzuParser and provides Strudel.js-style transformations like `fast`, `slow`, `rev`, `every`, etc.

**Purpose:** Pattern interpretation, orchestration, and transformation.

**Version:** 0.7.0

**Status:** Stable - comprehensive transformation library with query-based patterns

## Architecture

```
Pattern String → UzuParser.Grammar → AST → Interpreter → Pattern → query(cycle) → [Event]
    "bd sd"    →      parse/1      → AST →  interpret  → Pattern →   query(0)   → events
```

The pattern is a query function `(cycle -> [Event])` that enables:
- Lazy evaluation (only compute events when needed)
- Cycle-aware operations (alternation, every, etc.)
- Composable transformations

## Key Modules

| Module | Purpose |
|--------|---------|
| `UzuPattern` | Main public API |
| `UzuPattern.Pattern` | Query-based pattern struct and 50+ transformations |
| `UzuPattern.Interpreter` | AST → Pattern conversion (moved from uzu_parser) |
| `UzuPattern.Event` | Event struct with timing and params (moved from uzu_parser) |
| `UzuPattern.Euclidean` | Bjorklund's algorithm for rhythms (moved from uzu_parser) |

## Quick Reference

```elixir
# Create pattern from mini-notation
pattern = UzuPattern.parse("bd sd hh cp")

# Apply transformations
pattern
|> UzuPattern.Pattern.fast(2)
|> UzuPattern.Pattern.every(4, &UzuPattern.Pattern.rev/1)

# Query events for a specific cycle
events = UzuPattern.Pattern.query(pattern, 0)
# => [%Event{sound: "bd", time: 0.0, duration: 0.125}, ...]

# Different cycles may return different events (for alternation, every, etc.)
events_cycle_1 = UzuPattern.Pattern.query(pattern, 1)
```

## Available Transformations

### Time Modifiers
- `fast/2`, `slow/2` - Speed up/slow down
- `rev/1` - Reverse pattern
- `early/2`, `late/2` - Shift timing
- `ply/2` - Repeat each event N times
- `compress/3`, `zoom/3` - Time segment manipulation
- `linger/2` - Repeat first portion

### Combinators
- `stack/1` - Play patterns simultaneously (polyphony)
- `fastcat/1`, `slowcat/1` - Sequence patterns
- `append/2` - Append patterns
- `palindrome/1` - Forward then backward

### Conditional
- `every/3`, `every/4` - Apply function every N cycles
- `sometimes/2`, `often/2`, `rarely/2` - Probability-based
- `first_of/3`, `last_of/3` - Apply on specific cycles
- `when_fn/3` - Apply when condition is true
- `chunk/3`, `chunk_back/3` - Apply to rotating pattern sections

### Structure
- `mask/2` - Silence events based on mask pattern
- `struct_fn/2` - Apply rhythmic structure
- `degrade/1`, `degrade_by/2` - Random event removal

### Effects (Parameter Setting)
- `gain/2`, `pan/2`, `speed/2` - Audio parameters
- `lpf/2`, `hpf/2` - Filter parameters
- `room/2`, `delay/2` - Effect sends
- `cut/2` - Voice cutoff groups
- `set_param/3` - Generic parameter setter

### Advanced
- `jux/2`, `jux_by/3` - Stereo manipulation
- `superimpose/2` - Layer with transformed copy
- `off/3` - Superimpose with time offset
- `echo/4` - Rhythmic fading echoes
- `striate/2`, `chop/2` - Sample slicing
- `iter/2`, `iter_back/2` - Rotating pattern start

### Rhythm
- `euclid/3`, `euclid_rot/4` - Euclidean rhythms
- `swing/2`, `swing_by/3` - Swing timing

## Event Structure

```elixir
%UzuPattern.Event{
  sound: "bd",           # Sound/sample name
  sample: 0,             # Sample variant number
  time: 0.0,             # Position in cycle [0, 1)
  duration: 0.25,        # Duration as fraction of cycle
  params: %{gain: 0.8},  # Effect parameters
  source_start: 0,       # Position in source string (for highlighting)
  source_end: 2
}
```

## Commands

```bash
mix test          # Run tests (270+ tests)
mix compile       # Compile
```

## Dependencies

- `uzu_parser` - Pattern mini-notation parsing (AST only)

## Related Projects

- **uzu_parser** - Pattern parsing (provides AST)
- **undertow_server** - Server-side pattern evaluation
- **waveform** - Audio scheduling via PatternScheduler
- **waveform_js** - Web Audio playback
