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

  ## Submodules

  Functions are organized into logical submodules:
  - `Pattern.Time` - fast, slow, early, late, ply, compress, zoom, linger
  - `Pattern.Structure` - rev, palindrome, struct_fn, mask, degrade, jux, superimpose, off, echo, striate, chop
  - `Pattern.Conditional` - every, sometimes, often, rarely, iter, first_of, last_of, when_fn, chunk
  - `Pattern.Effects` - set_param, gain, pan, speed, cut, room, delay, lpf, hpf
  - `Pattern.Rhythm` - euclid, euclid_rot, swing, swing_by
  - `Pattern.Signal` - sine, saw, tri, square, rand, range, segment
  - `Pattern.Harmony` - form, scale (harmonic transformations)
  """

  alias UzuPattern.Event
  alias UzuPattern.Pattern.{Time, Structure, Conditional, Effects, Rhythm, Signal, Harmony}

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
  Create a pattern from a query function or mini-notation string.

  ## With query function

  The query function takes a cycle number and returns events for that cycle.
  Events should have time values in [0, 1) representing position within the cycle.

  ## With mini-notation string

  Parses the string and interprets it into a Pattern.

  ## Examples

      # From query function
      iex> pattern = Pattern.new(fn _cycle -> [%Event{sound: "bd", time: 0.0, duration: 1.0}] end)

      # From string
      iex> pattern = Pattern.new("bd sd hh")
      iex> events = Pattern.events(pattern)
      iex> length(events)
      3
  """
  def new(query_fn) when is_function(query_fn, 1) do
    %__MODULE__{query: query_fn, metadata: %{}}
  end

  def new(source) when is_binary(source) do
    UzuPattern.parse(source)
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
  # Time Modifiers (delegated to Pattern.Time)
  # ============================================================================

  defdelegate fast(pattern, factor), to: Time
  defdelegate slow(pattern, factor), to: Time
  defdelegate early(pattern, amount), to: Time
  defdelegate late(pattern, amount), to: Time
  defdelegate ply(pattern, n), to: Time
  defdelegate compress(pattern, start_time, end_time), to: Time
  defdelegate zoom(pattern, start_time, end_time), to: Time
  defdelegate linger(pattern, fraction), to: Time

  # ============================================================================
  # Structure Modifiers (delegated to Pattern.Structure)
  # ============================================================================

  defdelegate rev(pattern), to: Structure
  defdelegate palindrome(pattern), to: Structure
  defdelegate struct_fn(pattern, structure), to: Structure
  defdelegate mask(pattern, mask_pattern), to: Structure
  defdelegate degrade_by(pattern, probability), to: Structure
  defdelegate degrade(pattern), to: Structure
  defdelegate jux(pattern, fun), to: Structure
  defdelegate jux_by(pattern, amount, fun), to: Structure
  defdelegate superimpose(pattern, fun), to: Structure
  defdelegate off(pattern, time_offset, fun), to: Structure
  defdelegate echo(pattern, n, time_offset, gain_factor), to: Structure
  defdelegate striate(pattern, n), to: Structure
  defdelegate chop(pattern, n), to: Structure

  # ============================================================================
  # Conditional Modifiers (delegated to Pattern.Conditional)
  # ============================================================================

  defdelegate every(pattern, n, fun), to: Conditional
  defdelegate every(pattern, n, offset, fun), to: Conditional
  defdelegate sometimes_by(pattern, probability, fun), to: Conditional
  defdelegate sometimes(pattern, fun), to: Conditional
  defdelegate often(pattern, fun), to: Conditional
  defdelegate rarely(pattern, fun), to: Conditional
  defdelegate iter(pattern, n), to: Conditional
  defdelegate iter_back(pattern, n), to: Conditional
  defdelegate first_of(pattern, n, fun), to: Conditional
  defdelegate last_of(pattern, n, fun), to: Conditional
  defdelegate when_fn(pattern, condition_fn, fun), to: Conditional
  defdelegate chunk(pattern, n, fun), to: Conditional
  defdelegate chunk_back(pattern, n, fun), to: Conditional

  # ============================================================================
  # Effects (delegated to Pattern.Effects)
  # ============================================================================

  defdelegate set_param(pattern, key, value), to: Effects
  defdelegate gain(pattern, value), to: Effects
  defdelegate pan(pattern, value), to: Effects
  defdelegate speed(pattern, value), to: Effects
  defdelegate cut(pattern, group), to: Effects
  defdelegate room(pattern, value), to: Effects
  defdelegate delay(pattern, value), to: Effects
  defdelegate lpf(pattern, frequency), to: Effects
  defdelegate hpf(pattern, frequency), to: Effects

  # ============================================================================
  # Rhythm (delegated to Pattern.Rhythm)
  # ============================================================================

  defdelegate euclid(pattern, pulses, steps), to: Rhythm
  defdelegate euclid_rot(pattern, pulses, steps, offset), to: Rhythm
  defdelegate swing(pattern, n), to: Rhythm
  defdelegate swing_by(pattern, amount, n), to: Rhythm

  # ============================================================================
  # Signal (delegated to Pattern.Signal)
  # ============================================================================

  # Signal constructors (no pattern argument - these create new patterns)
  defdelegate signal(time_fn), to: Signal
  defdelegate sine(), to: Signal
  defdelegate saw(), to: Signal
  defdelegate isaw(), to: Signal
  defdelegate tri(), to: Signal
  defdelegate square(), to: Signal
  defdelegate rand(), to: Signal
  defdelegate irand(n), to: Signal

  # Signal operations
  defdelegate range(pattern, min, max), to: Signal
  defdelegate rangex(pattern, min, max), to: Signal
  defdelegate segment(pattern, n), to: Signal
  defdelegate with_value(pattern, value_fn), to: Signal
  defdelegate sample_at(pattern, time), to: Signal

  # ============================================================================
  # Harmony Delegations
  # ============================================================================

  defdelegate form(song_name), to: Harmony
  defdelegate scale(pattern, scale_name), to: Harmony
  defdelegate scale(pattern), to: Harmony

  # ============================================================================
  # Visualization Delegations
  # ============================================================================

  alias UzuPattern.Pattern.Visualization

  defdelegate pianoroll(pattern, opts \\ []), to: Visualization
  defdelegate spiral(pattern, opts \\ []), to: Visualization
  defdelegate punchcard(pattern, opts \\ []), to: Visualization
  defdelegate spectrum(pattern, opts \\ []), to: Visualization
  defdelegate scope(pattern, opts \\ []), to: Visualization
  defdelegate get_painters(pattern), to: Visualization
  defdelegate has_painters?(pattern), to: Visualization

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
