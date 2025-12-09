defmodule UzuPattern.Pattern do
  @moduledoc """
  Query-based pattern representation for composable live coding patterns.

  A Pattern stores a query function that is evaluated lazily when events
  are needed for a specific cycle. This enables proper composition of
  patterns including nested alternation.

  ## Core Concept

  A pattern is a function: `cycle -> [Event]`

  This allows patterns to be composed without expanding all events upfront:
  - `slowcat([p1, p2, p3])` - alternates patterns across cycles
  - `fastcat([p1, p2, p3])` - sequences patterns within a cycle
  - `stack([p1, p2, p3])` - layers patterns simultaneously

  ## Examples

      # Create a simple pattern
      p = Pattern.pure("bd")

      # Create a sequence (plays within one cycle)
      p = Pattern.fastcat([
        Pattern.pure("bd"),
        Pattern.pure("sd")
      ])

      # Create alternation (one per cycle)
      p = Pattern.slowcat([
        Pattern.fastcat([Pattern.pure("bd"), Pattern.pure("sd")]),
        Pattern.fastcat([Pattern.pure("hh"), Pattern.pure("cp")])
      ])

      # Query for events
      events = Pattern.query(p, 0)  # cycle 0: bd, sd
      events = Pattern.query(p, 1)  # cycle 1: hh, cp
  """

  alias UzuPattern.Event

  @type query_fn :: (non_neg_integer() -> [Event.t()])

  @type t :: %__MODULE__{
          query: query_fn(),
          metadata: map()
        }

  defstruct query: nil, metadata: %{}

  # ============================================================================
  # Constructors
  # ============================================================================

  @doc """
  Create a pattern from a query function.

  The query function takes a cycle number and returns events for that cycle.
  Events should have time values in [0, 1) representing position within the cycle.
  """
  def new(query_fn) when is_function(query_fn, 1) do
    %__MODULE__{query: query_fn, metadata: %{}}
  end

  @doc """
  Get events for cycle 0 as raw Event structs.

  This is a convenience function for tests and simple use cases.
  For cycle-aware patterns, use `query/2` instead.
  """
  def events(%__MODULE__{} = pattern) do
    query(pattern, 0)
  end

  @doc """
  Create a pattern that produces a single event at the start of each cycle.

  ## Examples

      iex> p = QueryPattern.pure("bd")
      iex> [event] = QueryPattern.query(p, 0)
      iex> event.sound
      "bd"
  """
  def pure(value, opts \\ []) when is_binary(value) do
    sample = Keyword.get(opts, :sample)
    params = Keyword.get(opts, :params, %{})
    source_start = Keyword.get(opts, :source_start)
    source_end = Keyword.get(opts, :source_end)

    new(fn _cycle ->
      [
        %Event{
          sound: value,
          sample: sample,
          time: 0.0,
          duration: 1.0,
          params: params,
          source_start: source_start,
          source_end: source_end
        }
      ]
    end)
  end

  @doc """
  Create an empty/silent pattern.
  """
  def silence do
    new(fn _cycle -> [] end)
  end

  @doc """
  Create a pattern from a list of pre-computed events.
  The events will be returned unchanged for any cycle.
  """
  def from_events(events) when is_list(events) do
    new(fn _cycle -> events end)
  end

  # ============================================================================
  # Pattern Combinators
  # ============================================================================

  @doc """
  Concatenate patterns, one per cycle (slowcat/cat).

  `<a b c>` in mini-notation becomes `slowcat([a, b, c])`.

  On cycle 0, pattern 0 plays. On cycle 1, pattern 1 plays, etc.
  Cycles wrap around when they exceed the number of patterns.

  ## Examples

      iex> p = QueryPattern.slowcat([
      ...>   QueryPattern.pure("bd"),
      ...>   QueryPattern.pure("sd")
      ...> ])
      iex> [e0] = QueryPattern.query(p, 0)
      iex> e0.sound
      "bd"
      iex> [e1] = QueryPattern.query(p, 1)
      iex> e1.sound
      "sd"
      iex> [e2] = QueryPattern.query(p, 2)
      iex> e2.sound
      "bd"
  """
  def slowcat([]), do: silence()
  def slowcat([single]), do: single

  def slowcat(patterns) when is_list(patterns) do
    n = length(patterns)

    new(fn cycle ->
      # Select pattern based on cycle, wrapping around
      index = rem(cycle, n)
      pattern = Enum.at(patterns, index)
      query(pattern, cycle)
    end)
  end

  @doc """
  Alias for slowcat - alternates patterns across cycles.
  """
  def cat(patterns), do: slowcat(patterns)

  @doc """
  Concatenate patterns within a single cycle (fastcat/sequence).

  `[a b c]` in mini-notation becomes `fastcat([a, b, c])`.

  All patterns play within one cycle, each taking 1/n of the cycle time.

  ## Examples

      iex> p = QueryPattern.fastcat([
      ...>   QueryPattern.pure("bd"),
      ...>   QueryPattern.pure("sd"),
      ...>   QueryPattern.pure("hh")
      ...> ])
      iex> events = QueryPattern.query(p, 0)
      iex> Enum.map(events, & &1.time)
      [0.0, 0.333..., 0.666...]
  """
  def fastcat([]), do: silence()
  def fastcat([single]), do: single

  def fastcat(patterns) when is_list(patterns) do
    n = length(patterns)
    step = 1.0 / n

    new(fn cycle ->
      patterns
      |> Enum.with_index()
      |> Enum.flat_map(fn {pattern, index} ->
        offset = index * step

        # Query pattern (it returns events in [0, 1))
        # Scale and shift those events to fit in this slot
        pattern
        |> query(cycle)
        |> Enum.map(fn event ->
          %{event | time: offset + event.time * step, duration: event.duration * step}
        end)
      end)
    end)
  end

  @doc """
  Alias for fastcat - sequences patterns within a cycle.
  """
  def sequence(patterns), do: fastcat(patterns)

  @doc """
  Append a second pattern after the first.

  The combined pattern has double the period - first pattern plays,
  then second pattern plays in the next cycle.
  """
  def append(%__MODULE__{} = pattern1, %__MODULE__{} = pattern2) do
    slowcat([pattern1, pattern2])
  end

  @doc """
  Layer patterns to play simultaneously (polyphony).

  `[a, b, c]` (with commas) in mini-notation becomes `stack([a, b, c])`.

  All patterns play at the same time within each cycle.

  ## Examples

      iex> p = QueryPattern.stack([
      ...>   QueryPattern.pure("bd"),
      ...>   QueryPattern.pure("sd")
      ...> ])
      iex> events = QueryPattern.query(p, 0)
      iex> length(events)
      2
      iex> Enum.map(events, & &1.sound) |> Enum.sort()
      ["bd", "sd"]
  """
  def stack([]), do: silence()
  def stack([single]), do: single

  def stack(patterns) when is_list(patterns) do
    new(fn cycle ->
      Enum.flat_map(patterns, fn pattern ->
        query(pattern, cycle)
      end)
    end)
  end

  # ============================================================================
  # Time Modifiers
  # ============================================================================

  @doc """
  Speed up a pattern by factor n.

  `*n` in mini-notation. Makes the pattern play n times per cycle.

  ## Examples

      iex> p = QueryPattern.pure("bd") |> QueryPattern.fast(4)
      iex> events = QueryPattern.query(p, 0)
      iex> length(events)
      4
      iex> Enum.map(events, & &1.time)
      [0.0, 0.25, 0.5, 0.75]
  """
  def fast(%__MODULE__{} = pattern, factor) when factor > 0 do
    new(fn cycle ->
      # When fast by n, we query n times per cycle
      0..(factor - 1)
      |> Enum.flat_map(fn i ->
        offset = i / factor
        step = 1.0 / factor

        pattern
        |> query(cycle * factor + i)
        |> Enum.map(fn event ->
          %{event | time: offset + event.time * step, duration: event.duration * step}
        end)
      end)
    end)
  end

  @doc """
  Slow down a pattern by factor n.

  `/n` in mini-notation. Makes the pattern take n cycles to complete.
  """
  def slow(%__MODULE__{} = pattern, factor) when factor > 0 do
    new(fn cycle ->
      # Only produce events on cycles where this pattern is "active"
      # For slow(2), cycle 0 and 1 both show the first half/second half of pattern
      inner_cycle = div(cycle, factor)
      position_in_slow = rem(cycle, factor)

      # Query the inner pattern
      events = query(pattern, inner_cycle)

      # Filter to events that fall within this cycle's portion
      start_frac = position_in_slow / factor
      end_frac = (position_in_slow + 1) / factor

      events
      |> Enum.filter(fn event ->
        event.time >= start_frac and event.time < end_frac
      end)
      |> Enum.map(fn event ->
        # Rescale time to [0, 1) within this cycle
        %{event | time: (event.time - start_frac) * factor, duration: event.duration * factor}
      end)
    end)
  end

  @doc """
  Shift pattern earlier in time.
  """
  def early(%__MODULE__{} = pattern, amount) do
    new(fn cycle ->
      pattern
      |> query(cycle)
      |> Enum.map(fn event ->
        new_time = event.time - amount
        wrapped = if new_time < 0, do: new_time + 1.0, else: new_time
        %{event | time: wrapped}
      end)
      |> Enum.sort_by(& &1.time)
    end)
  end

  @doc """
  Shift pattern later in time.
  """
  def late(%__MODULE__{} = pattern, amount) do
    early(pattern, -amount)
  end

  @doc """
  Repeat each event N times within its duration, creating rolls and stutters.

  Unlike `fast`, which speeds up the whole pattern, `ply` repeats each
  individual event in place. Great for drum rolls, glitchy effects, or
  adding rhythmic complexity.

  ## Examples

      iex> p = QueryPattern.pure("bd") |> QueryPattern.ply(4)
      iex> events = QueryPattern.query(p, 0)
      iex> length(events)
      4
  """
  def ply(%__MODULE__{} = pattern, n) when is_integer(n) and n > 0 do
    new(fn cycle ->
      pattern
      |> query(cycle)
      |> Enum.flat_map(fn event ->
        event_duration = event.duration / n

        for i <- 0..(n - 1) do
          %{event | time: event.time + i * event_duration, duration: event_duration}
        end
      end)
      |> Enum.sort_by(& &1.time)
    end)
  end

  @doc """
  Squeeze the pattern into a portion of the cycle, leaving silence elsewhere.

  `compress(0.0, 0.5)` plays the full pattern in the first half, then silence.
  `compress(0.25, 0.75)` plays the pattern in the middle half of the cycle.

  ## Examples

      iex> p = QueryPattern.fastcat([QueryPattern.pure("bd"), QueryPattern.pure("sd")])
      iex> compressed = QueryPattern.compress(p, 0.0, 0.5)
      iex> events = QueryPattern.query(compressed, 0)
      iex> Enum.all?(events, fn e -> e.time >= 0.0 and e.time < 0.5 end)
      true
  """
  def compress(%__MODULE__{} = pattern, start_time, end_time)
      when is_number(start_time) and is_number(end_time) and start_time < end_time do
    span = end_time - start_time

    new(fn cycle ->
      pattern
      |> query(cycle)
      |> Enum.map(fn event ->
        %{event | time: start_time + event.time * span, duration: event.duration * span}
      end)
      |> Enum.filter(fn event -> event.time < 1.0 end)
    end)
  end

  @doc """
  Zoom into a portion of the pattern and expand it to fill the cycle.

  `zoom(0.0, 0.5)` takes the first half of the pattern and stretches it.
  `zoom(0.25, 0.75)` extracts the middle portion and expands it.

  The inverse of `compress`.

  ## Examples

      iex> p = QueryPattern.fastcat([
      ...>   QueryPattern.pure("bd"),
      ...>   QueryPattern.pure("sd"),
      ...>   QueryPattern.pure("hh"),
      ...>   QueryPattern.pure("cp")
      ...> ])
      iex> zoomed = QueryPattern.zoom(p, 0.0, 0.5)
      iex> events = QueryPattern.query(zoomed, 0)
      iex> length(events)
      2
  """
  def zoom(%__MODULE__{} = pattern, start_time, end_time)
      when is_number(start_time) and is_number(end_time) and start_time < end_time do
    span = end_time - start_time

    new(fn cycle ->
      pattern
      |> query(cycle)
      |> Enum.filter(fn event ->
        event.time >= start_time and event.time < end_time
      end)
      |> Enum.map(fn event ->
        new_time = (event.time - start_time) / span
        new_duration = event.duration / span
        %{event | time: new_time, duration: new_duration}
      end)
    end)
  end

  @doc """
  Repeat the first portion of a pattern to fill the whole cycle.

  `linger(0.5)` takes the first half and repeats it twice.
  `linger(0.25)` takes the first quarter and repeats it 4 times.

  Creates hypnotic, looping effects by focusing on a small fragment.

  ## Examples

      iex> p = QueryPattern.fastcat([
      ...>   QueryPattern.pure("bd"),
      ...>   QueryPattern.pure("sd"),
      ...>   QueryPattern.pure("hh"),
      ...>   QueryPattern.pure("cp")
      ...> ])
      iex> lingered = QueryPattern.linger(p, 0.5)
      iex> events = QueryPattern.query(lingered, 0)
      iex> length(events)
      4
  """
  def linger(%__MODULE__{} = pattern, fraction)
      when is_number(fraction) and fraction > 0.0 and fraction <= 1.0 do
    repetitions = round(1.0 / fraction)

    new(fn cycle ->
      # Get events in the first 'fraction' of the pattern
      extracted =
        pattern
        |> query(cycle)
        |> Enum.filter(fn event -> event.time < fraction end)

      # Repeat them to fill the cycle
      for rep <- 0..(repetitions - 1) do
        offset = rep * fraction

        Enum.map(extracted, fn event ->
          %{event | time: event.time + offset}
        end)
      end
      |> List.flatten()
      |> Enum.sort_by(& &1.time)
    end)
  end

  # ============================================================================
  # Structure Modifiers
  # ============================================================================

  @doc """
  Reverse the pattern within each cycle.
  """
  def rev(%__MODULE__{} = pattern) do
    new(fn cycle ->
      pattern
      |> query(cycle)
      |> Enum.map(fn event ->
        # Flip time: 0.0 -> 1.0, 0.25 -> 0.75, etc.
        %{event | time: 1.0 - event.time - event.duration}
      end)
      |> Enum.sort_by(& &1.time)
    end)
  end

  @doc """
  Create a palindrome pattern (forward then backward within each cycle).
  """
  def palindrome(%__MODULE__{} = pattern) do
    fastcat([pattern, rev(pattern)])
  end

  @doc """
  Apply rhythmic structure from a structural pattern.

  Uses a pattern to determine which events from the source pattern are kept.
  Events in the structure pattern with non-rest values mark positions to keep.
  """
  def struct_fn(%__MODULE__{} = pattern, %__MODULE__{} = structure) do
    new(fn cycle ->
      pattern_events = query(pattern, cycle)
      struct_events = query(structure, cycle)

      Enum.filter(pattern_events, fn event ->
        # Keep event if there's a struct event at similar time
        Enum.any?(struct_events, fn struct_event ->
          abs(event.time - struct_event.time) < 0.001
        end)
      end)
    end)
  end

  @doc """
  Silence events based on a mask pattern.

  Events are kept only where the mask pattern has events.
  """
  def mask(%__MODULE__{} = pattern, %__MODULE__{} = mask_pattern) do
    struct_fn(pattern, mask_pattern)
  end

  @doc """
  Randomly remove events with a given probability.

  Uses cycle number as seed for deterministic randomness.
  """
  def degrade_by(%__MODULE__{} = pattern, probability)
      when is_float(probability) and probability >= 0.0 and probability <= 1.0 do
    new(fn cycle ->
      :rand.seed(:exsss, {cycle, cycle * 7, cycle * 13})

      pattern
      |> query(cycle)
      |> Enum.filter(fn _event -> :rand.uniform() > probability end)
    end)
  end

  @doc """
  Randomly remove ~50% of events.
  """
  def degrade(%__MODULE__{} = pattern) do
    degrade_by(pattern, 0.5)
  end

  @doc """
  Create a stereo effect by playing original and transformed versions in different ears.

  Original plays on the left, transformed version plays on the right.
  """
  def jux(%__MODULE__{} = pattern, fun) when is_function(fun, 1) do
    jux_by(pattern, 1.0, fun)
  end

  @doc """
  Apply a function to create a partial stereo effect.

  Amount controls pan separation (0.0 = no effect, 1.0 = full stereo).
  """
  def jux_by(%__MODULE__{} = pattern, amount, fun)
      when is_number(amount) and amount >= 0.0 and amount <= 1.0 and is_function(fun, 1) do
    # Pan left uses negative pan, right uses positive
    left_pan = 0.5 - amount / 2
    right_pan = 0.5 + amount / 2

    left_pattern = pan(pattern, left_pan)
    right_pattern = pattern |> fun.() |> pan(right_pan)

    stack([left_pattern, right_pattern])
  end

  @doc """
  Layer the original pattern with a transformed copy of itself.

  Superimpose is perfect for creating thickness and movement
  by combining the original with a modified version.

  ## Examples

      iex> p = QueryPattern.pure("bd") |> QueryPattern.superimpose(&QueryPattern.fast(&1, 2))
      iex> events = QueryPattern.query(p, 0)
      iex> length(events)
      3
  """
  def superimpose(%__MODULE__{} = pattern, fun) when is_function(fun, 1) do
    stack([pattern, fun.(pattern)])
  end

  @doc """
  Superimpose a delayed and transformed copy of the pattern.

  The transformed copy is offset by the given time amount.

  ## Examples

      iex> p = QueryPattern.pure("bd") |> QueryPattern.off(0.25, &QueryPattern.gain(&1, 0.5))
      iex> events = QueryPattern.query(p, 0)
      iex> length(events)
      2
  """
  def off(%__MODULE__{} = pattern, time_offset, fun)
      when is_number(time_offset) and is_function(fun, 1) do
    transformed = pattern |> fun.() |> late(time_offset)
    stack([pattern, transformed])
  end

  @doc """
  Create rhythmic echoes that fade out over time.

  Unlike the `delay` effect (which uses the audio engine), `echo`
  creates actual copies of events in the pattern, each quieter
  than the last.

  ## Examples

      iex> p = QueryPattern.pure("bd") |> QueryPattern.echo(3, 0.125, 0.5)
      iex> events = QueryPattern.query(p, 0)
      iex> length(events)
      4
  """
  def echo(%__MODULE__{} = pattern, n, time_offset, gain_factor)
      when is_integer(n) and n > 0 and is_number(time_offset) and
             is_number(gain_factor) and gain_factor >= 0.0 and gain_factor <= 1.0 do
    new(fn cycle ->
      base_events = query(pattern, cycle)

      echoes =
        for i <- 1..n do
          offset = time_offset * i
          gain_mult = :math.pow(gain_factor, i)

          Enum.map(base_events, fn e ->
            new_time = e.time + offset
            wrapped_time = new_time - Float.floor(new_time)
            current_gain = Map.get(e.params, :gain, 1.0)

            %{e | time: wrapped_time, params: Map.put(e.params, :gain, current_gain * gain_mult)}
          end)
        end
        |> List.flatten()

      Enum.sort_by(base_events ++ echoes, & &1.time)
    end)
  end

  @doc """
  Slice pattern into N parts and interleave them (stutter effect).

  ## Examples

      iex> p = QueryPattern.pure("bd") |> QueryPattern.striate(4)
      iex> events = QueryPattern.query(p, 0)
      iex> length(events)
      4
  """
  def striate(%__MODULE__{} = pattern, n) when is_integer(n) and n > 1 do
    new(fn cycle ->
      pattern
      |> query(cycle)
      |> Enum.flat_map(fn event ->
        slice_duration = event.duration / n

        for i <- 0..(n - 1) do
          %{event | time: event.time + i * slice_duration, duration: slice_duration}
        end
      end)
      |> Enum.sort_by(& &1.time)
    end)
  end

  @doc """
  Chop pattern into N pieces.

  Divides each event into N equal parts.

  ## Examples

      iex> p = QueryPattern.pure("bd") |> QueryPattern.chop(4)
      iex> events = QueryPattern.query(p, 0)
      iex> length(events)
      4
  """
  def chop(%__MODULE__{} = pattern, n) when is_integer(n) and n > 1 do
    new(fn cycle ->
      pattern
      |> query(cycle)
      |> Enum.flat_map(fn event ->
        piece_duration = event.duration / n

        for i <- 0..(n - 1) do
          %{event | time: event.time + i * piece_duration, duration: piece_duration}
        end
      end)
      |> Enum.sort_by(& &1.time)
    end)
  end

  # ============================================================================
  # Conditional Modifiers
  # ============================================================================

  @doc """
  Apply a function every n cycles.

  ## Examples

      iex> p = QueryPattern.pure("bd")
      ...>     |> QueryPattern.every(2, &QueryPattern.fast(&1, 2))
      iex> length(QueryPattern.query(p, 0))  # cycle 0: fast applied
      2
      iex> length(QueryPattern.query(p, 1))  # cycle 1: no change
      1
  """
  def every(%__MODULE__{} = pattern, n, fun) when n > 0 and is_function(fun, 1) do
    new(fn cycle ->
      if rem(cycle, n) == 0 do
        pattern |> fun.() |> query(cycle)
      else
        query(pattern, cycle)
      end
    end)
  end

  @doc """
  Apply a function every n cycles, starting at a given offset.

  - `every(pattern, 4, 0, f)` - apply on cycles 0, 4, 8, 12...
  - `every(pattern, 4, 1, f)` - apply on cycles 1, 5, 9, 13...
  """
  def every(%__MODULE__{} = pattern, n, offset, fun)
      when is_integer(n) and n > 0 and is_integer(offset) and offset >= 0 and offset < n and
             is_function(fun, 1) do
    new(fn cycle ->
      if rem(cycle, n) == offset do
        pattern |> fun.() |> query(cycle)
      else
        query(pattern, cycle)
      end
    end)
  end

  @doc """
  Apply a function with a given probability per cycle.

  Uses cycle number as random seed for deterministic but varied behavior.
  """
  def sometimes_by(%__MODULE__{} = pattern, probability, fun)
      when is_float(probability) and probability >= 0.0 and probability <= 1.0 and
             is_function(fun, 1) do
    new(fn cycle ->
      # Seed with cycle for deterministic behavior
      :rand.seed(:exsss, {cycle, cycle * 7, cycle * 13})

      if :rand.uniform() < probability do
        pattern |> fun.() |> query(cycle)
      else
        query(pattern, cycle)
      end
    end)
  end

  @doc """
  Apply a transformation 50% of the time.
  """
  def sometimes(%__MODULE__{} = pattern, fun) when is_function(fun, 1) do
    sometimes_by(pattern, 0.5, fun)
  end

  @doc """
  Apply a transformation 75% of the time.
  """
  def often(%__MODULE__{} = pattern, fun) when is_function(fun, 1) do
    sometimes_by(pattern, 0.75, fun)
  end

  @doc """
  Apply a transformation 25% of the time.
  """
  def rarely(%__MODULE__{} = pattern, fun) when is_function(fun, 1) do
    sometimes_by(pattern, 0.25, fun)
  end

  @doc """
  Rotate the pattern's starting point each cycle.

  Creates evolving grooves that shift phase over time.

  ## Examples

      iex> p = QueryPattern.fastcat([
      ...>   QueryPattern.pure("bd"),
      ...>   QueryPattern.pure("sd"),
      ...>   QueryPattern.pure("hh"),
      ...>   QueryPattern.pure("cp")
      ...> ]) |> QueryPattern.iter(4)
      iex> # Cycle 0: bd sd hh cp
      iex> # Cycle 1: sd hh cp bd (rotated by 1)
  """
  def iter(%__MODULE__{} = pattern, n) when is_integer(n) and n > 0 do
    new(fn cycle ->
      # Calculate rotation amount based on cycle
      rotation = rem(cycle, n)

      if rotation == 0 do
        query(pattern, cycle)
      else
        # Shift pattern early by rotation/n of the cycle
        pattern |> early(rotation / n) |> query(cycle)
      end
    end)
  end

  @doc """
  Rotate the pattern start position backwards each cycle.

  Like iter/2 but rotates in reverse.
  """
  def iter_back(%__MODULE__{} = pattern, n) when is_integer(n) and n > 0 do
    new(fn cycle ->
      rotation = rem(cycle, n)

      if rotation == 0 do
        query(pattern, cycle)
      else
        # Rotate backwards
        backward_rotation = n - rotation
        pattern |> early(backward_rotation / n) |> query(cycle)
      end
    end)
  end

  @doc """
  Apply a function on the first cycle of every N cycles.

  Applies on cycles where (cycle mod n) == 0.
  """
  def first_of(%__MODULE__{} = pattern, n, fun)
      when is_integer(n) and n > 0 and is_function(fun, 1) do
    every(pattern, n, 0, fun)
  end

  @doc """
  Apply a function on the last cycle of every N cycles.

  Applies on cycles where (cycle mod n) == (n - 1).
  """
  def last_of(%__MODULE__{} = pattern, n, fun)
      when is_integer(n) and n > 0 and is_function(fun, 1) do
    every(pattern, n, n - 1, fun)
  end

  @doc """
  Apply a function when a condition function returns true.

  The condition function receives the cycle number.
  """
  def when_fn(%__MODULE__{} = pattern, condition_fn, fun)
      when is_function(condition_fn, 1) and is_function(fun, 1) do
    new(fn cycle ->
      if condition_fn.(cycle) do
        pattern |> fun.() |> query(cycle)
      else
        query(pattern, cycle)
      end
    end)
  end

  @doc """
  Divide pattern into N parts, applying function to each part in turn per cycle.

  On cycle 0, the function is applied to part 0. On cycle 1, to part 1, etc.
  """
  def chunk(%__MODULE__{} = pattern, n, fun)
      when is_integer(n) and n > 0 and is_function(fun, 1) do
    new(fn cycle ->
      chunk_index = rem(cycle, n)
      chunk_start = chunk_index / n
      chunk_end = (chunk_index + 1) / n

      events = query(pattern, cycle)

      # Apply function to events within the target chunk
      Enum.map(events, fn event ->
        if event.time >= chunk_start and event.time < chunk_end do
          # Create a temporary pattern for just this event, apply func, extract
          temp_pattern = from_events([event])

          case query(fun.(temp_pattern), cycle) do
            [transformed] -> transformed
            _ -> event
          end
        else
          event
        end
      end)
    end)
  end

  @doc """
  Like chunk/3 but cycles through parts in reverse order.
  """
  def chunk_back(%__MODULE__{} = pattern, n, fun)
      when is_integer(n) and n > 0 and is_function(fun, 1) do
    new(fn cycle ->
      # Reverse chunk index
      chunk_index = n - 1 - rem(cycle, n)
      chunk_start = chunk_index / n
      chunk_end = (chunk_index + 1) / n

      events = query(pattern, cycle)

      Enum.map(events, fn event ->
        if event.time >= chunk_start and event.time < chunk_end do
          temp_pattern = from_events([event])

          case query(fun.(temp_pattern), cycle) do
            [transformed] -> transformed
            _ -> event
          end
        else
          event
        end
      end)
    end)
  end

  # ============================================================================
  # Effects (Parameter Setting)
  # ============================================================================

  @doc """
  Set a parameter on all events in the pattern.
  """
  def set_param(%__MODULE__{} = pattern, key, value) do
    new(fn cycle ->
      pattern
      |> query(cycle)
      |> Enum.map(fn event ->
        %{event | params: Map.put(event.params, key, value)}
      end)
    end)
  end

  @doc "Set gain parameter (0.0 to 1.0+)."
  def gain(pattern, value), do: set_param(pattern, :gain, value)

  @doc "Set pan parameter (0.0 left, 0.5 center, 1.0 right)."
  def pan(pattern, value), do: set_param(pattern, :pan, value)

  @doc "Set playback speed (1.0 = normal, 2.0 = double speed/octave up)."
  def speed(pattern, value), do: set_param(pattern, :speed, value)

  @doc "Set cut group - new events cut off previous ones in the same group."
  def cut(pattern, group), do: set_param(pattern, :cut, group)

  @doc "Set reverb amount (0.0 = dry, 1.0 = fully wet)."
  def room(pattern, value), do: set_param(pattern, :room, value)

  @doc "Set delay amount (0.0 = dry, 1.0 = fully delayed)."
  def delay(pattern, value), do: set_param(pattern, :delay, value)

  @doc "Set low-pass filter cutoff frequency (Hz)."
  def lpf(pattern, frequency), do: set_param(pattern, :lpf, frequency)

  @doc "Set high-pass filter cutoff frequency (Hz)."
  def hpf(pattern, frequency), do: set_param(pattern, :hpf, frequency)

  # ============================================================================
  # Rhythm
  # ============================================================================

  @doc """
  Create a Euclidean rhythm - evenly distributing pulses across steps.

  Euclidean rhythms are found in music worldwide, from African
  polyrhythms to Cuban clave patterns.

  Common patterns:
  - `euclid(3, 8)` - Cuban tresillo / breakbeat feel
  - `euclid(5, 8)` - Cinquillo rhythm
  - `euclid(7, 12)` - West African bell pattern

  ## Examples

      iex> p = QueryPattern.pure("bd") |> QueryPattern.euclid(3, 8)
      iex> events = QueryPattern.query(p, 0)
      iex> length(events)
      3
  """
  def euclid(%__MODULE__{} = pattern, pulses, steps)
      when is_integer(pulses) and is_integer(steps) and pulses >= 0 and steps > 0 and
             pulses <= steps do
    rhythm = euclidean_rhythm(pulses, steps)
    step_size = 1.0 / steps

    new(fn cycle ->
      base_events = query(pattern, cycle)

      rhythm
      |> Enum.with_index()
      |> Enum.flat_map(fn {hit, idx} ->
        if hit == 1 do
          Enum.map(base_events, fn event ->
            %{event | time: idx * step_size, duration: step_size}
          end)
        else
          []
        end
      end)
      |> Enum.sort_by(& &1.time)
    end)
  end

  @doc """
  Create a Euclidean rhythm with rotation offset.

  Same as `euclid/3` but shifts the starting point by `offset` steps.
  """
  def euclid_rot(%__MODULE__{} = pattern, pulses, steps, offset)
      when is_integer(pulses) and is_integer(steps) and is_integer(offset) and
             pulses >= 0 and steps > 0 and pulses <= steps do
    rhythm = euclidean_rhythm(pulses, steps)
    rotated = Enum.drop(rhythm, offset) ++ Enum.take(rhythm, offset)
    step_size = 1.0 / steps

    new(fn cycle ->
      base_events = query(pattern, cycle)

      rotated
      |> Enum.with_index()
      |> Enum.flat_map(fn {hit, idx} ->
        if hit == 1 do
          Enum.map(base_events, fn event ->
            %{event | time: idx * step_size, duration: step_size}
          end)
        else
          []
        end
      end)
      |> Enum.sort_by(& &1.time)
    end)
  end

  @doc """
  Add swing feel by delaying off-beat notes.

  Swing pushes the upbeats later, creating that "shuffle" or "groove"
  feel found in jazz, hip-hop, and house music.

  ## Examples

      iex> p = QueryPattern.fastcat([
      ...>   QueryPattern.pure("hh"),
      ...>   QueryPattern.pure("hh"),
      ...>   QueryPattern.pure("hh"),
      ...>   QueryPattern.pure("hh")
      ...> ]) |> QueryPattern.swing(4)
      iex> events = QueryPattern.query(p, 0)
      iex> length(events)
      4
  """
  def swing(%__MODULE__{} = pattern, n) when is_integer(n) and n > 0 do
    swing_by(pattern, 1 / 3, n)
  end

  @doc """
  Add swing with adjustable amount.

  - `amount` controls how much swing (0.0 = straight, 0.5 = heavy swing)
  - `n` sets the subdivision for swing timing
  """
  def swing_by(%__MODULE__{} = pattern, amount, n)
      when is_number(amount) and is_integer(n) and n > 0 do
    slice_size = 1.0 / n

    new(fn cycle ->
      pattern
      |> query(cycle)
      |> Enum.map(fn event ->
        slice_idx = floor(event.time / slice_size)
        position_in_slice = event.time - slice_idx * slice_size
        half_slice = slice_size / 2

        if position_in_slice >= half_slice do
          delay_amount = amount * half_slice
          new_time = event.time + delay_amount
          wrapped_time = new_time - Float.floor(new_time)
          %{event | time: wrapped_time}
        else
          event
        end
      end)
      |> Enum.sort_by(& &1.time)
    end)
  end

  # Bjorklund's algorithm for generating Euclidean rhythms
  defp euclidean_rhythm(pulses, _steps) when pulses == 0, do: []
  defp euclidean_rhythm(pulses, steps) when pulses == steps, do: List.duplicate(1, steps)

  defp euclidean_rhythm(pulses, steps) do
    ones = List.duplicate([1], pulses)
    zeros = List.duplicate([0], steps - pulses)
    bjorklund(ones, zeros) |> List.flatten()
  end

  defp bjorklund([], zeros), do: zeros
  defp bjorklund(ones, []), do: ones

  defp bjorklund(ones, zeros) when length(ones) <= length(zeros) do
    pairs = Enum.zip(ones, zeros) |> Enum.map(fn {a, b} -> a ++ b end)
    remaining = Enum.drop(zeros, length(ones))

    if remaining == [] do
      pairs
    else
      bjorklund(pairs, remaining)
    end
  end

  defp bjorklund(ones, zeros) do
    pairs = Enum.zip(zeros, ones) |> Enum.map(fn {a, b} -> a ++ b end)
    remaining = Enum.drop(ones, length(zeros))

    if remaining == [] do
      pairs
    else
      bjorklund(remaining, pairs)
    end
  end

  # ============================================================================
  # Query
  # ============================================================================

  @doc """
  Query the pattern for events at a specific cycle.

  Returns a list of events with time values in [0, 1).
  """
  def query(%__MODULE__{query: query_fn}, cycle) when is_integer(cycle) and cycle >= 0 do
    query_fn.(cycle)
  end

  def query(nil, _cycle), do: []

  @doc """
  Query the pattern and convert to scheduler format.

  Returns events as maps with :time, :s, :n, :dur, etc.
  """
  def query_for_scheduler(%__MODULE__{} = pattern, cycle) do
    pattern
    |> query(cycle)
    |> Enum.map(&event_to_scheduler_map/1)
  end

  defp event_to_scheduler_map(%Event{} = event) do
    %{
      time: event.time,
      s: event.sound,
      n: event.sample,
      dur: event.duration,
      source_start: event.source_start,
      source_end: event.source_end
    }
    |> Map.merge(event.params)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # ============================================================================
  # Transport Serialization (for Web Audio path)
  # ============================================================================

  @doc """
  Expand a pattern for transport to the browser.

  Pre-computes events for `num_cycles` cycles, returning a map keyed by cycle number.
  This is used for the Web Audio path where the browser scheduler needs pre-expanded
  events rather than a query function.

  ## Options

  - `:num_cycles` - Number of cycles to expand (default: 16)

  ## Examples

      iex> p = QueryPattern.slowcat([QueryPattern.pure("bd"), QueryPattern.pure("sd")])
      iex> expanded = QueryPattern.expand_for_transport(p)
      iex> Map.keys(expanded.cycles)
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
      iex> hd(expanded.cycles[0]).s
      "bd"
      iex> hd(expanded.cycles[1]).s
      "sd"
  """
  def expand_for_transport(%__MODULE__{} = pattern, opts \\ []) do
    num_cycles = Keyword.get(opts, :num_cycles, 16)

    cycles =
      0..(num_cycles - 1)
      |> Enum.map(fn cycle ->
        events = query_for_scheduler(pattern, cycle)
        {cycle, events}
      end)
      |> Map.new()

    %{
      cycles: cycles,
      num_cycles: num_cycles
    }
  end

  @doc """
  Detect the repetition period of a pattern.

  Finds the smallest number of cycles after which the pattern repeats.
  Useful for optimizing transport - we only need to send one full period.

  Returns the period length, or `nil` if no repetition found within `max_cycles`.

  ## Examples

      iex> p = QueryPattern.slowcat([QueryPattern.pure("bd"), QueryPattern.pure("sd")])
      iex> QueryPattern.detect_period(p)
      2

      iex> p = QueryPattern.pure("bd")
      iex> QueryPattern.detect_period(p)
      1
  """
  def detect_period(%__MODULE__{} = pattern, max_cycles \\ 64) do
    # Get cycle 0 as reference
    cycle_0 = query_for_scheduler(pattern, 0)

    # Find first cycle that matches cycle 0
    1..max_cycles
    |> Enum.find(fn cycle ->
      query_for_scheduler(pattern, cycle) == cycle_0
    end)
  end

  @doc """
  Expand a pattern for transport, automatically detecting period.

  Uses `detect_period/2` to find the shortest repeating unit,
  then only expands that many cycles.

  ## Examples

      iex> p = QueryPattern.slowcat([QueryPattern.pure("bd"), QueryPattern.pure("sd")])
      iex> expanded = QueryPattern.expand_for_transport_auto(p)
      iex> expanded.num_cycles
      2
      iex> expanded.period
      2
  """
  def expand_for_transport_auto(%__MODULE__{} = pattern, opts \\ []) do
    max_cycles = Keyword.get(opts, :max_cycles, 64)
    min_cycles = Keyword.get(opts, :min_cycles, 1)

    period = detect_period(pattern, max_cycles) || max_cycles
    num_cycles = max(period, min_cycles)

    cycles =
      0..(num_cycles - 1)
      |> Enum.map(fn cycle ->
        events = query_for_scheduler(pattern, cycle)
        {cycle, events}
      end)
      |> Map.new()

    %{
      cycles: cycles,
      num_cycles: num_cycles,
      period: period
    }
  end
end
