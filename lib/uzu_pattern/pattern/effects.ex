defmodule UzuPattern.Pattern.Effects do
  @moduledoc """
  Audio effects and parameter functions for patterns.

  This module provides functions for setting audio parameters on events,
  including volume, panning, filters, and effects like reverb and delay.

  ## Functions

  - `gain/2` - Set volume/gain
  - `pan/2` - Set stereo pan position
  - `speed/2` - Set playback speed
  - `cut/2` - Set cut group (event stopping)
  - `room/2` - Set reverb amount
  - `delay/2` - Set delay amount
  - `lpf/2` - Set low-pass filter cutoff
  - `hpf/2` - Set high-pass filter cutoff

  ## Examples

      iex> import UzuPattern.Pattern.Effects
      iex> pattern = Pattern.new("bd sd") |> gain(0.8) |> lpf(2000)
  """

  alias UzuPattern.Pattern

  @doc """
  Set the gain (volume) for all events in the pattern.

  Gain controls volume amplitude. Applied after ADSR envelope.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh") |> Pattern.Effects.gain(0.5)
      iex> events = Pattern.events(pattern)
      iex> Enum.all?(events, fn e -> e.params[:gain] == 0.5 end)
      true
  """
  def gain(%Pattern{} = pattern, value) when is_number(value) do
    new_events = Enum.map(pattern.events, fn e -> %{e | params: Map.put(e.params, :gain, value)} end)
    %{pattern | events: new_events}
  end

  @doc """
  Set the stereo pan position for all events in the pattern.

  Pan range: 0.0 (left) to 1.0 (right), 0.5 is center.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Effects.pan(0.5)
      iex> events = Pattern.events(pattern)
      iex> Enum.all?(events, fn e -> e.params[:pan] == 0.5 end)
      true
  """
  def pan(%Pattern{} = pattern, value) when is_number(value) and value >= 0.0 and value <= 1.0 do
    new_events = Enum.map(pattern.events, fn e -> %{e | params: Map.put(e.params, :pan, value)} end)
    %{pattern | events: new_events}
  end

  @doc """
  Set the playback speed for all events in the pattern.

  Speed multiplier: 1.0 is normal, 2.0 is double speed, 0.5 is half speed.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Effects.speed(2.0)
      iex> events = Pattern.events(pattern)
      iex> Enum.all?(events, fn e -> e.params[:speed] == 2.0 end)
      true
  """
  def speed(%Pattern{} = pattern, value) when is_number(value) and value > 0.0 do
    new_events = Enum.map(pattern.events, fn e -> %{e | params: Map.put(e.params, :speed, value)} end)
    %{pattern | events: new_events}
  end

  @doc """
  Set the cut group for all events in the pattern.

  Events with the same cut group will stop previous events in that group.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Effects.cut(1)
      iex> events = Pattern.events(pattern)
      iex> Enum.all?(events, fn e -> e.params[:cut] == 1 end)
      true
  """
  def cut(%Pattern{} = pattern, group) when is_integer(group) and group >= 0 do
    new_events = Enum.map(pattern.events, fn e -> %{e | params: Map.put(e.params, :cut, group)} end)
    %{pattern | events: new_events}
  end

  @doc """
  Set the reverb amount for all events in the pattern.

  Room range: 0.0 (dry) to 1.0 (wet).

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Effects.room(0.5)
      iex> events = Pattern.events(pattern)
      iex> Enum.all?(events, fn e -> e.params[:room] == 0.5 end)
      true
  """
  def room(%Pattern{} = pattern, value) when is_number(value) and value >= 0.0 and value <= 1.0 do
    new_events = Enum.map(pattern.events, fn e -> %{e | params: Map.put(e.params, :room, value)} end)
    %{pattern | events: new_events}
  end

  @doc """
  Set the delay amount for all events in the pattern.

  Delay range: 0.0 (dry) to 1.0 (wet).

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Effects.delay(0.25)
      iex> events = Pattern.events(pattern)
      iex> Enum.all?(events, fn e -> e.params[:delay] == 0.25 end)
      true
  """
  def delay(%Pattern{} = pattern, value) when is_number(value) and value >= 0.0 and value <= 1.0 do
    new_events = Enum.map(pattern.events, fn e -> %{e | params: Map.put(e.params, :delay, value)} end)
    %{pattern | events: new_events}
  end

  @doc """
  Set the low-pass filter cutoff frequency for all events.

  LPF allows low frequencies to pass, cutting high frequencies.
  Frequency range: 0 to 20000 Hz.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Effects.lpf(1000)
      iex> events = Pattern.events(pattern)
      iex> Enum.all?(events, fn e -> e.params[:lpf] == 1000 end)
      true
  """
  def lpf(%Pattern{} = pattern, frequency) when is_number(frequency) and frequency >= 0 and frequency <= 20000 do
    new_events = Enum.map(pattern.events, fn e -> %{e | params: Map.put(e.params, :lpf, frequency)} end)
    %{pattern | events: new_events}
  end

  @doc """
  Set the high-pass filter cutoff frequency for all events.

  HPF allows high frequencies to pass, cutting low frequencies.
  Frequency range: 0 to 20000 Hz.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Effects.hpf(1000)
      iex> events = Pattern.events(pattern)
      iex> Enum.all?(events, fn e -> e.params[:hpf] == 1000 end)
      true
  """
  def hpf(%Pattern{} = pattern, frequency) when is_number(frequency) and frequency >= 0 and frequency <= 20000 do
    new_events = Enum.map(pattern.events, fn e -> %{e | params: Map.put(e.params, :hpf, frequency)} end)
    %{pattern | events: new_events}
  end
end
