# UzuPattern

Pattern library for TidalCycles/Strudel-style live coding in Elixir.

UzuPattern provides a query-based pattern system with transformations (`fast`, `slow`, `rev`, `every`, `jux`, etc.), signal patterns for modulation, and effect parameters. It integrates mini-notation parsing from [UzuParser](https://github.com/rpmessner/uzu_parser).

## Installation

```elixir
def deps do
  [
    {:uzu_pattern, "~> 0.7.0"}
  ]
end
```

## Quick Start

```elixir
# Parse mini-notation into a pattern
pattern = UzuPattern.parse("bd sd hh cp")

# Apply transformations
pattern
|> Pattern.fast(2)
|> Pattern.rev()
|> Pattern.every(4, &Pattern.slow(&1, 2))

# Query events for a specific cycle
events = Pattern.query(pattern, 0)
```

## Core Concept: Query Functions

Patterns are query functions, not static event lists. This enables cycle-aware transformations:

```elixir
pattern = UzuPattern.parse("bd sd") |> Pattern.every(2, &Pattern.rev/1)

Pattern.query(pattern, 0)  # Cycle 0: reversed
Pattern.query(pattern, 1)  # Cycle 1: normal
Pattern.query(pattern, 2)  # Cycle 2: reversed
```

## Submodules

Functions are organized into logical groups:

- **Pattern.Time** - `fast`, `slow`, `early`, `late`, `ply`, `compress`, `zoom`, `linger`
- **Pattern.Structure** - `rev`, `palindrome`, `mask`, `degrade`, `jux`, `superimpose`, `off`, `echo`, `striate`, `chop`
- **Pattern.Conditional** - `every`, `sometimes`, `often`, `rarely`, `iter`, `first_of`, `last_of`, `when_fn`, `chunk`
- **Pattern.Effects** - `gain`, `pan`, `speed`, `cut`, `room`, `delay`, `lpf`, `hpf`
- **Pattern.Rhythm** - `euclid`, `euclid_rot`, `swing`, `swing_by`
- **Pattern.Signal** - `sine`, `saw`, `tri`, `square`, `rand`, `range`, `segment`

## Signal Patterns

Signals provide continuous values for modulating parameters:

```elixir
# Modulate filter cutoff with sine wave (200-2000 Hz)
UzuPattern.parse("bd sd hh cp")
|> Pattern.lpf(Pattern.sine() |> Pattern.range(200, 2000))

# Random gain per cycle
UzuPattern.parse("bd sd")
|> Pattern.gain(Pattern.rand() |> Pattern.range(0.5, 1.0))

# Stereo panning sweep
UzuPattern.parse("arpy:0 arpy:1 arpy:2 arpy:3")
|> Pattern.pan(Pattern.tri() |> Pattern.range(-1, 1))
```

Available waveforms: `sine`, `saw`, `isaw`, `tri`, `square`, `rand`, `irand`

## Effects

All effects accept static values or signal patterns:

```elixir
pattern
|> Pattern.gain(0.8)           # Static gain
|> Pattern.pan(-0.5)           # Static pan (left)
|> Pattern.lpf(2000)           # Static filter
|> Pattern.lpf(Pattern.sine() |> Pattern.range(200, 2000))  # Modulated filter
```

## Time Transformations

```elixir
Pattern.fast(pattern, 2)              # Double speed
Pattern.slow(pattern, 2)              # Half speed
Pattern.rev(pattern)                  # Reverse
Pattern.early(pattern, 0.25)          # Shift earlier
Pattern.late(pattern, 0.25)           # Shift later
Pattern.ply(pattern, 3)               # Repeat each event
Pattern.compress(pattern, 0.25, 0.75) # Fit into time window
Pattern.zoom(pattern, 0.5, 1.0)       # Extract and expand
Pattern.linger(pattern, 0.25)         # Loop first portion
```

## Structure

```elixir
Pattern.stack([p1, p2, p3])     # Layer patterns
Pattern.cat([p1, p2, p3])       # Sequence patterns
Pattern.palindrome(pattern)     # Forward then backward
Pattern.jux(pattern, &Pattern.rev/1)  # Stereo split
Pattern.superimpose(pattern, &Pattern.fast(&1, 2))  # Layer with transform
Pattern.off(pattern, 0.125, &Pattern.fast(&1, 2))   # Offset copy
```

## Conditional

```elixir
Pattern.every(pattern, 4, &Pattern.rev/1)     # Every 4th cycle
Pattern.sometimes(pattern, &Pattern.fast(&1, 2))  # 50% probability
Pattern.often(pattern, fun)                   # 75% probability
Pattern.rarely(pattern, fun)                  # 25% probability
Pattern.iter(pattern, 4)                      # Rotate each cycle
Pattern.degrade(pattern)                      # Remove ~50% of events
Pattern.degrade_by(pattern, 0.3)              # Remove ~30%
```

## Rhythm

```elixir
Pattern.euclid(pattern, 3, 8)           # Euclidean rhythm
Pattern.euclid_rot(pattern, 3, 8, 2)    # With rotation
Pattern.swing(pattern, 2)               # Swing feel
```

## Examples

### Layered Drum Pattern

```elixir
kicks = UzuPattern.parse("bd ~ bd ~")
snares = UzuPattern.parse("~ sd ~ sd")
hats = UzuPattern.parse("[hh hh hh hh]")

Pattern.stack([kicks, snares, hats])
|> Pattern.lpf(Pattern.sine() |> Pattern.range(800, 4000))
```

### Evolving Pattern

```elixir
UzuPattern.parse("bd sd hh cp")
|> Pattern.every(4, &Pattern.rev/1)
|> Pattern.every(8, &Pattern.fast(&1, 2))
|> Pattern.sometimes(&Pattern.degrade/1)
|> Pattern.gain(Pattern.saw() |> Pattern.range(0.6, 1.0))
```

### Stereo Arpeggio

```elixir
UzuPattern.parse("arpy:0 arpy:1 arpy:2 arpy:3")
|> Pattern.jux(&Pattern.rev/1)
|> Pattern.lpf(Pattern.tri() |> Pattern.range(500, 3000))
```

## Related Projects

- [UzuParser](https://github.com/rpmessner/uzu_parser) - Mini-notation parser
- [Undertow](https://github.com/rpmessner/undertow_standalone) - Live coding environment

## License

MIT License - see [LICENSE](LICENSE) for details.
