defmodule UzuPattern.Pattern.Effects do
  @moduledoc """
  Effect parameter functions for patterns.

  These functions set audio parameters on pattern events:
  - `gain/2`, `pan/2`, `speed/2` - Basic audio parameters
  - `lpf/2`, `hpf/2` - Filter parameters
  - `room/2`, `delay/2` - Effect sends
  - `cut/2` - Voice cutoff groups
  - `set_param/3` - Generic parameter setter

  ## Signal Modulation

  Effect functions can accept either a static value or a signal pattern:

      # Static filter cutoff
      s("bd sd") |> lpf(800)

      # Modulated filter cutoff (200-2000 Hz following sine wave)
      s("bd sd") |> lpf(sine() |> range(200, 2000))

  When a signal pattern is provided, it's sampled at each event's onset time.
  """

  alias UzuPattern.Pattern
  alias UzuPattern.Pattern.Signal
  alias UzuPattern.Hap
  alias UzuPattern.Time

  @doc """
  Set a parameter on all events in the pattern.

  Value can be a static number or a signal pattern (sampled at event onset).

  ## Examples

      # Static value
      s("bd sd") |> set_param(:lpf, 800)

      # Signal pattern - sampled at each event onset
      s("bd sd") |> set_param(:lpf, sine() |> range(200, 2000))
  """
  def set_param(%Pattern{} = pattern, key, %Pattern{} = signal_pattern) do
    # Value is a signal - sample at each hap's onset time
    Pattern.from_cycles(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.map(fn hap ->
        # Sample the signal at this hap's absolute time
        onset = Hap.onset(hap) || hap.part.begin
        absolute_time = Time.add(cycle, onset)
        value = Signal.sample_at(signal_pattern, absolute_time)
        %{hap | value: Map.put(hap.value, key, value)}
      end)
    end)
  end

  def set_param(%Pattern{} = pattern, key, value) do
    # Value is static - apply to all haps
    Pattern.from_cycles(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.map(fn hap ->
        %{hap | value: Map.put(hap.value, key, value)}
      end)
    end)
  end

  @doc """
  Set gain parameter (0.0 to 1.0+).

  Accepts static value or signal pattern.
  """
  def gain(pattern, value), do: set_param(pattern, :gain, value)

  @doc """
  Set pan parameter (-1.0 left, 0.0 center, 1.0 right).

  Accepts static value or signal pattern.
  """
  def pan(pattern, value), do: set_param(pattern, :pan, value)

  @doc """
  Set playback speed (1.0 = normal, 2.0 = double speed/octave up).

  Accepts static value or signal pattern.
  """
  def speed(pattern, value), do: set_param(pattern, :speed, value)

  @doc "Set cut group - new events cut off previous ones in the same group."
  def cut(pattern, group), do: set_param(pattern, :cut, group)

  @doc """
  Set reverb amount (0.0 = dry, 1.0 = fully wet).

  Accepts static value or signal pattern.
  """
  def room(pattern, value), do: set_param(pattern, :room, value)

  @doc """
  Set delay amount (0.0 = dry, 1.0 = fully delayed).

  Accepts static value or signal pattern.
  """
  def delay(pattern, value), do: set_param(pattern, :delay, value)

  @doc """
  Set low-pass filter cutoff frequency (Hz).

  Accepts static value or signal pattern for modulation.

  ## Examples

      # Static cutoff
      s("bd sd") |> lpf(800)

      # Modulated cutoff following sine wave
      s("bd sd") |> lpf(sine() |> range(200, 2000))
  """
  def lpf(pattern, frequency), do: set_param(pattern, :lpf, frequency)

  @doc """
  Set high-pass filter cutoff frequency (Hz).

  Accepts static value or signal pattern for modulation.

  ## Examples

      # Static cutoff
      s("bd sd") |> hpf(200)

      # Modulated cutoff following sawtooth wave
      s("bd sd") |> hpf(saw() |> range(100, 500))
  """
  def hpf(pattern, frequency), do: set_param(pattern, :hpf, frequency)
end
