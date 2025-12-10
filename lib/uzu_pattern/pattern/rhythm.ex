defmodule UzuPattern.Pattern.Rhythm do
  @moduledoc """
  Rhythm generation functions for patterns.

  These functions create or modify rhythmic patterns:
  - `euclid/3`, `euclid_rot/4` - Euclidean rhythm distribution
  - `swing/2`, `swing_by/3` - Add swing timing
  """

  alias UzuPattern.Pattern

  @doc """
  Create a Euclidean rhythm - evenly distributing pulses across steps.

  Euclidean rhythms are found in music worldwide, from African
  polyrhythms to Cuban clave patterns.

  Common patterns:
  - `euclid(3, 8)` - Cuban tresillo / breakbeat feel
  - `euclid(5, 8)` - Cinquillo rhythm
  - `euclid(7, 12)` - West African bell pattern
  """
  def euclid(%Pattern{} = pattern, pulses, steps)
      when is_integer(pulses) and is_integer(steps) and pulses >= 0 and steps > 0 and
             pulses <= steps do
    rhythm = euclidean_rhythm(pulses, steps)
    step_size = 1.0 / steps

    Pattern.new(fn cycle ->
      base_events = Pattern.query(pattern, cycle)

      pulse_indices =
        rhythm
        |> Enum.with_index()
        |> Enum.filter(fn {hit, _idx} -> hit == 1 end)
        |> Enum.map(fn {_hit, idx} -> idx end)

      base_events
      |> Enum.with_index()
      |> Enum.filter(fn {_event, idx} -> idx in pulse_indices end)
      |> Enum.map(fn {event, idx} ->
        %{event | time: idx * step_size, duration: step_size}
      end)
      |> Enum.sort_by(& &1.time)
    end)
  end

  @doc """
  Create a Euclidean rhythm with rotation offset.

  Same as `euclid/3` but shifts the starting point by `offset` steps.
  """
  def euclid_rot(%Pattern{} = pattern, pulses, steps, offset)
      when is_integer(pulses) and is_integer(steps) and is_integer(offset) and
             pulses >= 0 and steps > 0 and pulses <= steps do
    rhythm = euclidean_rhythm(pulses, steps)
    rotated = Enum.drop(rhythm, offset) ++ Enum.take(rhythm, offset)
    step_size = 1.0 / steps

    Pattern.new(fn cycle ->
      base_events = Pattern.query(pattern, cycle)

      pulse_indices =
        rotated
        |> Enum.with_index()
        |> Enum.filter(fn {hit, _idx} -> hit == 1 end)
        |> Enum.map(fn {_hit, idx} -> idx end)

      base_events
      |> Enum.with_index()
      |> Enum.filter(fn {_event, idx} -> idx in pulse_indices end)
      |> Enum.map(fn {event, idx} ->
        %{event | time: idx * step_size, duration: step_size}
      end)
      |> Enum.sort_by(& &1.time)
    end)
  end

  @doc """
  Add swing feel by delaying off-beat notes.

  Swing pushes the upbeats later, creating that "shuffle" or "groove"
  feel found in jazz, hip-hop, and house music.
  """
  def swing(%Pattern{} = pattern, n) when is_integer(n) and n > 0 do
    swing_by(pattern, 1 / 3, n)
  end

  @doc """
  Add swing with adjustable amount.

  - `amount` controls how much swing (0.0 = straight, 0.5 = heavy swing)
  - `n` sets the subdivision for swing timing
  """
  def swing_by(%Pattern{} = pattern, amount, n)
      when is_number(amount) and is_integer(n) and n > 0 do
    slice_size = 1.0 / n

    Pattern.new(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.map(fn event ->
        slice_idx = floor(event.time / slice_size)
        position_in_slice = event.time - slice_idx * slice_size
        half_slice = slice_size / 2

        if position_in_slice >= half_slice do
          delay_amount = amount * half_slice
          new_time = event.time + delay_amount
          wrapped_time = new_time - Float.floor(new_time)
          %{event | time: wrapped_time}
        else
          event
        end
      end)
      |> Enum.sort_by(& &1.time)
    end)
  end

  # Bjorklund's algorithm for generating Euclidean rhythms
  defp euclidean_rhythm(pulses, _steps) when pulses == 0, do: []
  defp euclidean_rhythm(pulses, steps) when pulses == steps, do: List.duplicate(1, steps)

  defp euclidean_rhythm(pulses, steps) do
    ones = List.duplicate([1], pulses)
    zeros = List.duplicate([0], steps - pulses)
    bjorklund(ones, zeros) |> List.flatten()
  end

  defp bjorklund([], zeros), do: zeros
  defp bjorklund(ones, []), do: ones

  defp bjorklund(ones, zeros) when length(ones) <= length(zeros) do
    pairs = Enum.zip(ones, zeros) |> Enum.map(fn {a, b} -> a ++ b end)
    remaining = Enum.drop(zeros, length(ones))

    if remaining == [] do
      pairs
    else
      bjorklund(pairs, remaining)
    end
  end

  defp bjorklund(ones, zeros) do
    pairs = Enum.zip(zeros, ones) |> Enum.map(fn {a, b} -> a ++ b end)
    remaining = Enum.drop(ones, length(zeros))

    if remaining == [] do
      pairs
    else
      bjorklund(remaining, pairs)
    end
  end
end
