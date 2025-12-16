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

  alias UzuPattern.Hap
  alias UzuPattern.Time
  alias UzuPattern.TimeSpan
  alias UzuPattern.Pattern.{Starters, Time, Structure, Conditional, Effects, Rhythm, Signal, Harmony, Algebra}
  alias UzuPattern.Time, as: T

  # Query function now takes a TimeSpan and returns haps for that span.
  # This enables pattern algebra operations that need to query arbitrary time ranges.
  @type query_fn :: (TimeSpan.t() -> [Hap.t()])

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

  The query function takes a TimeSpan and returns haps for that time range.
  Haps should have timing relative to the queried span.

  ## With mini-notation string

  Parses the string and interprets it into a Pattern.

  ## Examples

      # From query function (returns Haps)
      iex> pattern = Pattern.new(fn span -> [%Hap{whole: ..., part: ..., value: %{s: "bd"}, context: ...}] end)

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
  Create a pattern from a cycle-based query function.

  This is a convenience constructor for patterns that work in terms of integer
  cycles rather than arbitrary TimeSpans. The function receives a cycle number
  and should return haps with cycle-relative timing (0.0 to 1.0).

  Internally converts to span-based queries by:
  1. Splitting the query span by cycle boundaries
  2. Calling the cycle function for each cycle
  3. Shifting results to absolute time
  4. Filtering to the query span

  ## Examples

      iex> p = Pattern.from_cycles(fn cycle ->
      ...>   [%Hap{whole: %{begin: 0.0, end: 1.0}, part: %{begin: 0.0, end: 1.0},
      ...>         value: %{s: "bd", cycle: cycle}, context: %{}}]
      ...> end)
      iex> [hap] = Pattern.query(p, 3)
      iex> hap.value.cycle
      3
  """
  def from_cycles(cycle_fn) when is_function(cycle_fn, 1) do
    new(fn span ->
      TimeSpan.span_cycles(span)
      |> Enum.flat_map(fn cycle_span ->
        cycle = TimeSpan.cycle_of(cycle_span)

        cycle_fn.(cycle)
        |> Enum.map(fn hap -> shift_hap(hap, cycle) end)
        |> Enum.filter(fn hap ->
          # Filter to haps that intersect the query span
          TimeSpan.intersection(hap.part, cycle_span) != nil
        end)
      end)
    end)
  end

  # Helper for from_cycles - shift a hap by a cycle offset
  defp shift_hap(%Hap{} = hap, 0), do: hap

  defp shift_hap(%Hap{} = hap, offset) do
    %{hap | whole: shift_timespan(hap.whole, offset), part: shift_timespan(hap.part, offset)}
  end

  defp shift_timespan(nil, _offset), do: nil

  defp shift_timespan(%{begin: b, end: e}, offset) do
    o = T.ensure(offset)
    %{begin: T.add(b, o), end: T.add(e, o)}
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
    loc_start = Keyword.get(opts, :start)
    loc_end = Keyword.get(opts, :end)

    # Build value map: s is sound, n is sample (if present), plus params
    hap_value =
      %{s: value}
      |> maybe_put(:n, sample)
      |> Map.merge(params)

    # Build context from source location (Strudel convention: start/end)
    context =
      if loc_start != nil do
        %{locations: [%{start: loc_start, end: loc_end}], tags: []}
      else
        %{locations: [], tags: []}
      end

    new(fn span ->
      # For each cycle that the span covers, produce a hap at [cycle, cycle+1)
      TimeSpan.span_cycles(span)
      |> Enum.flat_map(fn cycle_span ->
        cycle = TimeSpan.cycle_of(cycle_span)
        # The whole event spans [cycle, cycle+1)
        whole = TimeSpan.new(cycle, cycle + 1)
        # The part is clipped to the query span
        case TimeSpan.intersection(whole, cycle_span) do
          nil -> []
          part -> [%Hap{whole: whole, part: part, value: hap_value, context: context}]
        end
      end)
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  @doc """
  Create an empty/silent pattern.
  """
  def silence do
    new(fn _span -> [] end)
  end

  @doc """
  Create a pattern from a list of pre-computed haps.

  The haps are assumed to have absolute timing. This filters and clips
  them to the query span.
  """
  def from_haps(haps) when is_list(haps) do
    new(fn span ->
      haps
      |> Enum.filter(fn hap ->
        # Check if hap intersects the query span
        TimeSpan.intersection(hap.part, span) != nil
      end)
      |> Enum.map(fn hap ->
        # Clip part to query span (whole stays the same for onset detection)
        case TimeSpan.intersection(hap.part, span) do
          nil -> nil
          clipped_part -> %{hap | part: clipped_part}
        end
      end)
      |> Enum.reject(&is_nil/1)
    end)
  end

  # Alias for backwards compat
  def from_events(haps), do: from_haps(haps)

  # ============================================================================
  # Context Modifiers
  # ============================================================================

  @doc """
  Add source location to a pattern's haps for highlighting.

  Locations are stored in `hap.context.locations` and survive pattern transforms.
  This is the Strudel-compatible way to track source positions.

  ## Examples

      iex> p = Pattern.pure("bd") |> Pattern.with_loc(15, 23)
      iex> [hap] = Pattern.query(p, 0)
      iex> hap.context.locations
      [%{start: 15, end: 23}]
  """
  def with_loc(%__MODULE__{} = pattern, start_pos, end_pos) do
    location = %{start: start_pos, end: end_pos}

    with_context(pattern, fn context ->
      locations = Map.get(context, :locations, [])
      Map.put(context, :locations, locations ++ [location])
    end)
  end

  @doc """
  Transform the context of all haps produced by a pattern.

  The context_fn receives the current context map and returns the new context.
  This is applied at query time, so it survives pattern transforms.

  ## Examples

      iex> p = Pattern.pure("bd")
      iex> p = Pattern.with_context(p, fn ctx -> Map.put(ctx, :color, "red") end)
      iex> [hap] = Pattern.query(p, 0)
      iex> hap.context.color
      "red"
  """
  def with_context(%__MODULE__{query: query} = pattern, context_fn) when is_function(context_fn, 1) do
    new_query = fn cycle ->
      query.(cycle)
      |> Enum.map(fn hap ->
        new_context = context_fn.(hap.context)
        %{hap | context: new_context}
      end)
    end

    %{pattern | query: new_query}
  end

  @doc """
  Add a global offset to all location positions in a pattern's haps.

  This adjusts existing locations (from mini-notation parsing) by adding
  the offset to their start/end positions. Applied at query time, so it
  survives pattern transforms like fast/slow.

  Use this when you know the global position of a pattern string in the
  source document and want highlighting to work correctly.

  ## Examples

      iex> p = Pattern.new("bd sd")  # locations at 0-2, 3-5 (relative)
      iex> p = Pattern.with_offset(p, 15)  # adjust to global positions
      iex> [hap1, _] = Pattern.query(p, 0)
      iex> [loc] = hap1.context.locations
      iex> {loc.start, loc.end}
      {15, 17}
  """
  def with_offset(%__MODULE__{} = pattern, offset) when is_integer(offset) do
    with_context(pattern, fn context ->
      case context do
        %{locations: locations} when is_list(locations) ->
          adjusted =
            Enum.map(locations, fn
              %{start: s, end: e} -> %{start: s + offset, end: e + offset}
              loc -> loc
            end)

          %{context | locations: adjusted}

        _ ->
          context
      end
    end)
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

    new(fn span ->
      # Split span by cycles and query appropriate pattern for each
      TimeSpan.span_cycles(span)
      |> Enum.flat_map(fn cycle_span ->
        cycle = TimeSpan.cycle_of(cycle_span)

        # Select pattern based on cycle, wrapping around
        index = rem(cycle, n)
        pattern = Enum.at(patterns, index)

        # Calculate local cycle for this pattern
        local_cycle = div(cycle, n)

        # Query the pattern with a span in its local time
        # Map [cycle, cycle+1) to [local_cycle, local_cycle+1)
        cycle_time = T.new(cycle)
        local_cycle_time = T.new(local_cycle)

        local_span = %{
          begin: T.add(local_cycle_time, T.sub(cycle_span.begin, cycle_time)),
          end: T.add(local_cycle_time, T.sub(cycle_span.end, cycle_time))
        }

        query_span(pattern, local_span)
        |> Enum.map(fn hap ->
          # Shift hap back to output time
          shift_offset = cycle - local_cycle
          shift_hap(hap, shift_offset)
        end)
      end)
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
    step = T.new(1, n)

    new(fn span ->
      # Split by cycle first
      TimeSpan.span_cycles(span)
      |> Enum.flat_map(fn cycle_span ->
        cycle = TimeSpan.cycle_of(cycle_span)
        cycle_time = T.new(cycle)

        patterns
        |> Enum.with_index()
        |> Enum.flat_map(fn {pattern, index} ->
          # This pattern occupies [cycle + index*step, cycle + (index+1)*step)
          slot_begin = T.add(cycle_time, T.mult(T.new(index), step))
          slot_end = T.add(cycle_time, T.mult(T.new(index + 1), step))
          slot_span = %{begin: slot_begin, end: slot_end}

          # Check if query span intersects this slot
          case TimeSpan.intersection(cycle_span, slot_span) do
            nil ->
              []

            intersected_span ->
              # Map the intersected span into the child pattern's time
              # The slot maps to a full cycle in the child pattern
              child_span = %{
                begin: T.add(cycle_time, T.divide(T.sub(intersected_span.begin, slot_begin), step)),
                end: T.add(cycle_time, T.divide(T.sub(intersected_span.end, slot_begin), step))
              }

              query_span(pattern, child_span)
              |> Enum.map(fn hap ->
                # Scale and shift hap from child time back to output time
                # offset = slot_begin - cycle * step
                offset = T.sub(slot_begin, T.mult(cycle_time, step))
                scale_hap(hap, step, offset)
              end)
              |> Enum.filter(fn hap ->
                # Filter to only haps that intersect the query
                TimeSpan.intersection(hap.part, cycle_span) != nil
              end)
          end
        end)
      end)
    end)
  end

  # Scale a hap's timespans by a factor and add an offset
  defp scale_hap(%Hap{} = hap, scale, offset) do
    %{
      hap
      | whole: scale_and_offset_timespan(hap.whole, scale, offset),
        part: scale_and_offset_timespan(hap.part, scale, offset)
    }
  end

  defp scale_and_offset_timespan(nil, _scale, _offset), do: nil

  defp scale_and_offset_timespan(%{begin: b, end: e}, scale, offset) do
    s = T.ensure(scale)
    o = T.ensure(offset)
    %{begin: T.add(o, T.mult(b, s)), end: T.add(o, T.mult(e, s))}
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
    new(fn span ->
      Enum.flat_map(patterns, fn pattern ->
        query_span(pattern, span)
      end)
    end)
  end

  # Variadic versions for convenience: stack(p1, p2) instead of stack([p1, p2])
  def stack(p1, p2), do: stack([p1, p2])
  def stack(p1, p2, p3), do: stack([p1, p2, p3])
  def stack(p1, p2, p3, p4), do: stack([p1, p2, p3, p4])

  # ============================================================================
  # Pattern Starters (delegated to Pattern.Starters)
  # ============================================================================

  defdelegate s(mini_notation), to: Starters
  defdelegate s(pattern, sound_name), to: Starters
  defdelegate sound(mini_notation), to: Starters
  defdelegate sound(pattern, sound_name), to: Starters
  defdelegate n(mini_notation), to: Starters
  defdelegate note(mini_notation), to: Starters

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
  # Algebra Delegations (Pattern algebra for composition)
  # ============================================================================

  # Functor
  defdelegate fmap(pattern, func), to: Algebra

  # Applicative
  defdelegate app_both(pat_func, pat_val), to: Algebra
  defdelegate app_left(pat_func, pat_val), to: Algebra
  defdelegate app_right(pat_func, pat_val), to: Algebra

  # Monad
  defdelegate bind(pattern, func), to: Algebra
  defdelegate bind_with(pattern, func, choose_whole), to: Algebra
  defdelegate join(pat_of_pats), to: Algebra
  defdelegate inner_bind(pattern, func), to: Algebra
  defdelegate inner_join(pat_of_pats), to: Algebra
  defdelegate outer_bind(pattern, func), to: Algebra
  defdelegate outer_join(pat_of_pats), to: Algebra
  defdelegate squeeze_bind(pattern, func), to: Algebra
  defdelegate squeeze_join(pat_of_pats), to: Algebra
  defdelegate focus_span(pattern, span), to: Algebra

  # ============================================================================
  # Harmony Delegations
  # ============================================================================

  defdelegate form(song_name), to: Harmony
  defdelegate scale(pattern, scale_name), to: Harmony
  defdelegate scale(pattern), to: Harmony
  defdelegate octave(pattern, octave_pattern), to: Harmony

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
  Query the pattern for events within a TimeSpan.

  This is the core query mechanism. All other query functions delegate to this.
  Returns haps with absolute timing within the queried span.

  ## Examples

      iex> pattern = Pattern.new("bd sd")
      iex> haps = Pattern.query_span(pattern, TimeSpan.new(0, 1))
      iex> length(haps)
      2
  """
  def query_span(%__MODULE__{query: query_fn}, %{begin: _, end: _} = span) do
    query_fn.(span)
  end

  def query_span(nil, _span), do: []

  @doc """
  Query the pattern for a time arc (Strudel-style).

  Takes a TimeSpan and returns haps with absolute timing.
  This is an alias for query_span for API compatibility.

  ## Examples

      iex> pattern = Pattern.new("bd sd")
      iex> haps = Pattern.query_arc(pattern, TimeSpan.new(0, 2))
      iex> length(haps)
      4
  """
  def query_arc(%__MODULE__{} = pattern, %{begin: _, end: _} = span) do
    query_span(pattern, span)
  end

  def query_arc(nil, _span), do: []

  @doc """
  Query the pattern for events at a specific cycle.

  Returns a list of haps with cycle-relative timing (values in [0, 1)).
  This is a convenience wrapper around query_span.

  For absolute timing, use `query_arc/2` or `query_span/2` instead.
  """
  def query(%__MODULE__{} = pattern, cycle) when is_integer(cycle) and cycle >= 0 do
    span = TimeSpan.new(cycle, cycle + 1)

    query_span(pattern, span)
    |> Enum.map(fn hap ->
      # Convert absolute timing back to cycle-relative [0, 1)
      shift_hap(hap, -cycle)
    end)
  end

  def query(nil, _cycle), do: []

  @doc """
  Query the pattern and return Haps as JSON-serializable maps.

  Preserves the Hap structure for proper client-side consumption:
  - whole: TimeSpan or null (for continuous)
  - part: TimeSpan
  - value: sound params (s, n, note, gain, etc.)
  - context: metadata (locations, tags)

  Times are normalized to be relative within the cycle (0.0-1.0).
  This allows the browser scheduler to wrap cycles without timing mismatches.
  """
  def query_for_scheduler(%__MODULE__{} = pattern, cycle) do
    span = TimeSpan.new(cycle, cycle + 1)

    pattern
    |> query_arc(span)
    |> Enum.map(&hap_to_json(&1, cycle))
  end

  @doc """
  Convert a Hap struct to a JSON-serializable map.

  The cycle parameter is used to normalize times to be relative (0.0-1.0).
  This is essential for cycle wrapping in the browser scheduler.
  """
  def hap_to_json(%Hap{} = hap, cycle \\ 0) do
    %{
      whole: timespan_to_json(hap.whole, cycle),
      part: timespan_to_json(hap.part, cycle),
      value: hap.value,
      context: %{
        locations: hap.context.locations || [],
        tags: hap.context.tags || []
      }
    }
  end

  defp timespan_to_json(nil, _cycle), do: nil

  defp timespan_to_json(%{begin: b, end: e}, cycle) do
    # Normalize to relative time within cycle (0.0-1.0) and convert to float
    cycle_time = T.new(cycle)
    %{begin: T.to_float(T.sub(b, cycle_time)), end: T.to_float(T.sub(e, cycle_time))}
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
    # Get cycle 0 as reference, normalized to remove absolute timing
    cycle_0 = normalize_cycle_content(query_for_scheduler(pattern, 0))

    # Find first cycle that matches cycle 0
    1..max_cycles
    |> Enum.find(fn cycle ->
      normalize_cycle_content(query_for_scheduler(pattern, cycle)) == cycle_0
    end)
  end

  # For period detection, only compare values (what sounds play)
  # Timing varies by cycle, so we ignore whole/part
  defp normalize_cycle_content(haps) do
    Enum.map(haps, fn hap -> hap.value end)
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
