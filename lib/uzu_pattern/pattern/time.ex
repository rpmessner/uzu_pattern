defmodule UzuPattern.Pattern.Time do
  @moduledoc """
  Time manipulation functions for patterns.

  These functions modify when events occur within cycles:
  - `fast/2`, `slow/2` - Speed up or slow down patterns
  - `early/2`, `late/2` - Shift events in time
  - `ply/2` - Repeat each event N times
  - `compress/3`, `zoom/3` - Squeeze or extract time windows
  - `linger/2` - Loop first portion of pattern

  ## Pattern Arguments

  The `fast` and `slow` functions accept pattern arguments, allowing the speed
  factor to vary over time:

      # Alternating speed: 2x on even cycles, 4x on odd cycles
      s("bd sd hh cp") |> fast("<2 4>")

      # Speed follows a signal
      s("bd sd") |> fast(sine() |> range(1, 4))

  ## Rational Timing

  All timing calculations use rational numbers for exact arithmetic.
  This eliminates floating-point drift in patterns like `fast(3) |> slow(3)`.
  """

  alias UzuPattern.Pattern
  alias UzuPattern.Pattern.Algebra
  alias UzuPattern.Hap
  alias UzuPattern.Time, as: T
  alias UzuPattern.TimeSpan

  @doc """
  Speed up a pattern by factor n.

  `*n` in mini-notation. Makes the pattern play n times per cycle.

  The factor can be:
  - A number: `fast(pattern, 2)` - constant speed
  - A pattern: `fast(pattern, "<2 4>")` - varying speed
  - A mini-notation string: parsed as a pattern

  ## Examples

      iex> p = Pattern.pure("bd") |> Pattern.fast(4)
      iex> haps = Pattern.query(p, 0)
      iex> length(haps)
      4

      # With pattern argument - speed alternates between 2 and 4
      iex> p = Pattern.pure("bd") |> Pattern.fast(Pattern.slowcat([Pattern.pure("2"), Pattern.pure("4")]))
  """
  def fast(%Pattern{} = pattern, %Pattern{} = factor_pattern) do
    # Pattern argument: use squeeze_bind
    # For each factor value, create a fast pattern and squeeze it
    Algebra.squeeze_bind(factor_pattern, fn %{s: s} ->
      factor = parse_numeric(s)
      _fast(pattern, factor)
    end)
  end

  def fast(%Pattern{} = pattern, factor) when is_binary(factor) do
    # String argument: parse as mini-notation
    case UzuPattern.parse(factor) do
      %Pattern{} = factor_pattern -> fast(pattern, factor_pattern)
      _ -> pattern
    end
  end

  def fast(%Pattern{} = pattern, factor) when is_number(factor) and factor > 0 do
    _fast(pattern, factor)
  end

  # Internal fast implementation for numeric factors
  defp _fast(%Pattern{} = pattern, factor) when is_number(factor) and factor > 0 do
    cond do
      factor >= 1 ->
        int_factor = trunc(factor)
        scale = T.new(1, int_factor)

        Pattern.from_cycles(fn cycle ->
          base_inner_cycle = cycle * int_factor

          0..(int_factor - 1)
          |> Enum.flat_map(fn offset ->
            inner_cycle = base_inner_cycle + offset
            time_offset = T.new(offset, int_factor)

            pattern
            |> Pattern.query(inner_cycle)
            |> Enum.map(fn hap ->
              scale_and_offset_hap(hap, scale, time_offset)
            end)
          end)
          |> Enum.filter(fn hap ->
            onset = Hap.onset(hap) || hap.part.begin
            T.gte?(onset, T.zero()) and T.lt?(onset, T.one())
          end)
          |> Enum.sort_by(fn hap ->
            T.to_float(Hap.onset(hap) || hap.part.begin)
          end)
        end)

      factor < 1 ->
        # For fractional factors, convert to slow
        slow(pattern, 1.0 / factor)
    end
  end

  @doc """
  Slow down a pattern by factor n.

  `/n` in mini-notation. Makes the pattern take n cycles to complete.

  For slow(2), the inner pattern's cycle is spread across 2 output cycles:
  - Output cycle 0 shows events from [0, 0.5) of inner cycle 0, scaled to [0, 1)
  - Output cycle 1 shows events from [0.5, 1) of inner cycle 0, scaled to [0, 1)

  Events are filtered by intersection (not onset), so long events that span
  multiple slices will appear in each relevant output cycle.

  The factor can be:
  - A number: `slow(pattern, 2)` - constant speed
  - A pattern: `slow(pattern, "<2 4>")` - varying speed
  - A mini-notation string: parsed as a pattern
  """
  def slow(%Pattern{} = pattern, %Pattern{} = factor_pattern) do
    # Pattern argument: use squeeze_bind
    Algebra.squeeze_bind(factor_pattern, fn %{s: s} ->
      factor = parse_numeric(s)
      _slow(pattern, factor)
    end)
  end

  def slow(%Pattern{} = pattern, factor) when is_binary(factor) do
    # String argument: parse as mini-notation
    case UzuPattern.parse(factor) do
      %Pattern{} = factor_pattern -> slow(pattern, factor_pattern)
      _ -> pattern
    end
  end

  def slow(%Pattern{} = pattern, factor) when is_number(factor) and factor > 0 do
    _slow(pattern, factor)
  end

  # Internal slow implementation for numeric factors
  defp _slow(%Pattern{} = pattern, factor) when is_number(factor) and factor > 0 do
    int_factor = trunc(factor)
    factor_time = T.new(int_factor)

    Pattern.from_cycles(fn cycle ->
      inner_cycle = div(cycle, int_factor)
      slice_index = rem(cycle, int_factor)
      slice_start = T.new(slice_index, int_factor)
      slice_end = T.new(slice_index + 1, int_factor)

      pattern
      |> Pattern.query(inner_cycle)
      |> Enum.filter(fn hap ->
        # Filter by intersection, not just onset
        # An event intersects the slice if it starts before slice_end AND ends after slice_start
        hap_begin = hap.part.begin
        hap_end = hap.part.end
        T.lt?(hap_begin, slice_end) and T.gt?(hap_end, slice_start)
      end)
      |> Enum.map(fn hap ->
        # Clip the event to the slice boundaries, then scale to fill the cycle
        hap_begin = hap.part.begin
        hap_end = hap.part.end

        # Clip to slice
        clipped_begin = T.max(hap_begin, slice_start)
        clipped_end = T.min(hap_end, slice_end)

        # Scale up and shift so this slice fills the whole cycle
        # new_begin = (clipped_begin - slice_start) * factor
        # new_end = (clipped_end - slice_start) * factor
        new_begin = T.mult(T.sub(clipped_begin, slice_start), factor_time)
        new_end = T.mult(T.sub(clipped_end, slice_start), factor_time)

        set_hap_timespan(hap, new_begin, new_end)
      end)
    end)
  end

  @doc """
  Shift pattern earlier in time.
  """
  def early(%Pattern{} = pattern, amount) do
    amt = T.ensure(amount)
    neg_amt = T.mult(amt, T.new(-1))

    Pattern.from_cycles(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.map(fn hap ->
        shifted = Hap.shift(hap, neg_amt)
        # Wrap if onset went negative
        onset = Hap.onset(shifted) || shifted.part.begin

        if T.lt?(onset, T.zero()) do
          Hap.shift(shifted, T.one())
        else
          shifted
        end
      end)
      |> Enum.sort_by(fn hap ->
        T.to_float(Hap.onset(hap) || hap.part.begin)
      end)
    end)
  end

  @doc """
  Shift pattern later in time.
  """
  def late(%Pattern{} = pattern, amount) do
    amt = T.ensure(amount)
    neg_amt = T.mult(amt, T.new(-1))
    early(pattern, neg_amt)
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
    Pattern.from_cycles(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.flat_map(fn hap ->
        onset = Hap.onset(hap) || hap.part.begin
        total_dur = TimeSpan.duration(hap.part)
        dur = T.divide(total_dur, n)

        for i <- 0..(n - 1) do
          new_onset = T.add(onset, T.mult(T.new(i), dur))
          set_hap_timespan(hap, new_onset, T.add(new_onset, dur))
        end
      end)
      |> Enum.sort_by(fn hap ->
        T.to_float(Hap.onset(hap) || hap.part.begin)
      end)
    end)
  end

  @doc """
  Squeeze the pattern into a portion of the cycle, leaving silence elsewhere.

  `compress(0.0, 0.5)` plays the full pattern in the first half, then silence.
  `compress(0.25, 0.75)` plays the pattern in the middle half of the cycle.
  """
  def compress(%Pattern{} = pattern, start_time, end_time)
      when is_number(start_time) and is_number(end_time) and start_time < end_time do
    start_t = T.from_float(start_time)
    end_t = T.from_float(end_time)
    span = T.sub(end_t, start_t)

    Pattern.from_cycles(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.map(fn hap ->
        onset = Hap.onset(hap) || hap.part.begin
        dur = TimeSpan.duration(hap.part)
        # new_onset = start_time + onset * span
        new_onset = T.add(start_t, T.mult(onset, span))
        # new_dur = dur * span
        new_dur = T.mult(dur, span)
        set_hap_timespan(hap, new_onset, T.add(new_onset, new_dur))
      end)
      |> Enum.filter(fn hap ->
        onset = Hap.onset(hap) || hap.part.begin
        T.lt?(onset, T.one())
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
    start_t = T.from_float(start_time)
    end_t = T.from_float(end_time)
    span = T.sub(end_t, start_t)

    Pattern.from_cycles(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.filter(fn hap ->
        onset = Hap.onset(hap) || hap.part.begin
        T.gte?(onset, start_t) and T.lt?(onset, end_t)
      end)
      |> Enum.map(fn hap ->
        onset = Hap.onset(hap) || hap.part.begin
        dur = TimeSpan.duration(hap.part)
        # new_onset = (onset - start_time) / span
        new_onset = T.divide(T.sub(onset, start_t), span)
        # new_dur = dur / span
        new_dur = T.divide(dur, span)
        set_hap_timespan(hap, new_onset, T.add(new_onset, new_dur))
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
    frac = T.from_float(fraction)
    repetitions = round(1.0 / fraction)

    Pattern.from_cycles(fn cycle ->
      extracted =
        pattern
        |> Pattern.query(cycle)
        |> Enum.filter(fn hap ->
          onset = Hap.onset(hap) || hap.part.begin
          T.lt?(onset, frac)
        end)

      for rep <- 0..(repetitions - 1) do
        offset = T.mult(T.new(rep), frac)

        Enum.map(extracted, fn hap ->
          Hap.shift(hap, offset)
        end)
      end
      |> List.flatten()
      |> Enum.sort_by(fn hap ->
        T.to_float(Hap.onset(hap) || hap.part.begin)
      end)
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
    s = T.ensure(scale)
    o = T.ensure(offset)
    %{begin: T.add(o, T.mult(b, s)), end: T.add(o, T.mult(e, s))}
  end

  # Set a hap's timespan to specific begin/end values
  defp set_hap_timespan(%Hap{} = hap, begin_time, end_time) do
    timespan = TimeSpan.new(begin_time, end_time)
    %{hap | whole: timespan, part: timespan}
  end

  # Parse a numeric value from various formats
  defp parse_numeric(value) when is_number(value), do: value

  defp parse_numeric(value) when is_binary(value) do
    case Float.parse(value) do
      {num, ""} ->
        num

      {num, _} ->
        num

      :error ->
        case Integer.parse(value) do
          {num, ""} -> num
          {num, _} -> num
          :error -> 1
        end
    end
  end

  defp parse_numeric(_), do: 1
end
