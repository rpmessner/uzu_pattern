defmodule UzuPattern.Pattern.Time do
  @moduledoc """
  Time manipulation functions for patterns.

  This module provides functions for modifying the timing and temporal
  structure of patterns, including speed changes, time shifting, compression,
  and repetition effects.

  ## Functions

  - `fast/2` - Speed up pattern by factor
  - `slow/2` - Slow down pattern by factor
  - `early/2` - Shift pattern earlier (wraps around)
  - `late/2` - Shift pattern later (wraps around)
  - `ply/2` - Repeat each event N times within duration
  - `compress/3` - Fit pattern into time segment
  - `zoom/3` - Extract and expand time segment
  - `linger/2` - Repeat fraction of pattern to fill cycle

  ## Examples

      iex> import UzuPattern.Pattern.Time
      iex> pattern = Pattern.new("bd sd hh cp") |> fast(2)
      iex> pattern = pattern |> compress(0.25, 0.75)
  """

  alias UzuPattern.Pattern

  @doc """
  Speed up a pattern by a factor.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Time.fast(2)
      iex> events = Pattern.events(pattern)
      iex> Enum.at(events, 1).time
      0.25
  """
  def fast(%Pattern{} = pattern, factor) when is_number(factor) and factor > 0 do
    new_events =
      pattern.events
      |> Enum.map(fn event ->
        %{event | time: event.time / factor, duration: event.duration / factor}
      end)
      |> Enum.filter(fn event -> event.time < 1.0 end)

    %{pattern | events: new_events}
  end

  @doc """
  Slow down a pattern by a factor.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Time.slow(2)
      iex> events = Pattern.events(pattern)
      iex> Enum.at(events, 1).time
      1.0
  """
  def slow(%Pattern{} = pattern, factor) when is_number(factor) and factor > 0 do
    new_events =
      pattern.events
      |> Enum.map(fn event ->
        %{event | time: event.time * factor, duration: event.duration * factor}
      end)

    %{pattern | events: new_events}
  end

  @doc """
  Shift pattern earlier by a number of cycles (wraps around).

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Time.early(0.25)
      iex> events = Pattern.events(pattern)
      iex> hd(events).time
      0.75
  """
  def early(%Pattern{} = pattern, amount) when is_number(amount) do
    new_events =
      pattern.events
      |> Enum.map(fn event ->
        new_time = event.time - amount
        wrapped = new_time - Float.floor(new_time)
        %{event | time: wrapped}
      end)
      |> Enum.sort_by(& &1.time)

    %{pattern | events: new_events}
  end

  @doc """
  Shift pattern later by a number of cycles (wraps around).

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Time.late(0.25)
      iex> events = Pattern.events(pattern)
      iex> hd(events).time
      0.25
  """
  def late(%Pattern{} = pattern, amount) when is_number(amount) do
    early(pattern, -amount)
  end

  @doc """
  Repeat each event N times within its duration.

  Creates rapid repetitions of each event, useful for rolls and stutters.
  Each repetition fits within the original event's time slot.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Time.ply(2)
      iex> events = Pattern.events(pattern)
      iex> length(events)
      4
      iex> # First event at 0.0, second at 0.125 (half of 0.25 duration)
  """
  def ply(%Pattern{} = pattern, n) when is_integer(n) and n > 0 do
    new_events =
      pattern.events
      |> Enum.flat_map(fn event ->
        event_duration = event.duration / n

        for i <- 0..(n - 1) do
          %{event | time: event.time + i * event_duration, duration: event_duration}
        end
      end)
      |> Enum.sort_by(& &1.time)

    %{pattern | events: new_events}
  end

  @doc """
  Compress the pattern into a time segment within the cycle.

  Squeezes all events into the time range [start, end], leaving the rest
  of the cycle as silence. Useful for creating rhythmic gaps.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.Time.compress(0.25, 0.75)
      iex> events = Pattern.events(pattern)
      iex> # All events now fit between 0.25 and 0.75
      iex> Enum.all?(events, fn e -> e.time >= 0.25 and e.time < 0.75 end)
      true
  """
  def compress(%Pattern{} = pattern, start_time, end_time)
      when is_number(start_time) and is_number(end_time) and start_time < end_time do
    span = end_time - start_time

    new_events =
      pattern.events
      |> Enum.map(fn event ->
        %{event | time: start_time + event.time * span, duration: event.duration * span}
      end)
      |> Enum.filter(fn event -> event.time < 1.0 end)

    %{pattern | events: new_events}
  end

  @doc """
  Extract and expand a time segment of the pattern.

  Zooms into a specific portion of the pattern [start, end] and stretches it
  to fill the entire cycle. This is the inverse of compress.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.Time.zoom(0.25, 0.75)
      iex> events = Pattern.events(pattern)
      iex> # Middle half of pattern (sd, hh) expanded to full cycle
      iex> length(events)
      2
  """
  def zoom(%Pattern{} = pattern, start_time, end_time)
      when is_number(start_time) and is_number(end_time) and start_time < end_time do
    span = end_time - start_time

    new_events =
      pattern.events
      |> Enum.filter(fn event ->
        # Keep only events that start within the zoom window
        event.time >= start_time and event.time < end_time
      end)
      |> Enum.map(fn event ->
        # Scale and shift the time to fill the full cycle
        new_time = (event.time - start_time) / span
        new_duration = event.duration / span

        %{event | time: new_time, duration: new_duration}
      end)

    %{pattern | events: new_events}
  end

  @doc """
  Repeat a fraction of the pattern to fill the cycle.

  Selects the given fraction of the pattern (from start) and repeats it
  to fill the remainder of the cycle. Also known as fastgap in Strudel.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.Time.linger(0.5)
      iex> events = Pattern.events(pattern)
      iex> # First half (bd sd) repeated twice to fill cycle
      iex> length(events)
      4

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.Time.linger(0.25)
      iex> events = Pattern.events(pattern)
      iex> # First quarter (bd) repeated 4 times
      iex> length(events)
      4
  """
  def linger(%Pattern{} = pattern, fraction)
      when is_number(fraction) and fraction > 0.0 and fraction <= 1.0 do
    # Extract events in the first 'fraction' of the pattern
    extracted =
      pattern.events
      |> Enum.filter(fn event -> event.time < fraction end)

    # Calculate how many times to repeat
    repetitions = round(1.0 / fraction)

    # Create repeated events
    new_events =
      for rep <- 0..(repetitions - 1) do
        offset = rep * fraction

        Enum.map(extracted, fn event ->
          %{event | time: event.time + offset}
        end)
      end
      |> List.flatten()
      |> Enum.sort_by(& &1.time)

    %{pattern | events: new_events}
  end
end
