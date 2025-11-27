defmodule UzuPattern.Pattern.Rhythm do
  @moduledoc """
  Rhythm generation and timing functions for patterns.

  This module provides functions for generating rhythmic patterns using
  Euclidean algorithms and adding swing timing.

  ## Functions

  - `euclid/3` - Generate Euclidean rhythm pattern
  - `euclid_rot/4` - Euclidean rhythm with rotation
  - `swing/2` - Add swing timing (1/3 delay)
  - `swing_by/3` - Parameterized swing timing

  ## Examples

      iex> import UzuPattern.Pattern.Rhythm
      iex> pattern = Pattern.new("bd*8") |> euclid(3, 8) |> swing(8)
  """

  alias UzuPattern.Pattern

  @doc """
  Generate a Euclidean rhythm pattern.

  Distributes N pulses across M steps using Bjorklund's algorithm.
  Only events at positions where pulses occur are kept.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.Rhythm.euclid(3, 8)
      iex> events = Pattern.events(pattern)
      iex> length(events) == 3
      true
  """
  def euclid(%Pattern{} = pattern, pulses, steps)
      when is_integer(pulses) and is_integer(steps) and pulses >= 0 and steps > 0 and pulses <= steps do
    # Generate Euclidean rhythm using Bjorklund's algorithm
    rhythm = euclidean_rhythm(pulses, steps)

    # Keep only events at positions where rhythm has 1
    new_events =
      pattern.events
      |> Enum.with_index()
      |> Enum.filter(fn {_event, idx} ->
        Enum.at(rhythm, rem(idx, steps), 0) == 1
      end)
      |> Enum.map(fn {event, _idx} -> event end)

    %{pattern | events: new_events}
  end

  @doc """
  Generate a Euclidean rhythm with rotation offset.

  Like euclid/3 but rotates the pattern by offset steps.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.Rhythm.euclid_rot(3, 8, 2)
      iex> events = Pattern.events(pattern)
      iex> length(events) == 3
      true
  """
  def euclid_rot(%Pattern{} = pattern, pulses, steps, offset)
      when is_integer(pulses) and is_integer(steps) and is_integer(offset) and
             pulses >= 0 and steps > 0 and pulses <= steps do
    # Generate Euclidean rhythm and rotate it
    rhythm = euclidean_rhythm(pulses, steps)
    rotated = Enum.drop(rhythm, offset) ++ Enum.take(rhythm, offset)

    # Keep only events at positions where rhythm has 1
    new_events =
      pattern.events
      |> Enum.with_index()
      |> Enum.filter(fn {_event, idx} ->
        Enum.at(rotated, rem(idx, steps), 0) == 1
      end)
      |> Enum.map(fn {event, _idx} -> event end)

    %{pattern | events: new_events}
  end

  @doc """
  Add swing timing to pattern.

  Delays every other event by 1/3 of the slice duration, creating shuffle feel.
  Convenience function that calls swing_by with delay of 1/3.

  ## Examples

      iex> pattern = Pattern.new("hh*8") |> Pattern.Rhythm.swing(4)
      iex> events = Pattern.events(pattern)
      iex> length(events) == 8
      true
  """
  def swing(%Pattern{} = pattern, n) when is_integer(n) and n > 0 do
    swing_by(pattern, 1 / 3, n)
  end

  @doc """
  Add parameterized swing timing to pattern.

  Breaks cycle into N slices, delays events in second half of each slice.
  Amount is relative to half-slice size (0.0 = no swing, 0.5 = half delay).

  ## Examples

      iex> pattern = Pattern.new("hh*8") |> Pattern.Rhythm.swing_by(0.5, 4)
      iex> events = Pattern.events(pattern)
      iex> length(events) == 8
      true
  """
  def swing_by(%Pattern{} = pattern, amount, n)
      when is_number(amount) and is_integer(n) and n > 0 do
    slice_size = 1.0 / n

    new_events =
      pattern.events
      |> Enum.map(fn event ->
        # Determine which slice this event is in
        slice_idx = floor(event.time / slice_size)
        position_in_slice = event.time - slice_idx * slice_size
        half_slice = slice_size / 2

        # If in second half of slice, apply swing delay
        if position_in_slice >= half_slice do
          delay = amount * half_slice
          new_time = event.time + delay
          wrapped_time = new_time - Float.floor(new_time)
          %{event | time: wrapped_time}
        else
          event
        end
      end)
      |> Enum.sort_by(& &1.time)

    %{pattern | events: new_events}
  end

  # Bjorklund's algorithm for generating Euclidean rhythms
  defp euclidean_rhythm(pulses, steps) when pulses == 0, do: List.duplicate(0, steps)
  defp euclidean_rhythm(pulses, steps) when pulses == steps, do: List.duplicate(1, steps)

  defp euclidean_rhythm(pulses, steps) do
    # Start with pulses 1s and (steps - pulses) 0s
    ones = List.duplicate([1], pulses)
    zeros = List.duplicate([0], steps - pulses)

    bjorklund(ones, zeros)
    |> List.flatten()
  end

  defp bjorklund([], zeros), do: zeros
  defp bjorklund(ones, []), do: ones

  defp bjorklund(ones, zeros) when length(ones) <= length(zeros) do
    # Pair each one with a zero
    pairs = Enum.zip(ones, zeros) |> Enum.map(fn {a, b} -> a ++ b end)
    remaining = Enum.drop(zeros, length(ones))

    if remaining == [] do
      pairs
    else
      bjorklund(pairs, remaining)
    end
  end

  defp bjorklund(ones, zeros) do
    # More ones than zeros, pair zeros with ones
    pairs = Enum.zip(zeros, ones) |> Enum.map(fn {a, b} -> a ++ b end)
    remaining = Enum.drop(ones, length(zeros))

    if remaining == [] do
      pairs
    else
      bjorklund(remaining, pairs)
    end
  end
end
