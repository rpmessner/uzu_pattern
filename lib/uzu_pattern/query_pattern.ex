defmodule UzuPattern.QueryPattern do
  @moduledoc """
  Query-based pattern representation for composable live coding patterns.

  Unlike the event-list based Pattern, QueryPattern stores a query function
  that is evaluated lazily when events are needed for a specific cycle.
  This enables proper composition of patterns including nested alternation.

  ## Core Concept

  A pattern is a function: `cycle -> [Event]`

  This allows patterns to be composed without expanding all events upfront:
  - `slowcat([p1, p2, p3])` - alternates patterns across cycles
  - `fastcat([p1, p2, p3])` - sequences patterns within a cycle
  - `stack([p1, p2, p3])` - layers patterns simultaneously

  ## Examples

      # Create a simple pattern
      p = QueryPattern.pure("bd")

      # Create a sequence (plays within one cycle)
      p = QueryPattern.fastcat([
        QueryPattern.pure("bd"),
        QueryPattern.pure("sd")
      ])

      # Create alternation (one per cycle)
      p = QueryPattern.slowcat([
        QueryPattern.fastcat([QueryPattern.pure("bd"), QueryPattern.pure("sd")]),
        QueryPattern.fastcat([QueryPattern.pure("hh"), QueryPattern.pure("cp")])
      ])

      # Query for events
      events = QueryPattern.query(p, 0)  # cycle 0: bd, sd
      events = QueryPattern.query(p, 1)  # cycle 1: hh, cp
  """

  alias UzuParser.Event

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

  @doc "Set gain parameter."
  def gain(pattern, value), do: set_param(pattern, :gain, value)

  @doc "Set pan parameter."
  def pan(pattern, value), do: set_param(pattern, :pan, value)

  @doc "Set speed parameter."
  def speed(pattern, value), do: set_param(pattern, :speed, value)

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
