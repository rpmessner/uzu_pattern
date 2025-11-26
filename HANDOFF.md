# UzuPattern Architecture & Integration Guide

This document provides comprehensive information for integrating UzuPattern with other components of the Elixir music ecosystem.

## Overview

UzuPattern sits between UzuParser (parsing) and Waveform (audio playback):

```
User Code (kino_harmony, harmony_server)
              │
              ▼
┌─────────────────────────────────────────┐
│            UzuPattern                    │
│                                          │
│  Pattern.new("bd sd hh cp")             │
│  |> Pattern.fast(2)                     │
│  |> Pattern.every(4, &Pattern.rev/1)    │
│  |> Pattern.query(cycle)                │
└────────────────┬────────────────────────┘
                 │
    ┌────────────┴────────────┐
    ▼                         ▼
┌──────────┐           ┌──────────┐
│UzuParser │           │ Waveform │
│          │           │          │
│parse/1   │           │schedule  │
│[Event{}] │           │play OSC  │
└──────────┘           └──────────┘
```

## Key Design Decisions

### 1. Separation from UzuParser

**Why separate libraries?**

- **Single Responsibility**: UzuParser handles parsing, UzuPattern handles transformation
- **Reusability**: Both waveform and harmony_server can use UzuPattern
- **Testability**: Transformation logic can be tested independently
- **Strudel Parity**: Mirrors Strudel.js architecture (mini-notation vs Pattern class)

### 2. Cycle-Aware Transformations

**The Problem:**
Functions like `every(4, rev)` need to know which cycle is being played to decide whether to apply the transformation.

**The Solution:**
- Store cycle-aware transforms in the Pattern struct
- Resolve them when `query/2` is called with a cycle number
- Waveform provides the cycle number at scheduling time

```elixir
# Pattern stores the transform rule
pattern = Pattern.new("bd sd") |> Pattern.every(4, &Pattern.rev/1)

# Waveform calls query with cycle number
events = Pattern.query(pattern, 0)  # cycle 0: reversed
events = Pattern.query(pattern, 1)  # cycle 1: normal
events = Pattern.query(pattern, 2)  # cycle 2: normal
events = Pattern.query(pattern, 3)  # cycle 3: normal
events = Pattern.query(pattern, 4)  # cycle 4: reversed (4 mod 4 == 0)
```

### 3. Query Function Interface

UzuPattern provides events to Waveform via a query function:

```elixir
# Create the query function
query_fn = fn cycle -> UzuPattern.query(pattern, cycle) end

# Pass to Waveform (after Waveform implements query function support)
Waveform.PatternScheduler.schedule_pattern(:drums, query_fn)
```

**Why a function instead of raw events?**
- Allows cycle-aware transforms to be resolved at playback time
- Keeps Waveform decoupled from UzuPattern internals
- Supports dynamic pattern changes

### 4. Event Format

UzuPattern's `query/2` returns events in Waveform's expected format:

```elixir
# Format: [{cycle_position, params}]
[
  {0.0, [s: "bd", n: nil, dur: 0.25]},
  {0.25, [s: "sd", n: nil, dur: 0.25]},
  ...
]
```

This matches Waveform's `PatternScheduler.schedule_pattern/3` format.

## Integration Points

### With Waveform

**Current state**: Waveform accepts static event lists
**Future state**: Waveform accepts query functions (see `waveform/docs/HANDOFF_CYCLE_AWARE_PATTERNS.md`)

Until Waveform is updated, you can use a polling approach:

```elixir
# Workaround until Waveform supports query functions
defmodule PatternPlayer do
  def start(pattern) do
    spawn(fn -> loop(pattern, 0) end)
  end

  defp loop(pattern, cycle) do
    events = UzuPattern.query(pattern, cycle)
    Waveform.PatternScheduler.update_pattern(:my_pattern, events)
    Process.sleep(cycle_duration_ms())
    loop(pattern, cycle + 1)
  end
end
```

### With kino_harmony

kino_harmony can use UzuPattern for pattern transformations:

```elixir
# In a Livebook cell
alias UzuPattern.Pattern

"bd sd [hh hh] cp"
|> Pattern.new()
|> Pattern.fast(2)
|> Pattern.every(4, &Pattern.rev/1)
|> play()  # kino_harmony's play function
```

### With harmony_server

harmony_server can expose UzuPattern functions via RPC:

```elixir
# harmony_server endpoint
def handle_call({:transform_pattern, pattern_string, transforms}, _from, state) do
  pattern = UzuPattern.new(pattern_string)

  transformed = Enum.reduce(transforms, pattern, fn
    {:fast, factor}, p -> UzuPattern.Pattern.fast(p, factor)
    {:slow, factor}, p -> UzuPattern.Pattern.slow(p, factor)
    {:rev}, p -> UzuPattern.Pattern.rev(p)
    {:every, n, :rev}, p -> UzuPattern.Pattern.every(p, n, &UzuPattern.Pattern.rev/1)
  end)

  {:reply, {:ok, transformed}, state}
end
```

## Pattern Struct Internals

```elixir
%UzuPattern.Pattern{
  events: [%UzuParser.Event{}, ...],  # Base events from parsing
  transforms: [                        # Pending cycle-aware transforms
    {:every, 4, &Pattern.rev/1},
    {:sometimes_by, 0.5, &Pattern.fast(&1, 2)}
  ]
}
```

### Immediate vs Deferred Transforms

**Immediate** (applied immediately, modify `events`):
- `fast/2`, `slow/2`, `rev/1`
- `early/2`, `late/2`
- `stack/1`, `cat/1`
- `degrade/1`, `degrade_by/2`
- `jux/2`

**Deferred** (stored in `transforms`, applied at query time):
- `every/3`
- `sometimes_by/3`, `sometimes/2`, `often/2`, `rarely/2`

## Testing Strategy

### Unit Tests
Test each transformation in isolation:

```elixir
test "fast/2 doubles speed" do
  pattern = Pattern.new("bd sd") |> Pattern.fast(2)
  events = Pattern.events(pattern)
  assert Enum.at(events, 1).time == 0.25  # was 0.5
end
```

### Cycle-Aware Tests
Test transforms with different cycle numbers:

```elixir
test "every/3 applies on matching cycles" do
  pattern = Pattern.new("bd sd") |> Pattern.every(2, &Pattern.rev/1)

  # Cycle 0: should be reversed (0 mod 2 == 0)
  events_0 = Pattern.query(pattern, 0)
  assert hd(events_0) |> elem(1) |> Keyword.get(:s) == "sd"

  # Cycle 1: should be normal
  events_1 = Pattern.query(pattern, 1)
  assert hd(events_1) |> elem(1) |> Keyword.get(:s) == "bd"
end
```

### Property-Based Tests
Use StreamData for mathematical properties:

```elixir
property "fast(n) |> slow(n) == identity" do
  check all pattern_str <- pattern_generator(),
            factor <- float(min: 0.5, max: 4.0) do
    pattern = Pattern.new(pattern_str)
    roundtrip = pattern |> Pattern.fast(factor) |> Pattern.slow(factor)

    # Events should have same times (within float tolerance)
    assert_events_equal(Pattern.events(pattern), Pattern.events(roundtrip))
  end
end
```

## Performance Considerations

### Query Function Caching

For expensive transformations, consider caching:

```elixir
defmodule CachedPattern do
  def query_with_cache(pattern, cycle) do
    cache_key = {pattern, cycle}

    case :ets.lookup(:pattern_cache, cache_key) do
      [{^cache_key, events}] -> events
      [] ->
        events = UzuPattern.query(pattern, cycle)
        :ets.insert(:pattern_cache, {cache_key, events})
        events
    end
  end
end
```

### Event Count

Be mindful of event count when stacking patterns:

```elixir
# This creates many events
huge_pattern =
  1..100
  |> Enum.map(fn _ -> Pattern.new("bd sd hh cp") end)
  |> Pattern.stack()

# Consider limiting or chunking
```

## Error Handling

UzuPattern functions generally don't raise errors - they return empty patterns or pass through invalid input:

```elixir
Pattern.new("")           # => %Pattern{events: []}
Pattern.fast(pattern, 0)  # Guard prevents this (factor must be > 0)
Pattern.fast(pattern, -1) # Guard prevents this
```

## Future Enhancements

See `ROADMAP.md` for the full feature roadmap. Key upcoming features:

1. **Phase 2**: `ply`, `iter`, `compress`, `zoom`
2. **Phase 3**: `first_of`, `last_of`, `when_fn`, `chunk`
3. **Phase 4**: Effect parameters (`gain`, `pan`, `lpf`)
4. **Phase 5**: Advanced combinators (`superimpose`, `off`, `echo`)
5. **Phase 6**: Generative rhythm (`euclid`, `swing`)

## Questions?

- Check `ROADMAP.md` for feature status
- Check Waveform's `docs/HANDOFF_CYCLE_AWARE_PATTERNS.md` for integration details
- See [Strudel.js docs](https://strudel.cc/learn/) for function behavior reference
