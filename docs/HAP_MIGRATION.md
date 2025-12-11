# Hap Migration: Adopting Strudel's Event Format

## Overview

This document describes the migration from UzuPattern's current `Event` struct to Strudel's `Hap` format. The Hap format provides better semantics for:

- Query boundary handling (whole vs part)
- Continuous vs discrete events
- Rich metadata via context
- Consistent parameter storage

## Current State: UzuPattern.Event

```elixir
defstruct sound: "",
          sample: nil,
          time: 0.0,
          duration: 1.0,
          params: %{},
          source_start: nil,
          source_end: nil,
          value: nil,
          continuous: false
```

**Problems:**

1. **No whole/part distinction** - When querying cycle 0-1, an event spanning 0.8-1.2 gets clipped without knowing it continues
2. **Scattered parameters** - `sound`, `sample`, `params` are separate; Strudel puts everything in `value`
3. **Flat metadata** - `source_start/end` are top-level; should be in `context.locations`
4. **Boolean continuous** - Strudel uses `whole: nil` to indicate continuous

## Target State: Hap Format

### Strudel's Hap Structure

```javascript
class Hap {
  whole;       // TimeSpan | undefined - the "true" event extent
  part;        // TimeSpan (required) - intersection with query window
  value;       // any - all parameters live here
  context;     // object - metadata (locations, tags, triggers)
  stateful;    // boolean - for stateful patterns (rare)
}

class TimeSpan {
  begin;  // Fraction - start time
  end;    // Fraction - end time
}
```

### Proposed UzuPattern.Hap

```elixir
defmodule UzuPattern.Hap do
  @moduledoc """
  A Hap (happening) represents a pattern event with precise timing semantics.

  Adopts Strudel's Hap format for compatibility and correct boundary handling.

  ## Fields

  - `whole` - The complete event timespan, or nil for continuous events
  - `part` - The portion intersecting the query window (always present)
  - `value` - Map of all parameters (s, n, note, gain, pan, etc.)
  - `context` - Metadata: source locations, tags, callbacks

  ## Whole vs Part

  When querying a pattern, events may extend beyond the query window:

      # Query [0.0, 1.0), event naturally spans [0.8, 1.2)
      %Hap{
        whole: %{begin: 0.8, end: 1.2},  # True extent
        part:  %{begin: 0.8, end: 1.0},  # Clipped to query
        value: %{s: "bd"}
      }

  The scheduler uses `whole` to know when to trigger the sound,
  while `part` indicates what portion was requested.

  ## Continuous Events

  For continuously varying values (signals), `whole` is nil:

      %Hap{
        whole: nil,                      # No discrete onset
        part:  %{begin: 0.5, end: 1.0},
        value: %{freq: 440.0}
      }

  ## Value Map

  All parameters live in value using short names:

      %{
        s: "bd",           # sound/sample bank
        n: 0,              # sample number
        note: 60,          # MIDI note
        gain: 0.8,         # amplitude 0-1
        pan: 0.0,          # stereo -1 to 1
        speed: 1.0,        # playback rate
        begin: 0.0,        # sample slice start
        end: 1.0,          # sample slice end
        # ... any other parameter
      }

  ## Context

  Metadata accumulated through pattern operations:

      %{
        locations: [%{file: "...", line: 42, column: 5}],
        tags: ["drums", "loop"],
        # Future: onTrigger callbacks
      }
  """

  @type timespan :: %{begin: float(), end: float()}

  @type t :: %__MODULE__{
    whole: timespan() | nil,
    part: timespan(),
    value: map(),
    context: map()
  }

  defstruct whole: nil,
            part: %{begin: 0.0, end: 1.0},
            value: %{},
            context: %{locations: [], tags: []}
end
```

## TimeSpan Operations

Strudel uses Fraction for precise arithmetic. We can use floats initially, potentially moving to rationals later.

```elixir
defmodule UzuPattern.TimeSpan do
  @moduledoc """
  Time interval with begin/end points.
  """

  @type t :: %{begin: float(), end: float()}

  def new(begin_time, end_time) do
    %{begin: begin_time, end: end_time}
  end

  def duration(%{begin: b, end: e}), do: e - b

  def midpoint(%{begin: b, end: e}), do: (b + e) / 2

  @doc "Returns intersection of two timespans, or nil if disjoint"
  def intersection(%{begin: b1, end: e1}, %{begin: b2, end: e2}) do
    new_begin = max(b1, b2)
    new_end = min(e1, e2)
    if new_begin < new_end do
      %{begin: new_begin, end: new_end}
    else
      nil
    end
  end

  @doc "Split timespan at cycle boundaries"
  def span_cycles(%{begin: b, end: e}) do
    start_cycle = floor(b)
    end_cycle = floor(e)

    if start_cycle == end_cycle or (end_cycle == e and e == floor(e)) do
      [%{begin: b, end: e}]
    else
      first = %{begin: b, end: start_cycle + 1.0}
      rest = span_cycles(%{begin: start_cycle + 1.0, end: e})
      [first | rest]
    end
  end

  @doc "Check if timespan contains a point"
  def contains?(%{begin: b, end: e}, point) do
    point >= b and point < e
  end
end
```

## Migration Phases

### Phase 1: Add Hap Module (Parallel Structure)

Create `UzuPattern.Hap` and `UzuPattern.TimeSpan` modules alongside existing `Event`. This allows incremental migration.

**Files to create:**
- `lib/uzu_pattern/hap.ex`
- `lib/uzu_pattern/timespan.ex`

**Tests:**
- `test/uzu_pattern/hap_test.exs`
- `test/uzu_pattern/timespan_test.exs`

### Phase 2: Update Pattern.query/2 to Return Haps

The core change: `Pattern.query(pattern, cycle)` returns `[Hap]` instead of `[Event]`.

**Current:**
```elixir
def query(%Pattern{query: query_fn}, cycle) when is_integer(cycle) do
  query_fn.(cycle)  # Returns [Event]
end
```

**New:**
```elixir
def query(%Pattern{query: query_fn}, cycle) when is_integer(cycle) do
  span = TimeSpan.new(cycle, cycle + 1)
  query_fn.(span)  # Returns [Hap]
end

# Query arbitrary timespan (for lookahead, boundary handling)
def query_arc(%Pattern{query: query_fn}, begin_time, end_time) do
  TimeSpan.new(begin_time, end_time)
  |> TimeSpan.span_cycles()
  |> Enum.flat_map(fn span -> query_fn.(span) end)
end
```

**Files to modify:**
- `lib/uzu_pattern/pattern.ex`

### Phase 3: Update Interpreter to Create Haps

The mini-notation interpreter creates events. Update to create Haps.

**Current (simplified):**
```elixir
defp create_event(sound, time, duration) do
  %Event{sound: sound, time: time, duration: duration}
end
```

**New:**
```elixir
defp create_hap(sound, time, duration, source_loc) do
  %Hap{
    whole: %{begin: time, end: time + duration},
    part: %{begin: time, end: time + duration},
    value: %{s: sound},
    context: %{locations: [source_loc]}
  }
end
```

**Files to modify:**
- `lib/uzu_pattern/interpreter.ex`

### Phase 4: Update Pattern Transforms

All pattern transforms that manipulate events need updates.

**Example: fast/2**

**Current:**
```elixir
def fast(%Pattern{} = pattern, factor) do
  map(pattern, fn event ->
    %{event |
      time: event.time / factor,
      duration: event.duration / factor
    }
  end)
end
```

**New:**
```elixir
def fast(%Pattern{} = pattern, factor) do
  with_query_time(pattern, fn span ->
    # Scale the query span
    %{begin: span.begin * factor, end: span.end * factor}
  end)
  |> map_haps(fn hap ->
    # Scale the hap timespans
    %{hap |
      whole: scale_timespan(hap.whole, 1/factor),
      part: scale_timespan(hap.part, 1/factor)
    }
  end)
end

defp scale_timespan(nil, _), do: nil
defp scale_timespan(%{begin: b, end: e}, factor) do
  %{begin: b * factor, end: e * factor}
end
```

**Key transforms to update:**
- `fast/2`, `slow/2` - Time scaling
- `early/2`, `late/2` - Time shifting
- `rev/1` - Time reversal
- `every/3` - Conditional application
- `stack/1`, `cat/1` - Pattern combination
- `set_param/3` - Add to value map
- Signal transforms (`sine/0`, `saw/0`, etc.)

**Files to modify:**
- `lib/uzu_pattern/pattern.ex`
- `lib/uzu_pattern/pattern/signal.ex`
- `lib/uzu_pattern/pattern/rhythm.ex`

### Phase 5: Update Channel Serialization

The channel formats events for the browser. Simplify to one path.

**Current (two paths):**
```elixir
# Path 1: UzuPattern.Event
defp format_event(%UzuPattern.Event{} = event) do
  %{"s" => event.sound, "time" => event.time, "dur" => event.duration, ...}
end

# Path 2: Strudel Hap-like maps
defp format_event(%{value: value} = event) do
  %{"time" => event.whole_start || event.part_start, ...}
end
```

**New (single path):**
```elixir
defp format_hap(%Hap{} = hap) do
  %{
    "whole" => format_timespan(hap.whole),
    "part" => format_timespan(hap.part),
    "value" => hap.value,
    "context" => hap.context
  }
end

defp format_timespan(nil), do: nil
defp format_timespan(%{begin: b, end: e}), do: %{"begin" => b, "end" => e}
```

**Files to modify:**
- `lib/undertow_standalone_web/channels/undertow_channel.ex`

### Phase 6: Update JavaScript Side

The browser needs to understand Hap format.

**Current:** Expects `{time, dur, s, n, ...}`

**New:** Expects `{whole: {begin, end}, part: {begin, end}, value: {s, n, ...}}`

**Files to modify:**
- `undertow_repl_js/src/audio/scheduler.ts`
- `undertow_repl_js/src/visualization-manager.ts`
- `undertow_standalone/assets/js/lib/audio-state.ts`

### Phase 7: Deprecate Event, Remove

Once all code uses Hap:
1. Mark `UzuPattern.Event` as deprecated
2. Update any remaining references
3. Delete `Event` module

## Value Field Conventions

All parameters use short names (Strudel convention):

| Long Name | Short | Description |
|-----------|-------|-------------|
| sound | s | Sample bank name |
| sample | n | Sample number in bank |
| note | note | MIDI note number |
| gain | gain | Amplitude 0-1 |
| pan | pan | Stereo position -1 to 1 |
| speed | speed | Playback rate |
| duration | dur | Event duration (for sustain) |
| begin | begin | Sample slice start 0-1 |
| end | end | Sample slice end 0-1 |
| octave | oct | Octave offset |
| cutoff | cutoff | Filter cutoff frequency |
| resonance | resonance | Filter resonance |

## Context Field Conventions

```elixir
%{
  # Source code locations for debugging/highlighting
  locations: [
    %{
      source_start: 0,    # Character offset in source
      source_end: 5,
      file: "repl",       # Optional: source file
      line: 1,            # Optional: line number
      column: 0           # Optional: column
    }
  ],

  # Tags for filtering/identification
  tags: ["drums", "d1"],

  # Pattern label (track name)
  label: "d1",

  # Future: trigger callbacks
  # on_trigger: fn hap, time -> ... end
}
```

## Continuous Events (Signals)

For continuously varying values, `whole` is nil:

```elixir
# Discrete event (has onset)
%Hap{
  whole: %{begin: 0.0, end: 0.5},
  part: %{begin: 0.0, end: 0.5},
  value: %{s: "bd"}
}

# Continuous event (sampled value)
%Hap{
  whole: nil,
  part: %{begin: 0.0, end: 1.0},
  value: %{freq: 440.0},
  context: %{tags: ["continuous"]}
}
```

The scheduler handles these differently:
- Discrete: Trigger at `whole.begin`
- Continuous: Sample value at `part.midpoint` or interpolate

## Query Semantics

### queryArc(begin, end)

Query a pattern for events in a time range:

```elixir
def query_arc(pattern, begin_time, end_time) do
  # Split at cycle boundaries
  spans = TimeSpan.span_cycles(%{begin: begin_time, end: end_time})

  # Query each cycle span
  Enum.flat_map(spans, fn span ->
    pattern.query.(span)
    |> Enum.filter(fn hap ->
      # Keep only haps that intersect our query
      TimeSpan.intersection(hap.part, span) != nil
    end)
    |> Enum.map(fn hap ->
      # Clip part to query span
      %{hap | part: TimeSpan.intersection(hap.part, span)}
    end)
  end)
end
```

### Boundary Example

Query `[0.7, 1.3)` for a pattern with event at `[0.8, 1.2)`:

```
Cycle 0: query [0.7, 1.0)
  -> Hap{whole: [0.8, 1.2), part: [0.8, 1.0)}  # Clipped at cycle end

Cycle 1: query [1.0, 1.3)
  -> Hap{whole: [0.8, 1.2), part: [1.0, 1.2)}  # Clipped at cycle start
```

The scheduler sees both fragments but triggers the sound only once (at `whole.begin`).

## Testing Strategy

### Unit Tests

```elixir
# TimeSpan tests
test "intersection of overlapping spans" do
  a = %{begin: 0.0, end: 0.5}
  b = %{begin: 0.3, end: 0.8}
  assert TimeSpan.intersection(a, b) == %{begin: 0.3, end: 0.5}
end

test "span_cycles splits at boundaries" do
  span = %{begin: 0.5, end: 2.3}
  assert TimeSpan.span_cycles(span) == [
    %{begin: 0.5, end: 1.0},
    %{begin: 1.0, end: 2.0},
    %{begin: 2.0, end: 2.3}
  ]
end

# Hap tests
test "hap with whole and part" do
  hap = Hap.new(
    whole: %{begin: 0.0, end: 1.0},
    part: %{begin: 0.0, end: 0.5},
    value: %{s: "bd"}
  )
  assert hap.whole.end == 1.0
  assert hap.part.end == 0.5
end

test "continuous hap has nil whole" do
  hap = Hap.continuous(%{begin: 0.0, end: 1.0}, %{freq: 440})
  assert hap.whole == nil
end
```

### Integration Tests

```elixir
test "fast/2 scales hap timespans" do
  pattern = s("bd") |> fast(2)
  haps = Pattern.query(pattern, 0)

  # Original event at [0, 1) becomes [0, 0.5) and [0.5, 1)
  assert length(haps) == 2
  assert Enum.at(haps, 0).whole == %{begin: 0.0, end: 0.5}
  assert Enum.at(haps, 1).whole == %{begin: 0.5, end: 1.0}
end

test "query_arc handles cycle boundaries" do
  pattern = s("bd sd")  # bd at [0, 0.5), sd at [0.5, 1)
  haps = Pattern.query_arc(pattern, 0.3, 0.7)

  assert length(haps) == 2
  # bd: whole [0, 0.5), part clipped to [0.3, 0.5)
  # sd: whole [0.5, 1), part clipped to [0.5, 0.7)
end
```

## Compatibility Notes

### Strudel Interop

With Hap format, we can potentially:
- Import Strudel pattern definitions
- Export patterns to Strudel
- Share visualization code

### Breaking Changes

This is a breaking change for:
- Any code directly accessing `Event` fields
- Custom pattern transforms
- External tools consuming pattern events

Migration path:
1. Add deprecation warnings to Event
2. Provide Event-to-Hap conversion helpers
3. Full removal in next major version

## Open Questions

1. **Fraction vs Float** - Strudel uses arbitrary-precision fractions. Do we need this? Floats are simpler but may accumulate errors over long patterns.

2. **Stateful patterns** - Strudel's `stateful` flag allows value to be a function. Do we need this for Elixir?

3. **Context callbacks** - `onTrigger` in context allows per-event callbacks. Useful for visualization hooks?

4. **Value type enforcement** - Strudel throws if value isn't an object when expected. Should we be strict?

## References

- Strudel source: `packages/core/hap.mjs`, `pattern.mjs`, `timespan.mjs`
- Tidal Haskell: Similar concepts in `Sound.Tidal.Pattern`
- UzuPattern current: `lib/uzu_pattern/event.ex`
