defmodule UzuPattern.Pattern do
  @moduledoc """
  Pattern struct and transformation functions for Strudel.js-style live coding.

  A Pattern wraps events from UzuParser and provides transformation functions
  that can be chained together. Patterns support both immediate transformations
  (like `fast`, `slow`, `rev`) and cycle-aware transformations (like `every`).

  ## Creating Patterns

  ```elixir
  # From mini-notation string
  pattern = Pattern.new("bd sd hh cp")

  # From existing events
  pattern = Pattern.from_events(events)
  ```

  ## Chaining Transformations

  ```elixir
  "bd sd hh cp"
  |> Pattern.new()
  |> Pattern.fast(2)
  |> Pattern.rev()
  |> Pattern.every(4, &Pattern.slow(&1, 2))
  ```

  ## Querying for Events

  Use `query/2` to get events for a specific cycle:

  ```elixir
  events = Pattern.query(pattern, cycle_number)
  ```

  This resolves any cycle-aware transformations based on the cycle number.
  """

  alias UzuParser.Event

  @type t :: %__MODULE__{
          events: [Event.t()],
          transforms: [transform()]
        }

  @type transform ::
          {:every, pos_integer(), function()}
          | {:sometimes_by, float(), function()}
          | {:when, function(), function()}
          | {:iter, pos_integer()}
          | {:iter_back, pos_integer()}

  defstruct events: [],
            transforms: []

  # ============================================================================
  # Constructors
  # ============================================================================

  @doc """
  Create a new pattern from a mini-notation string.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh cp")
      iex> length(pattern.events)
      4
  """
  def new(source) when is_binary(source) do
    events = UzuParser.parse(source)
    %__MODULE__{events: events, transforms: []}
  end

  @doc """
  Create a pattern from an existing list of events.

  ## Examples

      iex> events = UzuParser.parse("bd sd")
      iex> pattern = Pattern.from_events(events)
      iex> length(pattern.events)
      2
  """
  def from_events(events) when is_list(events) do
    %__MODULE__{events: events, transforms: []}
  end

  # ============================================================================
  # Query / Extract
  # ============================================================================

  @doc """
  Query a pattern for events at a specific cycle.

  This resolves any cycle-aware transformations (like `every`) based on the
  cycle number and returns the final list of events.

  Returns events in the format expected by Waveform's PatternScheduler:
  `[{cycle_position, params}, ...]`

  ## Examples

      iex> pattern = Pattern.new("bd sd")
      iex> events = Pattern.query(pattern, 0)
      iex> length(events)
      2
  """
  def query(%__MODULE__{} = pattern, cycle) when is_integer(cycle) do
    # Apply cycle-aware transforms
    resolved = apply_transforms(pattern, cycle)

    # Convert to Waveform format: [{position, params}]
    Enum.map(resolved.events, &event_to_waveform_tuple/1)
  end

  @doc """
  Extract raw events from a pattern without resolving cycle-aware transforms.

  ## Examples

      iex> pattern = Pattern.new("bd sd")
      iex> events = Pattern.events(pattern)
      iex> hd(events).sound
      "bd"
  """
  def events(%__MODULE__{events: events}) do
    events
  end

  # Convert Event struct to Waveform tuple format
  defp event_to_waveform_tuple(%Event{} = event) do
    params =
      [s: event.sound]
      |> maybe_add(:n, event.sample)
      |> maybe_add(:dur, event.duration)
      |> Map.new()
      |> Map.merge(event.params)
      |> Map.to_list()

    {event.time, params}
  end

  defp maybe_add(params, _key, nil), do: params
  defp maybe_add(params, key, value), do: [{key, value} | params]

  # ============================================================================
  # Time Modifiers (Immediate)
  # ============================================================================

  @doc """
  Speed up a pattern by a factor.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.fast(2)
      iex> events = Pattern.events(pattern)
      iex> Enum.at(events, 1).time
      0.25
  """
  def fast(%__MODULE__{} = pattern, factor) when is_number(factor) and factor > 0 do
    new_events =
      pattern.events
      |> Enum.map(fn event ->
        %{event | time: event.time / factor, duration: event.duration / factor}
      end)
      |> Enum.filter(fn event -> event.time < 1.0 end)

    %{pattern | events: new_events}
  end

  @doc """
  Slow down a pattern by a factor.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.slow(2)
      iex> events = Pattern.events(pattern)
      iex> Enum.at(events, 1).time
      1.0
  """
  def slow(%__MODULE__{} = pattern, factor) when is_number(factor) and factor > 0 do
    new_events =
      pattern.events
      |> Enum.map(fn event ->
        %{event | time: event.time * factor, duration: event.duration * factor}
      end)

    %{pattern | events: new_events}
  end

  @doc """
  Reverse the order of events in a pattern.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh") |> Pattern.rev()
      iex> events = Pattern.events(pattern)
      iex> hd(events).sound
      "hh"
  """
  def rev(%__MODULE__{} = pattern) do
    new_events =
      pattern.events
      |> Enum.map(fn event ->
        new_time = 1.0 - event.time - event.duration
        %{event | time: max(0.0, new_time)}
      end)
      |> Enum.sort_by(& &1.time)

    %{pattern | events: new_events}
  end

  @doc """
  Shift pattern earlier by a number of cycles (wraps around).

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.early(0.25)
      iex> events = Pattern.events(pattern)
      iex> hd(events).time
      0.75
  """
  def early(%__MODULE__{} = pattern, amount) when is_number(amount) do
    new_events =
      pattern.events
      |> Enum.map(fn event ->
        new_time = event.time - amount
        wrapped = new_time - Float.floor(new_time)
        %{event | time: wrapped}
      end)
      |> Enum.sort_by(& &1.time)

    %{pattern | events: new_events}
  end

  @doc """
  Shift pattern later by a number of cycles (wraps around).

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.late(0.25)
      iex> events = Pattern.events(pattern)
      iex> hd(events).time
      0.25
  """
  def late(%__MODULE__{} = pattern, amount) when is_number(amount) do
    early(pattern, -amount)
  end

  @doc """
  Repeat each event N times within its duration.

  Creates rapid repetitions of each event, useful for rolls and stutters.
  Each repetition fits within the original event's time slot.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.ply(2)
      iex> events = Pattern.events(pattern)
      iex> length(events)
      4
      iex> # First event at 0.0, second at 0.125 (half of 0.25 duration)
  """
  def ply(%__MODULE__{} = pattern, n) when is_integer(n) and n > 0 do
    new_events =
      pattern.events
      |> Enum.flat_map(fn event ->
        event_duration = event.duration / n

        for i <- 0..(n - 1) do
          %{event | time: event.time + i * event_duration, duration: event_duration}
        end
      end)
      |> Enum.sort_by(& &1.time)

    %{pattern | events: new_events}
  end

  @doc """
  Compress the pattern into a time segment within the cycle.

  Squeezes all events into the time range [start, end], leaving the rest
  of the cycle as silence. Useful for creating rhythmic gaps.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.compress(0.25, 0.75)
      iex> events = Pattern.events(pattern)
      iex> # All events now fit between 0.25 and 0.75
      iex> Enum.all?(events, fn e -> e.time >= 0.25 and e.time < 0.75 end)
      true
  """
  def compress(%__MODULE__{} = pattern, start_time, end_time)
      when is_number(start_time) and is_number(end_time) and start_time < end_time do
    span = end_time - start_time

    new_events =
      pattern.events
      |> Enum.map(fn event ->
        %{event | time: start_time + event.time * span, duration: event.duration * span}
      end)
      |> Enum.filter(fn event -> event.time < 1.0 end)

    %{pattern | events: new_events}
  end

  @doc """
  Extract and expand a time segment of the pattern.

  Zooms into a specific portion of the pattern [start, end] and stretches it
  to fill the entire cycle. This is the inverse of compress.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.zoom(0.25, 0.75)
      iex> events = Pattern.events(pattern)
      iex> # Middle half of pattern (sd, hh) expanded to full cycle
      iex> length(events)
      2
  """
  def zoom(%__MODULE__{} = pattern, start_time, end_time)
      when is_number(start_time) and is_number(end_time) and start_time < end_time do
    span = end_time - start_time

    new_events =
      pattern.events
      |> Enum.filter(fn event ->
        # Keep only events that start within the zoom window
        event.time >= start_time and event.time < end_time
      end)
      |> Enum.map(fn event ->
        # Scale and shift the time to fill the full cycle
        new_time = (event.time - start_time) / span
        new_duration = event.duration / span

        %{event | time: new_time, duration: new_duration}
      end)

    %{pattern | events: new_events}
  end

  @doc """
  Repeat a fraction of the pattern to fill the cycle.

  Selects the given fraction of the pattern (from start) and repeats it
  to fill the remainder of the cycle. Also known as fastgap in Strudel.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.linger(0.5)
      iex> events = Pattern.events(pattern)
      iex> # First half (bd sd) repeated twice to fill cycle
      iex> length(events)
      4

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.linger(0.25)
      iex> events = Pattern.events(pattern)
      iex> # First quarter (bd) repeated 4 times
      iex> length(events)
      4
  """
  def linger(%__MODULE__{} = pattern, fraction)
      when is_number(fraction) and fraction > 0.0 and fraction <= 1.0 do
    # Extract events in the first 'fraction' of the pattern
    extracted =
      pattern.events
      |> Enum.filter(fn event -> event.time < fraction end)

    # Calculate how many times to repeat
    repetitions = round(1.0 / fraction)

    # Create repeated events
    new_events =
      for rep <- 0..(repetitions - 1) do
        offset = rep * fraction

        Enum.map(extracted, fn event ->
          %{event | time: event.time + offset}
        end)
      end
      |> List.flatten()
      |> Enum.sort_by(& &1.time)

    %{pattern | events: new_events}
  end

  # ============================================================================
  # Combinators (Immediate)
  # ============================================================================

  @doc """
  Stack multiple patterns to play simultaneously.

  ## Examples

      iex> p1 = Pattern.new("bd")
      iex> p2 = Pattern.new("sd")
      iex> combined = Pattern.stack([p1, p2])
      iex> length(Pattern.events(combined))
      2
  """
  def stack(patterns) when is_list(patterns) do
    all_events =
      patterns
      |> Enum.flat_map(fn %__MODULE__{events: events} -> events end)
      |> Enum.sort_by(& &1.time)

    %__MODULE__{events: all_events, transforms: []}
  end

  @doc """
  Concatenate patterns to play sequentially.

  ## Examples

      iex> p1 = Pattern.new("bd")
      iex> p2 = Pattern.new("sd")
      iex> combined = Pattern.cat([p1, p2])
      iex> events = Pattern.events(combined)
      iex> Enum.at(events, 1).time
      0.5
  """
  def cat(patterns) when is_list(patterns) do
    count = length(patterns)
    segment_duration = 1.0 / count

    all_events =
      patterns
      |> Enum.with_index()
      |> Enum.flat_map(fn {%__MODULE__{events: events}, index} ->
        offset = index * segment_duration

        Enum.map(events, fn event ->
          %{event | time: offset + event.time * segment_duration, duration: event.duration * segment_duration}
        end)
      end)
      |> Enum.sort_by(& &1.time)

    %__MODULE__{events: all_events, transforms: []}
  end

  @doc """
  Create a palindrome pattern (forward then backward).

  ## Examples

      iex> pattern = Pattern.new("bd sd hh") |> Pattern.palindrome()
      iex> length(Pattern.events(pattern))
      6
  """
  def palindrome(%__MODULE__{} = pattern) do
    cat([pattern, rev(pattern)])
  end

  # ============================================================================
  # Conditional Modifiers (Cycle-Aware)
  # ============================================================================

  @doc """
  Apply a function every N cycles.

  This is a cycle-aware transformation - the function is applied based on
  the cycle number when `query/2` is called.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.every(4, &Pattern.rev/1)
      iex> # On cycle 0, 4, 8... the pattern is reversed
      iex> Pattern.query(pattern, 0) |> length()
      2
  """
  def every(%__MODULE__{} = pattern, n, fun) when is_integer(n) and n > 0 and is_function(fun, 1) do
    transform = {:every, n, fun}
    %{pattern | transforms: pattern.transforms ++ [transform]}
  end

  @doc """
  Apply a function with a given probability per cycle.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.sometimes_by(0.5, &Pattern.rev/1)
      iex> # 50% chance to reverse each cycle
  """
  def sometimes_by(%__MODULE__{} = pattern, probability, fun)
      when is_float(probability) and probability >= 0.0 and probability <= 1.0 and is_function(fun, 1) do
    transform = {:sometimes_by, probability, fun}
    %{pattern | transforms: pattern.transforms ++ [transform]}
  end

  @doc """
  Apply a function with 50% probability per cycle.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.sometimes(&Pattern.rev/1)
  """
  def sometimes(%__MODULE__{} = pattern, fun) when is_function(fun, 1) do
    sometimes_by(pattern, 0.5, fun)
  end

  @doc """
  Apply a function with 75% probability per cycle.
  """
  def often(%__MODULE__{} = pattern, fun) when is_function(fun, 1) do
    sometimes_by(pattern, 0.75, fun)
  end

  @doc """
  Apply a function with 25% probability per cycle.
  """
  def rarely(%__MODULE__{} = pattern, fun) when is_function(fun, 1) do
    sometimes_by(pattern, 0.25, fun)
  end

  @doc """
  Rotate the pattern start position each cycle.

  Divides the pattern into N subdivisions and shifts the starting point by
  one subdivision each cycle. Creates evolving patterns.

  This is a cycle-aware transformation - resolved at query time.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.iter(4)
      iex> # Cycle 0: starts at bd (subdivision 0)
      iex> # Cycle 1: starts at sd (subdivision 1)
      iex> # Cycle 2: starts at hh (subdivision 2)
      iex> # Cycle 3: starts at cp (subdivision 3)
      iex> # Cycle 4: wraps back to bd
  """
  def iter(%__MODULE__{} = pattern, n) when is_integer(n) and n > 0 do
    transform = {:iter, n}
    %{pattern | transforms: pattern.transforms ++ [transform]}
  end

  @doc """
  Rotate the pattern start position backwards each cycle.

  Like iter/2 but rotates in reverse. Also known as iter' in TidalCycles.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.iter_back(4)
      iex> # Cycle 0: starts at bd
      iex> # Cycle 1: starts at cp (backwards rotation)
      iex> # Cycle 2: starts at hh
  """
  def iter_back(%__MODULE__{} = pattern, n) when is_integer(n) and n > 0 do
    transform = {:iter_back, n}
    %{pattern | transforms: pattern.transforms ++ [transform]}
  end

  # ============================================================================
  # Degradation
  # ============================================================================

  @doc """
  Randomly remove events with a given probability.

  Unlike `sometimes_by`, this operates on individual events, not the whole pattern.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.degrade_by(0.5)
      iex> # ~50% of events removed (randomly)
  """
  def degrade_by(%__MODULE__{} = pattern, probability)
      when is_float(probability) and probability >= 0.0 and probability <= 1.0 do
    new_events = Enum.filter(pattern.events, fn _event -> :rand.uniform() > probability end)
    %{pattern | events: new_events}
  end

  @doc """
  Randomly remove ~50% of events.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.degrade()
  """
  def degrade(%__MODULE__{} = pattern) do
    degrade_by(pattern, 0.5)
  end

  # ============================================================================
  # Stereo
  # ============================================================================

  @doc """
  Apply a function to create a stereo effect.

  Creates two copies of the pattern: original panned left, transformed panned right.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.jux(&Pattern.rev/1)
      iex> length(Pattern.events(pattern))
      4
  """
  def jux(%__MODULE__{} = pattern, fun) when is_function(fun, 1) do
    left_events = Enum.map(pattern.events, fn e -> %{e | params: Map.put(e.params, :pan, -1.0)} end)
    right_pattern = fun.(pattern)
    right_events = Enum.map(right_pattern.events, fn e -> %{e | params: Map.put(e.params, :pan, 1.0)} end)

    all_events = Enum.sort_by(left_events ++ right_events, & &1.time)
    %{pattern | events: all_events}
  end

  # ============================================================================
  # Internal: Transform Resolution
  # ============================================================================

  defp apply_transforms(%__MODULE__{} = pattern, cycle) do
    Enum.reduce(pattern.transforms, pattern, fn transform, acc ->
      apply_transform(acc, transform, cycle)
    end)
  end

  defp apply_transform(pattern, {:every, n, fun}, cycle) do
    if rem(cycle, n) == 0 do
      fun.(pattern)
    else
      pattern
    end
  end

  defp apply_transform(pattern, {:sometimes_by, probability, fun}, cycle) do
    # Use cycle as seed for deterministic randomness per cycle
    :rand.seed(:exsss, {cycle, cycle * 2, cycle * 3})

    if :rand.uniform() < probability do
      fun.(pattern)
    else
      pattern
    end
  end

  defp apply_transform(pattern, {:iter, n}, cycle) do
    # Calculate rotation amount based on cycle
    rotation = rem(cycle, n)
    segment_size = 1.0 / n

    # Rotate by shifting time forward and wrapping
    new_events =
      pattern.events
      |> Enum.map(fn event ->
        # Shift backwards by rotation amount
        new_time = event.time - rotation * segment_size
        # Wrap if negative
        wrapped_time = if new_time < 0, do: new_time + 1.0, else: new_time

        %{event | time: wrapped_time}
      end)
      |> Enum.sort_by(& &1.time)

    %{pattern | events: new_events}
  end

  defp apply_transform(pattern, {:iter_back, n}, cycle) do
    # Calculate rotation amount in reverse
    rotation = rem(cycle, n)
    segment_size = 1.0 / n

    # Rotate by shifting time backwards (opposite of iter)
    new_events =
      pattern.events
      |> Enum.map(fn event ->
        # Shift forwards by rotation amount
        new_time = event.time + rotation * segment_size
        # Wrap if >= 1.0
        wrapped_time = if new_time >= 1.0, do: new_time - 1.0, else: new_time

        %{event | time: wrapped_time}
      end)
      |> Enum.sort_by(& &1.time)

    %{pattern | events: new_events}
  end
end
