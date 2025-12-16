defmodule UzuPattern.Pattern.Signal do
  @moduledoc """
  Signal patterns - continuous value patterns for modulation.

  Signals are patterns that produce continuous values over time, like LFOs.
  They're used for modulating parameters: `lpf(sine() |> range(200, 2000))`.

  ## Key Insight

  Signals ARE patterns - they use the same `%Pattern{query: fn}` structure.
  A signal's query function returns a single continuous hap with a numeric value
  sampled at the cycle time.

  ## Waveforms

  Basic waveforms output values in the range [0, 1]:
  - `sine/0` - Sine wave (smooth oscillation)
  - `saw/0` - Sawtooth (ramp up, then reset)
  - `tri/0` - Triangle (ramp up, then ramp down)
  - `square/0` - Square wave (0 or 1)

  Use `range/3` to scale to different ranges: `sine() |> range(200, 2000)`

  ## Randomness

  - `rand/0` - Random value per query (deterministic by cycle)
  - `irand/1` - Random integer from 0 to n-1

  ## Operations

  - `range/3` - Scale [0,1] to [min, max]
  - `segment/2` - Discretize into n samples per cycle

  ## Examples

      # Continuous sine wave scaled to filter frequency
      sine() |> range(200, 2000)

      # Stepped random values (8 per cycle)
      rand() |> segment(8)

      # Slow LFO (one cycle per 4 pattern cycles)
      sine() |> slow(4) |> range(0.5, 1.0)
  """

  alias UzuPattern.Pattern
  alias UzuPattern.Hap
  alias UzuPattern.Time

  # ============================================================================
  # Signal Constructor
  # ============================================================================

  @doc """
  Create a continuous signal pattern from a time function.

  The function receives a time value (which may be fractional) and returns
  a numeric value. Signal patterns return a single continuous hap when
  queried via `Pattern.query/2`.

  For sub-cycle sampling (fractional times), use `sample_at/2` which calls
  the time function directly at the exact fractional time.

  ## Examples

      iex> sig = Signal.signal(fn t -> t end)  # identity signal
      iex> [hap] = Pattern.query(sig, 0)
      iex> hap.value.value
      0.0
      iex> Hap.continuous?(hap)
      true
  """
  def signal(time_fn) when is_function(time_fn, 1) do
    # Store the time function in metadata so sample_at can use it
    pattern =
      Pattern.from_cycles(fn cycle ->
        value = time_fn.(cycle * 1.0)

        # Use exact Ratio times for the hap span
        [Hap.continuous(%{begin: Time.zero(), end: Time.one()}, %{value: value})]
      end)

    %{pattern | metadata: Map.put(pattern.metadata, :time_fn, time_fn)}
  end

  # ============================================================================
  # Basic Waveforms (0 to 1)
  # ============================================================================

  @doc """
  Sine wave signal oscillating from 0 to 1.

  One complete cycle per pattern cycle.

  ## Examples

      iex> [hap] = Pattern.query(Signal.sine(), 0)
      iex> hap.value.value
      0.5
  """
  def sine do
    signal(fn t ->
      :math.sin(:math.pi() * 2 * t) * 0.5 + 0.5
    end)
  end

  @doc """
  Sawtooth wave signal ramping from 0 to 1.

  Ramps up linearly then resets each cycle.
  """
  def saw do
    signal(fn t ->
      # ensure float
      t = t * 1.0
      t - Float.floor(t)
    end)
  end

  @doc """
  Inverse sawtooth wave ramping from 1 to 0.
  """
  def isaw do
    signal(fn t ->
      # ensure float
      t = t * 1.0
      1.0 - (t - Float.floor(t))
    end)
  end

  @doc """
  Triangle wave signal oscillating from 0 to 1 to 0.

  Linear ramp up then linear ramp down.
  """
  def tri do
    signal(fn t ->
      # ensure float
      t = t * 1.0
      phase = t - Float.floor(t)

      if phase < 0.5 do
        phase * 2
      else
        2 - phase * 2
      end
    end)
  end

  @doc """
  Square wave signal alternating between 0 and 1.

  First half of cycle is 0, second half is 1.
  """
  def square do
    signal(fn t ->
      # ensure float
      t = t * 1.0
      phase = t - Float.floor(t)
      if phase < 0.5, do: 0.0, else: 1.0
    end)
  end

  # ============================================================================
  # Random Signals
  # ============================================================================

  @doc """
  Random signal producing values from 0 to 1.

  Values are deterministic based on cycle number for reproducibility.
  Each integer cycle produces the same random value.

  ## Examples

      iex> [h1] = Pattern.query(Signal.rand(), 0)
      iex> [h2] = Pattern.query(Signal.rand(), 0)
      iex> h1.value.value == h2.value.value  # Same cycle = same value
      true
  """
  def rand do
    signal(fn t ->
      # Seed based on integer cycle for reproducibility
      cycle = trunc(t)
      :rand.seed(:exsss, {cycle, cycle * 7, cycle * 13})
      :rand.uniform()
    end)
  end

  @doc """
  Random integer signal from 0 to n-1.

  Values are deterministic based on cycle number.

  ## Examples

      iex> sig = Signal.irand(4)
      iex> [hap] = Pattern.query(sig, 0)
      iex> hap.value.value in 0..3
      true
  """
  def irand(n) when is_integer(n) and n > 0 do
    signal(fn t ->
      cycle = trunc(t)
      :rand.seed(:exsss, {cycle, cycle * 7, cycle * 13})
      :rand.uniform(n) - 1
    end)
  end

  # ============================================================================
  # Signal Operations
  # ============================================================================

  @doc """
  Scale signal values from [0, 1] to [min, max].

  This is a linear transformation: `value * (max - min) + min`

  ## Examples

      iex> sig = Signal.sine() |> Signal.range(200, 2000)
      iex> Signal.sample_at(sig, 0)  # sine at 0 is 0.5, scaled: 0.5 * 1800 + 200 = 1100
      1100.0
  """
  def range(%Pattern{metadata: meta} = pattern, min, max) when is_number(min) and is_number(max) do
    scale_fn = fn v -> v * (max - min) + min end

    case meta[:time_fn] do
      nil ->
        # No time function - use standard with_value
        with_value(pattern, scale_fn)

      time_fn ->
        # Compose a new time function that includes the scaling
        new_time_fn = fn t -> scale_fn.(time_fn.(t)) end
        signal(new_time_fn)
    end
  end

  @doc """
  Exponential range scaling (useful for frequencies).

  Maps [0, 1] to [min, max] on an exponential curve.
  """
  def rangex(%Pattern{metadata: meta} = pattern, min, max) when is_number(min) and is_number(max) and min > 0 do
    scale_fn = fn v -> min * :math.pow(max / min, v) end

    case meta[:time_fn] do
      nil ->
        with_value(pattern, scale_fn)

      time_fn ->
        new_time_fn = fn t -> scale_fn.(time_fn.(t)) end
        signal(new_time_fn)
    end
  end

  @doc """
  Discretize a continuous signal into n samples per cycle.

  Turns a continuous signal into n discrete haps, each with
  the signal value sampled at that point in time.

  ## Examples

      iex> sig = Signal.saw() |> Signal.segment(4)
      iex> haps = Pattern.query(sig, 0)
      iex> length(haps)
      4
      iex> Enum.map(haps, & Time.to_float(&1.part.begin))
      [0.0, 0.25, 0.5, 0.75]
  """
  def segment(%Pattern{} = pattern, n) when is_integer(n) and n > 0 do
    Pattern.from_cycles(fn cycle ->
      for i <- 0..(n - 1) do
        # Use exact Ratio times
        begin_time = Time.new(i, n)
        end_time = Time.new(i + 1, n)

        # Sample the signal at the exact fractional time (convert to float for waveform math)
        abs_time = cycle + Time.to_float(begin_time)
        value = sample_at(pattern, abs_time)

        # Create a discrete hap (not continuous)
        Hap.new(%{begin: begin_time, end: end_time}, %{value: value})
      end
    end)
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  @doc """
  Transform the value of each hap in a pattern.

  Works on both discrete events and continuous signals.
  """
  def with_value(%Pattern{} = pattern, value_fn) when is_function(value_fn, 1) do
    Pattern.from_cycles(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.map(fn hap ->
        case Map.get(hap.value, :value) do
          nil -> hap
          v -> %{hap | value: Map.put(hap.value, :value, value_fn.(v))}
        end
      end)
    end)
  end

  @doc """
  Sample a signal pattern at a specific time, returning the numeric value.

  For signals created with `signal/1`, this uses the stored time function
  to sample at the exact fractional time. For transformed patterns (like
  range/3), it recursively samples the underlying signal.

  Used internally when applying signals to event parameters.

  ## Examples

      iex> Signal.sample_at(Signal.saw(), 0.5)
      0.5
      iex> Signal.sample_at(Signal.saw(), 1.5)
      0.5
  """
  def sample_at(%Pattern{metadata: %{time_fn: time_fn}}, time) when is_number(time) do
    # Direct signal - use the time function
    time_fn.(time)
  end

  def sample_at(%Pattern{metadata: %{time_fn: time_fn}}, %Ratio{} = time) do
    # Direct signal with Ratio - convert to float for continuous calculation
    time_fn.(Time.to_float(time))
  end

  def sample_at(%Pattern{} = pattern, time) when is_number(time) do
    # Transformed pattern - query at integer cycle and get the value
    cycle = trunc(time)

    pattern
    |> Pattern.query(cycle)
    |> List.first()
    |> case do
      nil -> 0.0
      %Hap{value: %{value: v}} when not is_nil(v) -> v
      _ -> 0.0
    end
  end

  def sample_at(%Pattern{} = pattern, %Ratio{} = time) do
    # Transformed pattern with Ratio - convert to float
    sample_at(pattern, Time.to_float(time))
  end
end
