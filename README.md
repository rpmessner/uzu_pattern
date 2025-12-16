# UzuPattern

Pattern library for TidalCycles/Strudel-style live coding in Elixir.

UzuPattern provides a query-based pattern system with time transformations, structure manipulation, conditional application, signal patterns for modulation, and effect parameters. It uses exact rational arithmetic for precise timing and integrates mini-notation parsing from [UzuParser](https://github.com/rpmessner/uzu_parser).

## Installation

```elixir
def deps do
  [
    {:uzu_pattern, "~> 0.8.0"}
  ]
end
```

## Quick Start

```elixir
# Parse mini-notation into a pattern
pattern = UzuPattern.parse("bd sd hh cp")

# Query events for a specific cycle
haps = UzuPattern.query(pattern, 0)

# Apply transformations
pattern
|> Pattern.fast(2)
|> Pattern.rev()
|> Pattern.every(4, &Pattern.slow(&1, 2))
```

## Core Concepts

### Patterns as Query Functions

Patterns are query functions, not static event lists. This enables cycle-aware transformations:

```elixir
pattern = UzuPattern.parse("bd sd") |> Pattern.every(2, &Pattern.rev/1)

Pattern.query(pattern, 0)  # Cycle 0: reversed
Pattern.query(pattern, 1)  # Cycle 1: normal
Pattern.query(pattern, 2)  # Cycle 2: reversed
```

### Haps (Events)

Each query returns a list of `Hap` structs containing:
- `whole` - The timespan of the complete event
- `part` - The portion of the event within the queried range
- `value` - Map with `:sound`, `:sample`, and effect parameters
- `context` - Source locations and tags

```elixir
[hap | _] = UzuPattern.query(pattern, 0)
Hap.sound(hap)   # => "bd"
Hap.sample(hap)  # => 0
hap.part.begin   # => Ratio.new(0, 1)  (exact rational)
hap.part.end     # => Ratio.new(1, 4)
```

### Exact Rational Timing

All time values use exact rational arithmetic via the Ratio library. This prevents rhythmic drift and enables precise pattern calculations:

```elixir
# Times are exact fractions, not floats
hap.part.begin  # => Ratio.new(1, 3) not 0.333...

# Conversion to floats only at the scheduling boundary
TimeSpan.begin_float(hap.part)  # => 0.3333333...
```

## Modules

Functions are organized into logical groups:

| Module | Functions |
|--------|-----------|
| **Pattern** | `query`, `events`, `pure`, `silence`, `stack`, `cat`, `slowcat`, `fastcat`, `timeCat` |
| **Pattern.Time** | `fast`, `slow`, `early`, `late`, `ply`, `compress`, `zoom`, `linger`, `inside` |
| **Pattern.Structure** | `rev`, `palindrome`, `mask`, `degrade`, `jux`, `jux_by`, `superimpose`, `off`, `echo`, `striate`, `chop` |
| **Pattern.Conditional** | `every`, `sometimes`, `often`, `rarely`, `almostNever`, `almostAlways`, `iter`, `first_of`, `last_of`, `when_fn`, `chunk` |
| **Pattern.Effects** | `gain`, `pan`, `speed`, `cut`, `room`, `delay`, `lpf`, `hpf`, `set_param` |
| **Pattern.Rhythm** | `euclid`, `euclid_rot`, `swing`, `swing_by` |
| **Pattern.Signal** | `sine`, `saw`, `isaw`, `tri`, `square`, `rand`, `irand`, `range`, `rangex`, `segment` |
| **Pattern.Algebra** | `add`, `sub`, `mul`, `div_op`, `mod`, `pow`, `app_left`, `app_right`, `app_both` |

## Signal Patterns

Signals provide continuous values for modulating parameters:

```elixir
# Modulate filter cutoff with sine wave (200-2000 Hz)
UzuPattern.parse("bd sd hh cp")
|> Pattern.lpf(Signal.sine() |> Signal.range(200, 2000))

# Random gain per cycle
UzuPattern.parse("bd sd")
|> Pattern.gain(Signal.rand() |> Signal.range(0.5, 1.0))

# Stereo panning sweep
UzuPattern.parse("arpy:0 arpy:1 arpy:2 arpy:3")
|> Pattern.pan(Signal.tri() |> Signal.range(-1, 1))

# Discretize signal into stepped values
Signal.saw() |> Signal.segment(8)  # 8 discrete steps per cycle
```

Available waveforms: `sine`, `saw`, `isaw`, `tri`, `square`, `rand`, `irand`

## Effects

All effects accept static values or signal patterns:

```elixir
pattern
|> Pattern.gain(0.8)           # Static gain
|> Pattern.pan(-0.5)           # Static pan (left)
|> Pattern.speed(2)            # Double speed playback
|> Pattern.cut(1)              # Cut group (monophonic)
|> Pattern.room(0.5)           # Reverb send
|> Pattern.delay(0.3)          # Delay send
|> Pattern.lpf(2000)           # Low-pass filter
|> Pattern.hpf(200)            # High-pass filter
|> Pattern.lpf(Signal.sine() |> Signal.range(200, 2000))  # Modulated
```

## Time Transformations

```elixir
Pattern.fast(pattern, 2)              # Double speed
Pattern.slow(pattern, 2)              # Half speed
Pattern.rev(pattern)                  # Reverse
Pattern.early(pattern, 0.25)          # Shift earlier by 1/4 cycle
Pattern.late(pattern, 0.25)           # Shift later by 1/4 cycle
Pattern.ply(pattern, 3)               # Repeat each event 3 times
Pattern.compress(pattern, 0.25, 0.75) # Fit into time window
Pattern.zoom(pattern, 0.5, 1.0)       # Extract and expand portion
Pattern.linger(pattern, 0.25)         # Loop first 1/4 of pattern
Pattern.inside(pattern, 4, &Pattern.rev/1)  # Apply transform at 4x speed
```

## Structure

```elixir
Pattern.stack([p1, p2, p3])           # Layer patterns (simultaneous)
Pattern.cat([p1, p2, p3])             # Sequence patterns (one per cycle)
Pattern.fastcat([p1, p2, p3])         # Sequence within one cycle
Pattern.slowcat([p1, p2, p3])         # Alias for cat
Pattern.timeCat([{3, p1}, {1, p2}])   # Weighted sequence
Pattern.palindrome(pattern)           # Forward then backward
Pattern.jux(pattern, &Pattern.rev/1)  # Stereo split with transform
Pattern.jux_by(pattern, 0.5, fun)     # Partial stereo separation
Pattern.superimpose(pattern, fun)     # Layer with transform
Pattern.off(pattern, 0.125, fun)      # Offset copy with transform
Pattern.echo(pattern, 3, 0.25, 0.8)   # Multiple echoes with decay
Pattern.striate(pattern, 4)           # Slice into 4 parts
Pattern.chop(pattern, 4)              # Chop each event into 4
```

## Conditional

```elixir
Pattern.every(pattern, 4, fun)        # Apply every 4th cycle
Pattern.sometimes(pattern, fun)       # 50% probability
Pattern.often(pattern, fun)           # 75% probability
Pattern.rarely(pattern, fun)          # 25% probability
Pattern.almostNever(pattern, fun)     # 10% probability
Pattern.almostAlways(pattern, fun)    # 90% probability
Pattern.iter(pattern, 4)              # Rotate by 1/4 each cycle
Pattern.first_of(pattern, 4, fun)     # Apply on first of every 4
Pattern.last_of(pattern, 4, fun)      # Apply on last of every 4
Pattern.when_fn(pattern, pred, fun)   # Apply when predicate true
Pattern.degrade(pattern)              # Remove ~50% of events randomly
Pattern.degrade_by(pattern, 0.3)      # Remove ~30% of events
```

## Rhythm

```elixir
Pattern.euclid(pattern, 3, 8)         # 3 hits over 8 steps (Euclidean)
Pattern.euclid_rot(pattern, 3, 8, 2)  # With rotation offset
Pattern.swing(pattern, 2)             # Swing on 8th notes
Pattern.swing_by(pattern, 0.2, 2)     # Swing with specific amount
```

## Pattern Algebra

Combine patterns with arithmetic operations:

```elixir
Pattern.add(p1, p2)       # Add values
Pattern.mul(p1, p2)       # Multiply values
Pattern.app_left(p1, p2)  # Apply structure from left pattern
Pattern.app_right(p1, p2) # Apply structure from right pattern
Pattern.app_both(p1, p2)  # Combine both structures
```

## Mini-Notation Features

The parser supports the full Strudel/Tidal mini-notation:

```elixir
# Basic sequences and rests
"bd sd hh cp"       # Four sounds
"bd ~ sd ~"         # With rests

# Subdivisions
"bd [sd sd] hh"     # Subdivision
"[[bd sd] hh]"      # Nested

# Modifiers
"bd*4"              # Repeat 4 times
"[bd sd]/2"         # Slow by 2
"bd:3"              # Sample 3
"bd?"               # 50% probability
"bd?0.25"           # 25% probability
"bd@2 sd"           # Weight (bd twice as long)
"bd _ sd"           # Elongation

# Polyphony
"[bd,sd,hh]"        # Chord (simultaneous)
"{bd sd, hh hh hh}" # Polymetric

# Alternation
"<bd sd hh>"        # Cycle through options
"bd|sd|hh"          # Random choice

# Euclidean
"bd(3,8)"           # 3 over 8
"bd(3,8,1)"         # With rotation

# Parameters
"bd|gain:0.8|speed:2"
```

## Examples

### Layered Drum Pattern

```elixir
kicks = UzuPattern.parse("bd ~ bd ~")
snares = UzuPattern.parse("~ sd ~ sd")
hats = UzuPattern.parse("[hh hh hh hh]")

Pattern.stack([kicks, snares, hats])
|> Pattern.lpf(Signal.sine() |> Signal.range(800, 4000))
```

### Evolving Pattern

```elixir
UzuPattern.parse("bd sd hh cp")
|> Pattern.every(4, &Pattern.rev/1)
|> Pattern.every(8, &Pattern.fast(&1, 2))
|> Pattern.sometimes(&Pattern.degrade/1)
|> Pattern.gain(Signal.saw() |> Signal.range(0.6, 1.0))
```

### Stereo Arpeggio

```elixir
UzuPattern.parse("arpy:0 arpy:1 arpy:2 arpy:3")
|> Pattern.jux(&Pattern.rev/1)
|> Pattern.lpf(Signal.tri() |> Signal.range(500, 3000))
```

### Polyrhythmic Layers

```elixir
Pattern.stack([
  UzuPattern.parse("bd(3,8)"),
  UzuPattern.parse("sd(5,8)"),
  UzuPattern.parse("hh*8")
])
|> Pattern.every(4, &Pattern.fast(&1, 2))
```

## Related Projects

- [UzuParser](https://github.com/rpmessner/uzu_parser) - Mini-notation parser
- [Waveform](https://github.com/rpmessner/waveform) - Audio playback via SuperCollider/MIDI

## License

MIT License - see [LICENSE](LICENSE) for details.
