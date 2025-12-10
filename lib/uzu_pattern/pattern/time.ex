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

  @doc """
  Speed up a pattern by factor n.

  `*n` in mini-notation. Makes the pattern play n times per cycle.

  ## Examples

      iex> p = Pattern.pure("bd") |> Pattern.fast(4)
      iex> events = Pattern.query(p, 0)
      iex> length(events)
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
            |> Enum.map(fn event ->
              %{
                event
                | time: time_offset + event.time / factor,
                  duration: event.duration / factor
              }
            end)
          end)
          |> Enum.filter(fn event ->
            event.time >= 0.0 and event.time < 1.0
          end)
          |> Enum.sort_by(& &1.time)
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
      |> Enum.filter(fn event ->
        event.time >= slice_start and event.time < slice_end
      end)
      |> Enum.map(fn event ->
        new_time = (event.time - slice_start) * factor
        new_duration = event.duration * factor
        %{event | time: new_time, duration: min(new_duration, 1.0 - new_time)}
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
      |> Enum.map(fn event ->
        new_time = event.time - amount
        wrapped = if new_time < 0, do: new_time + 1.0, else: new_time
        %{event | time: wrapped}
      end)
      |> Enum.sort_by(& &1.time)
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
      iex> events = Pattern.query(p, 0)
      iex> length(events)
      4
  """
  def ply(%Pattern{} = pattern, n) when is_integer(n) and n > 0 do
    Pattern.new(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.flat_map(fn event ->
        event_duration = event.duration / n

        for i <- 0..(n - 1) do
          %{event | time: event.time + i * event_duration, duration: event_duration}
        end
      end)
      |> Enum.sort_by(& &1.time)
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
      |> Enum.map(fn event ->
        %{event | time: start_time + event.time * span, duration: event.duration * span}
      end)
      |> Enum.filter(fn event -> event.time < 1.0 end)
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
      |> Enum.filter(fn event ->
        event.time >= start_time and event.time < end_time
      end)
      |> Enum.map(fn event ->
        new_time = (event.time - start_time) / span
        new_duration = event.duration / span
        %{event | time: new_time, duration: new_duration}
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
        |> Enum.filter(fn event -> event.time < fraction end)

      for rep <- 0..(repetitions - 1) do
        offset = rep * fraction

        Enum.map(extracted, fn event ->
          %{event | time: event.time + offset}
        end)
      end
      |> List.flatten()
      |> Enum.sort_by(& &1.time)
    end)
  end
end
