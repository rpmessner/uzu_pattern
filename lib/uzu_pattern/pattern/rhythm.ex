defmodule UzuPattern.Pattern.Rhythm do
  @moduledoc """
  Rhythm generation functions for patterns.

  These functions create or modify rhythmic patterns:
  - `euclid/3`, `euclid_rot/4` - Euclidean rhythm distribution
  - `swing/2`, `swing_by/3` - Add swing timing
  """

  alias UzuPattern.Pattern
  alias UzuPattern.Euclidean
  alias UzuPattern.Hap

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
    rhythm = Euclidean.rhythm(pulses, steps)
    step_size = 1.0 / steps

    Pattern.new(fn cycle ->
      base_haps = Pattern.query(pattern, cycle)

      pulse_indices =
        rhythm
        |> Enum.with_index()
        |> Enum.filter(fn {hit, _idx} -> hit == 1 end)
        |> Enum.map(fn {_hit, idx} -> idx end)

      base_haps
      |> Enum.with_index()
      |> Enum.filter(fn {_hap, idx} -> idx in pulse_indices end)
      |> Enum.map(fn {hap, idx} ->
        time = idx * step_size
        set_hap_timespan(hap, time, time + step_size)
      end)
      |> Enum.sort_by(&Hap.onset/1)
    end)
  end

  @doc """
  Create a Euclidean rhythm with rotation offset.

  Same as `euclid/3` but shifts the starting point by `offset` steps.
  """
  def euclid_rot(%Pattern{} = pattern, pulses, steps, offset)
      when is_integer(pulses) and is_integer(steps) and is_integer(offset) and
             pulses >= 0 and steps > 0 and pulses <= steps do
    rhythm = Euclidean.rhythm(pulses, steps, offset)
    step_size = 1.0 / steps

    Pattern.new(fn cycle ->
      base_haps = Pattern.query(pattern, cycle)

      pulse_indices =
        rhythm
        |> Enum.with_index()
        |> Enum.filter(fn {hit, _idx} -> hit == 1 end)
        |> Enum.map(fn {_hit, idx} -> idx end)

      base_haps
      |> Enum.with_index()
      |> Enum.filter(fn {_hap, idx} -> idx in pulse_indices end)
      |> Enum.map(fn {hap, idx} ->
        time = idx * step_size
        set_hap_timespan(hap, time, time + step_size)
      end)
      |> Enum.sort_by(&Hap.onset/1)
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
      |> Enum.map(fn hap ->
        onset = Hap.onset(hap) || hap.part.begin
        slice_idx = floor(onset / slice_size)
        position_in_slice = onset - slice_idx * slice_size
        half_slice = slice_size / 2

        if position_in_slice >= half_slice do
          delay_amount = amount * half_slice
          Hap.shift(hap, delay_amount)
        else
          hap
        end
      end)
      |> Enum.sort_by(&Hap.onset/1)
    end)
  end

  # Set a hap's timespan to specific begin/end values
  defp set_hap_timespan(%Hap{} = hap, begin_time, end_time) do
    timespan = %{begin: begin_time, end: end_time}
    %{hap | whole: timespan, part: timespan}
  end
end
