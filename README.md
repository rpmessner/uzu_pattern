# UzuPattern

Pattern orchestration library for Strudel.js-style transformations in Elixir.

UzuPattern provides pattern manipulation functions (`fast`, `slow`, `rev`, `stack`, `cat`, `every`, `jux`, etc.) that work with events from [UzuParser](https://github.com/rpmessner/uzu_parser). It enables TidalCycles/Strudel.js-style live coding patterns with method chaining and cycle-aware transformations.

## Installation

Add `uzu_pattern` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:uzu_pattern, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
alias UzuPattern.Pattern

# Create a pattern from mini-notation
pattern = Pattern.new("bd sd hh cp")

# Apply transformations
pattern
|> Pattern.fast(2)                      # Double speed
|> Pattern.rev()                        # Reverse
|> Pattern.every(4, &Pattern.slow(&1, 2)) # Slow every 4th cycle

# Get events for a specific cycle
events = Pattern.query(pattern, 0)
```

## Architecture

```
┌───────────────────────────────────────────────────────┐
│                    HarmonyServer                       │
│                   (coordination)                       │
│                                                        │
│  ┌─────────────────┐     ┌─────────────────┐          │
│  │   UzuParser     │────▶│   UzuPattern    │          │
│  │   (parsing)     │     │  (transforms)   │          │
│  │                 │     │   ◀── HERE      │          │
│  │ • parse/1       │     │ • fast/slow/rev │          │
│  │ • mini-notation │     │ • stack/cat     │          │
│  │ • [%Event{}]    │     │ • every/when    │          │
│  └─────────────────┘     └─────────────────┘          │
│                                                        │
└────────────────────────────┬──────────────────────────┘
                             │
                             ▼
                   ┌─────────────────┐
                   │    Waveform     │
                   │    (audio)      │
                   └─────────────────┘
```

## Features

### Time Modifiers

```elixir
Pattern.fast(pattern, 2)         # Speed up by factor
Pattern.slow(pattern, 2)         # Slow down by factor
Pattern.rev(pattern)             # Reverse pattern
Pattern.early(pattern, 0.25)     # Shift earlier (wraps)
Pattern.late(pattern, 0.25)      # Shift later (wraps)
Pattern.ply(pattern, 3)          # Repeat each event 3 times
Pattern.compress(pattern, 0.25, 0.75)  # Fit into time segment
Pattern.zoom(pattern, 0.25, 0.75)      # Extract and expand segment
Pattern.linger(pattern, 0.5)     # Repeat first half to fill cycle
```

### Combinators

```elixir
Pattern.stack([p1, p2, p3])  # Play simultaneously
Pattern.cat([p1, p2, p3])    # Play sequentially
Pattern.palindrome(pattern)  # Forward then backward
```

### Conditional (Cycle-Aware)

```elixir
Pattern.every(pattern, 4, &Pattern.rev/1)    # Reverse every 4th cycle
Pattern.sometimes(pattern, &Pattern.fast(&1, 2)) # 50% chance each cycle
Pattern.often(pattern, fun)       # 75% probability
Pattern.rarely(pattern, fun)      # 25% probability
Pattern.iter(pattern, 4)          # Rotate start position each cycle
Pattern.iter_back(pattern, 4)     # Rotate backwards each cycle
```

### Degradation

```elixir
Pattern.degrade(pattern)         # Remove ~50% of events
Pattern.degrade_by(pattern, 0.3) # Remove ~30% of events
```

### Stereo

```elixir
Pattern.jux(pattern, &Pattern.rev/1) # Left: original, Right: reversed
```

## Cycle-Aware Transformations

Some transformations (like `every`) depend on which cycle is being played. UzuPattern handles this through the `query/2` function:

```elixir
pattern = Pattern.new("bd sd") |> Pattern.every(2, &Pattern.rev/1)

Pattern.query(pattern, 0)  # Cycle 0: reversed (0 mod 2 == 0)
Pattern.query(pattern, 1)  # Cycle 1: normal
Pattern.query(pattern, 2)  # Cycle 2: reversed
Pattern.query(pattern, 3)  # Cycle 3: normal
```

## Integration with Waveform

UzuPattern provides a query function that Waveform can use for scheduling:

```elixir
# Create pattern with transforms
pattern =
  "bd sd hh cp"
  |> Pattern.new()
  |> Pattern.fast(2)
  |> Pattern.every(4, &Pattern.rev/1)

# Create query function for Waveform
query_fn = fn cycle -> UzuPattern.query(pattern, cycle) end

# Pass to Waveform's PatternScheduler
Waveform.PatternScheduler.schedule_pattern(:drums, query_fn)
```

## Examples

### Basic Drum Pattern

```elixir
"bd sd [hh hh] cp"
|> Pattern.new()
|> Pattern.fast(2)
|> Pattern.query(0)
```

### Layered Patterns

```elixir
kicks = Pattern.new("bd ~ bd ~")
snares = Pattern.new("~ sd ~ sd")
hats = Pattern.new("[hh hh hh hh]")

Pattern.stack([kicks, snares, hats])
```

### Evolving Pattern

```elixir
"bd sd hh cp"
|> Pattern.new()
|> Pattern.every(4, &Pattern.rev/1)
|> Pattern.every(8, &Pattern.fast(&1, 2))
|> Pattern.sometimes(&Pattern.degrade/1)
```

### Stereo Spread

```elixir
"arpy:0 arpy:1 arpy:2 arpy:3"
|> Pattern.new()
|> Pattern.jux(&Pattern.rev/1)
```

### Rhythmic Variations (Phase 2)

```elixir
# Drum roll effect with ply
"bd sd"
|> Pattern.new()
|> Pattern.ply(4)

# Compress pattern into middle of cycle
"bd sd hh cp"
|> Pattern.new()
|> Pattern.compress(0.25, 0.75)

# Zoom into second half
"bd sd hh cp"
|> Pattern.new()
|> Pattern.zoom(0.5, 1.0)

# Rotating pattern (evolves each cycle)
"bd sd hh cp"
|> Pattern.new()
|> Pattern.iter(4)

# Repeat first quarter
"bd sd hh cp"
|> Pattern.new()
|> Pattern.linger(0.25)
```

## Documentation

- **[ROADMAP.md](ROADMAP.md)** - Feature roadmap and Strudel.js parity tracking
- **[HANDOFF.md](HANDOFF.md)** - Architecture and integration guide

## Related Projects

- [UzuParser](https://github.com/rpmessner/uzu_parser) - Mini-notation parser
- [Waveform](https://github.com/rpmessner/waveform) - Audio playback via SuperDirt/MIDI
- [kino_harmony](https://github.com/rpmessner/kino_harmony) - Livebook live coding
- [harmony_server](https://github.com/rpmessner/harmony_server) - API gateway

## License

MIT License - see [LICENSE](LICENSE) for details.
