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
end
