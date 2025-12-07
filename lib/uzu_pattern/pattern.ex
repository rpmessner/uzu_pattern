defmodule UzuPattern.Pattern do
  @moduledoc """
  Pattern struct and transformation functions for Strudel.js-style live coding.

  A Pattern wraps events from UzuParser and provides transformation functions
  that can be chained together. Patterns support both immediate transformations
  (like `fast`, `slow`, `rev`) and cycle-aware transformations (like `every`).

  Functions are organized into submodules:
  - `UzuPattern.Pattern.Time` - Time modifiers (fast, slow, compress, etc.)
  - `UzuPattern.Pattern.Combinators` - Pattern combinations (stack, cat, etc.)
  - `UzuPattern.Pattern.Conditional` - Cycle-aware conditionals (every, iter, etc.)
  - `UzuPattern.Pattern.Effects` - Audio parameters (gain, pan, filters, etc.)
  - `UzuPattern.Pattern.Rhythm` - Rhythm generation (euclid, swing, etc.)
  - `UzuPattern.Pattern.Structure` - Structure manipulation (rev, degrade, jux, etc.)

  ## Creating Patterns

  ```elixir
  # From mini-notation string
  pattern = Pattern.new("bd sd hh cp")

  # From existing events
  pattern = Pattern.from_events(events)
  ```

  ## Chaining Transformations

  You can use functions from submodules directly:

  ```elixir
  alias UzuPattern.Pattern.{Time, Effects, Rhythm}

  "bd sd hh cp"
  |> Pattern.new()
  |> Time.fast(2)
  |> Rhythm.euclid(3, 8)
  |> Effects.gain(0.8)
  ```

  Or use the delegated functions for backward compatibility:

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
          | {:every_offset, pos_integer(), non_neg_integer(), function()}
          | {:sometimes_by, float(), function()}
          | {:when, function(), function()}
          | {:iter, pos_integer()}
          | {:iter_back, pos_integer()}
          | {:first_of, pos_integer(), function()}
          | {:last_of, pos_integer(), function()}
          | {:when_fn, function(), function()}
          | {:chunk, pos_integer(), function()}
          | {:chunk_back, pos_integer(), function()}

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
  # Delegators for Backward Compatibility
  # ============================================================================

  # Time modifiers
  defdelegate fast(pattern, factor), to: UzuPattern.Pattern.Time
  defdelegate slow(pattern, factor), to: UzuPattern.Pattern.Time
  defdelegate early(pattern, amount), to: UzuPattern.Pattern.Time
  defdelegate late(pattern, amount), to: UzuPattern.Pattern.Time
  defdelegate ply(pattern, n), to: UzuPattern.Pattern.Time
  defdelegate compress(pattern, start_time, end_time), to: UzuPattern.Pattern.Time
  defdelegate zoom(pattern, start_time, end_time), to: UzuPattern.Pattern.Time
  defdelegate linger(pattern, fraction), to: UzuPattern.Pattern.Time

  # Combinators
  defdelegate stack(patterns), to: UzuPattern.Pattern.Combinators
  defdelegate cat(patterns), to: UzuPattern.Pattern.Combinators
  defdelegate palindrome(pattern), to: UzuPattern.Pattern.Combinators
  defdelegate append(pattern, other), to: UzuPattern.Pattern.Combinators
  defdelegate superimpose(pattern, fun), to: UzuPattern.Pattern.Combinators
  defdelegate off(pattern, time_offset, fun), to: UzuPattern.Pattern.Combinators
  defdelegate echo(pattern, n, time_offset, gain_factor), to: UzuPattern.Pattern.Combinators
  defdelegate striate(pattern, n), to: UzuPattern.Pattern.Combinators
  defdelegate chop(pattern, n), to: UzuPattern.Pattern.Combinators

  # Conditional modifiers
  defdelegate every(pattern, n, fun), to: UzuPattern.Pattern.Conditional
  defdelegate every(pattern, n, offset, fun), to: UzuPattern.Pattern.Conditional
  defdelegate sometimes_by(pattern, probability, fun), to: UzuPattern.Pattern.Conditional
  defdelegate sometimes(pattern, fun), to: UzuPattern.Pattern.Conditional
  defdelegate often(pattern, fun), to: UzuPattern.Pattern.Conditional
  defdelegate rarely(pattern, fun), to: UzuPattern.Pattern.Conditional
  defdelegate iter(pattern, n), to: UzuPattern.Pattern.Conditional
  defdelegate iter_back(pattern, n), to: UzuPattern.Pattern.Conditional
  defdelegate first_of(pattern, n, fun), to: UzuPattern.Pattern.Conditional
  defdelegate last_of(pattern, n, fun), to: UzuPattern.Pattern.Conditional
  defdelegate when_fn(pattern, condition_fn, fun), to: UzuPattern.Pattern.Conditional
  defdelegate chunk(pattern, n, fun), to: UzuPattern.Pattern.Conditional
  defdelegate chunk_back(pattern, n, fun), to: UzuPattern.Pattern.Conditional

  # Effects
  defdelegate set_param(pattern, key, value), to: UzuPattern.Pattern.Effects
  defdelegate gain(pattern, value), to: UzuPattern.Pattern.Effects
  defdelegate pan(pattern, value), to: UzuPattern.Pattern.Effects
  defdelegate speed(pattern, value), to: UzuPattern.Pattern.Effects
  defdelegate cut(pattern, group), to: UzuPattern.Pattern.Effects
  defdelegate room(pattern, value), to: UzuPattern.Pattern.Effects
  defdelegate delay(pattern, value), to: UzuPattern.Pattern.Effects
  defdelegate lpf(pattern, frequency), to: UzuPattern.Pattern.Effects
  defdelegate hpf(pattern, frequency), to: UzuPattern.Pattern.Effects

  # Rhythm
  defdelegate euclid(pattern, pulses, steps), to: UzuPattern.Pattern.Rhythm
  defdelegate euclid_rot(pattern, pulses, steps, offset), to: UzuPattern.Pattern.Rhythm
  defdelegate swing(pattern, n), to: UzuPattern.Pattern.Rhythm
  defdelegate swing_by(pattern, amount, n), to: UzuPattern.Pattern.Rhythm

  # Structure
  defdelegate rev(pattern), to: UzuPattern.Pattern.Structure
  defdelegate struct_fn(pattern, structure_string), to: UzuPattern.Pattern.Structure
  defdelegate mask(pattern, mask_string), to: UzuPattern.Pattern.Structure
  defdelegate degrade_by(pattern, probability), to: UzuPattern.Pattern.Structure
  defdelegate degrade(pattern), to: UzuPattern.Pattern.Structure
  defdelegate jux(pattern, fun), to: UzuPattern.Pattern.Structure
  defdelegate jux_by(pattern, amount, fun), to: UzuPattern.Pattern.Structure

  # ============================================================================
  # Cycle-Aware Transform Application (Private)
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

  defp apply_transform(pattern, {:every_offset, n, offset, fun}, cycle) do
    if rem(cycle, n) == offset do
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

  defp apply_transform(pattern, {:first_of, n, fun}, cycle) do
    if rem(cycle, n) == 0 do
      fun.(pattern)
    else
      pattern
    end
  end

  defp apply_transform(pattern, {:last_of, n, fun}, cycle) do
    if rem(cycle, n) == n - 1 do
      fun.(pattern)
    else
      pattern
    end
  end

  defp apply_transform(pattern, {:when_fn, condition_fn, fun}, cycle) do
    if condition_fn.(cycle) do
      fun.(pattern)
    else
      pattern
    end
  end

  defp apply_transform(pattern, {:chunk, n, fun}, cycle) do
    # Determine which chunk to apply the function to
    chunk_index = rem(cycle, n)
    chunk_size = 1.0 / n
    chunk_start = chunk_index * chunk_size
    chunk_end = (chunk_index + 1) * chunk_size

    # Split events into those in the chunk and those outside
    {chunk_events, other_events} =
      Enum.split_with(pattern.events, fn event ->
        event.time >= chunk_start and event.time < chunk_end
      end)

    # Create a pattern from just the chunk events
    chunk_pattern = %{pattern | events: chunk_events}

    # Apply the function to the chunk
    transformed_chunk = fun.(chunk_pattern)

    # Combine transformed chunk with other events
    all_events = Enum.sort_by(other_events ++ transformed_chunk.events, & &1.time)
    %{pattern | events: all_events}
  end

  defp apply_transform(pattern, {:chunk_back, n, fun}, cycle) do
    # Like chunk but cycles through chunks in reverse
    chunk_index = n - 1 - rem(cycle, n)
    chunk_size = 1.0 / n
    chunk_start = chunk_index * chunk_size
    chunk_end = (chunk_index + 1) * chunk_size

    # Split events into those in the chunk and those outside
    {chunk_events, other_events} =
      Enum.split_with(pattern.events, fn event ->
        event.time >= chunk_start and event.time < chunk_end
      end)

    # Create a pattern from just the chunk events
    chunk_pattern = %{pattern | events: chunk_events}

    # Apply the function to the chunk
    transformed_chunk = fun.(chunk_pattern)

    # Combine transformed chunk with other events
    all_events = Enum.sort_by(other_events ++ transformed_chunk.events, & &1.time)
    %{pattern | events: all_events}
  end
end
