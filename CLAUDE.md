# CLAUDE.md - UzuPattern

## Project Overview

**uzu_pattern** is a pattern transformation library for Elixir live coding. It wraps UzuParser and adds Strudel.js-style transformations like `fast`, `slow`, `rev`, `every`, etc.

**Purpose:** Pattern orchestration and transformation on top of parsed mini-notation.

**Version:** 0.6.0

**Status:** Stable - comprehensive transformation library

## Architecture

```
Pattern String → UzuParser → UzuPattern → Transformed Events
    "bd sd"    →  events   → .fast(2)   → faster events
```

## Key Modules

| Module | Purpose |
|--------|---------|
| `UzuPattern` | Main public API |
| `UzuPattern.Pattern` | Pattern struct and transformations |

## Quick Reference

```elixir
# Create pattern from mini-notation
pattern = UzuPattern.new("bd sd hh cp")

# Apply transformations
pattern
|> UzuPattern.Pattern.fast(2)
|> UzuPattern.Pattern.every(4, &UzuPattern.Pattern.rev/1)

# Query events for a specific cycle
events = UzuPattern.query(pattern, cycle_number)
```

## Available Transformations

### Time Modifiers
- `fast/2`, `slow/2` - Speed up/slow down
- `rev/1` - Reverse pattern
- `early/2`, `late/2` - Shift timing
- `ply/2` - Repeat each event N times
- `compress/3`, `zoom/3` - Time segment manipulation

### Combinators
- `stack/1` - Play patterns simultaneously
- `cat/1` - Play patterns sequentially
- `palindrome/1` - Forward then backward

### Conditional
- `every/3` - Apply function every N cycles
- `sometimes/2`, `often/2`, `rarely/2` - Probability-based
- `first_of/3`, `last_of/3` - Apply on specific cycles

### Effects
- `gain/2`, `pan/2`, `speed/2` - Audio parameters
- `lpf/2`, `hpf/2` - Filter parameters
- `room/2`, `delay/2` - Effect sends

### Advanced
- `jux/2`, `jux_by/3` - Stereo manipulation
- `striate/2`, `chop/2` - Sample slicing
- `euclid/3`, `swing/2` - Rhythm generation

## Commands

```bash
mix test          # Run tests
mix compile       # Compile
```

## Dependencies

- `uzu_parser` - Pattern mini-notation parsing

## Related Projects

- **uzu_parser** - Pattern parsing (dependency)
- **waveform** - Audio scheduling via PatternScheduler
