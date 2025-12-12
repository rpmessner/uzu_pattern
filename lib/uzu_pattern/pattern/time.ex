defmodule UzuPattern.Pattern.Time do
  @moduledoc """
  Time manipulation functions for patterns.

  These functions modify when events occur within cycles:
  - `fast/2`, `slow/2` - Speed up or slow down patterns
  - `early/2`, `late/2` - Shift events in time
  - `ply/2` - Repeat each event N times
  - `compress/3`, `zoom/3` - Squeeze or extract time windows
  - `linger/2` - Loop first portion of pattern
  """

  alias UzuPattern.Pattern
  alias UzuPattern.Hap

  @doc """
  Speed up a pattern by factor n.

  `*n` in mini-notation. Makes the pattern play n times per cycle.

  ## Examples

      iex> p = Pattern.pure("bd") |> Pattern.fast(4)
      iex> haps = Pattern.query(p, 0)
      iex> length(haps)
      4
  """
  def fast(%Pattern{} = pattern, factor) when is_number(factor) and factor > 0 do
    cond do
      factor >= 1 ->
        int_factor = trunc(factor)

        Pattern.new(fn cycle ->
          base_inner_cycle = cycle * int_factor

          0..(int_factor - 1)
          |> Enum.flat_map(fn offset ->
            inner_cycle = base_inner_cycle + offset
            time_offset = offset / factor

            pattern
            |> Pattern.query(inner_cycle)
            |> Enum.map(fn hap ->
              scale_and_offset_hap(hap, 1.0 / factor, time_offset)
            end)
          end)
          |> Enum.filter(fn hap ->
            onset = Hap.onset(hap) || hap.part.begin
            onset >= 0.0 and onset < 1.0
          end)
          |> Enum.sort_by(&(Hap.onset(&1) || &1.part.begin))
        end)

      factor < 1 ->
        slow(pattern, 1.0 / factor)
    end
  end

  @doc """
  Slow down a pattern by factor n.

  `/n` in mini-notation. Makes the pattern take n cycles to complete.

  For slow(2), the inner pattern's cycle is spread across 2 output cycles:
  - Output cycle 0 shows events from [0, 0.5) of inner cycle 0, scaled to [0, 1)
  - Output cycle 1 shows events from [0.5, 1) of inner cycle 0, scaled to [0, 1)
  """
  def slow(%Pattern{} = pattern, factor) when is_number(factor) and factor > 0 do
    int_factor = trunc(factor)

    Pattern.new(fn cycle ->
      inner_cycle = div(cycle, int_factor)
      slice_index = rem(cycle, int_factor)
      slice_start = slice_index / factor
      slice_end = (slice_index + 1) / factor

      pattern
      |> Pattern.query(inner_cycle)
      |> Enum.filter(fn hap ->
        onset = Hap.onset(hap) || hap.part.begin
        onset >= slice_start and onset < slice_end
      end)
      |> Enum.map(fn hap ->
        # Scale up and shift so this slice fills the whole cycle
        onset = Hap.onset(hap) || hap.part.begin
        new_onset = (onset - slice_start) * factor
        dur = hap.part.end - hap.part.begin
        new_dur = min(dur * factor, 1.0 - new_onset)
        set_hap_timespan(hap, new_onset, new_onset + new_dur)
      end)
    end)
  end

  @doc """
  Shift pattern earlier in time.
  """
  def early(%Pattern{} = pattern, amount) do
    Pattern.new(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.map(fn hap ->
        shifted = Hap.shift(hap, -amount)
        # Wrap if onset went negative
        onset = Hap.onset(shifted) || shifted.part.begin

        if onset < 0 do
          Hap.shift(shifted, 1.0)
        else
          shifted
        end
      end)
      |> Enum.sort_by(&(Hap.onset(&1) || &1.part.begin))
    end)
  end

  @doc """
  Shift pattern later in time.
  """
  def late(%Pattern{} = pattern, amount) do
    early(pattern, -amount)
  end

  @doc """
  Repeat each event N times within its duration, creating rolls and stutters.

  Unlike `fast`, which speeds up the whole pattern, `ply` repeats each
  individual event in place.

  ## Examples

      iex> p = Pattern.pure("bd") |> Pattern.ply(4)
      iex> haps = Pattern.query(p, 0)
      iex> length(haps)
      4
  """
  def ply(%Pattern{} = pattern, n) when is_integer(n) and n > 0 do
    Pattern.new(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.flat_map(fn hap ->
        onset = Hap.onset(hap) || hap.part.begin
        dur = (hap.part.end - hap.part.begin) / n

        for i <- 0..(n - 1) do
          new_onset = onset + i * dur
          set_hap_timespan(hap, new_onset, new_onset + dur)
        end
      end)
      |> Enum.sort_by(&(Hap.onset(&1) || &1.part.begin))
    end)
  end

  @doc """
  Squeeze the pattern into a portion of the cycle, leaving silence elsewhere.

  `compress(0.0, 0.5)` plays the full pattern in the first half, then silence.
  `compress(0.25, 0.75)` plays the pattern in the middle half of the cycle.
  """
  def compress(%Pattern{} = pattern, start_time, end_time)
      when is_number(start_time) and is_number(end_time) and start_time < end_time do
    span = end_time - start_time

    Pattern.new(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.map(fn hap ->
        onset = Hap.onset(hap) || hap.part.begin
        dur = hap.part.end - hap.part.begin
        new_onset = start_time + onset * span
        new_dur = dur * span
        set_hap_timespan(hap, new_onset, new_onset + new_dur)
      end)
      |> Enum.filter(fn hap ->
        onset = Hap.onset(hap) || hap.part.begin
        onset < 1.0
      end)
    end)
  end

  @doc """
  Zoom into a portion of the pattern and expand it to fill the cycle.

  `zoom(0.0, 0.5)` takes the first half of the pattern and stretches it.
  `zoom(0.25, 0.75)` extracts the middle portion and expands it.

  The inverse of `compress`.
  """
  def zoom(%Pattern{} = pattern, start_time, end_time)
      when is_number(start_time) and is_number(end_time) and start_time < end_time do
    span = end_time - start_time

    Pattern.new(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.filter(fn hap ->
        onset = Hap.onset(hap) || hap.part.begin
        onset >= start_time and onset < end_time
      end)
      |> Enum.map(fn hap ->
        onset = Hap.onset(hap) || hap.part.begin
        dur = hap.part.end - hap.part.begin
        new_onset = (onset - start_time) / span
        new_dur = dur / span
        set_hap_timespan(hap, new_onset, new_onset + new_dur)
      end)
    end)
  end

  @doc """
  Repeat the first portion of a pattern to fill the whole cycle.

  `linger(0.5)` takes the first half and repeats it twice.
  `linger(0.25)` takes the first quarter and repeats it 4 times.

  Creates hypnotic, looping effects by focusing on a small fragment.
  """
  def linger(%Pattern{} = pattern, fraction)
      when is_number(fraction) and fraction > 0.0 and fraction <= 1.0 do
    repetitions = round(1.0 / fraction)

    Pattern.new(fn cycle ->
      extracted =
        pattern
        |> Pattern.query(cycle)
        |> Enum.filter(fn hap ->
          onset = Hap.onset(hap) || hap.part.begin
          onset < fraction
        end)

      for rep <- 0..(repetitions - 1) do
        offset = rep * fraction

        Enum.map(extracted, fn hap ->
          Hap.shift(hap, offset)
        end)
      end
      |> List.flatten()
      |> Enum.sort_by(&(Hap.onset(&1) || &1.part.begin))
    end)
  end

  # Helper: scale and offset a hap's timespans
  defp scale_and_offset_hap(%Hap{} = hap, scale, offset) do
    new_whole = scale_and_offset_timespan(hap.whole, scale, offset)
    new_part = scale_and_offset_timespan(hap.part, scale, offset)
    %{hap | whole: new_whole, part: new_part}
  end

  defp scale_and_offset_timespan(nil, _scale, _offset), do: nil

  defp scale_and_offset_timespan(%{begin: b, end: e}, scale, offset) do
    %{begin: offset + b * scale, end: offset + e * scale}
  end

  # Set a hap's timespan to specific begin/end values
  defp set_hap_timespan(%Hap{} = hap, begin_time, end_time) do
    timespan = %{begin: begin_time, end: end_time}
    %{hap | whole: timespan, part: timespan}
  end
end
