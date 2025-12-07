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
  Speed up a pattern by a factor, making it play faster.

  `fast(2)` doubles the speed, fitting the pattern twice per cycle.
  `fast(4)` quadruples the speed, fitting it four times per cycle.

  This is one of the most essential pattern functions - use it to create
  rapid rhythms, fills, or to match different patterns together.

  ## Examples

      # Double-time hi-hats
      s("hh") |> fast(2)

      # Create a drum roll by speeding up 4x
      s("bd") |> fast(4)

      # Fractional values work too - 1.5x speed
      s("bd sd hh cp") |> fast(1.5)

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
  Slow down a pattern by a factor, stretching it over more cycles.

  `slow(2)` halves the speed - the pattern takes 2 cycles to complete.
  `slow(4)` plays the pattern over 4 cycles.

  Useful for creating longer phrases, ambient textures, or making
  melodic patterns span multiple bars.

  ## Examples

      # Stretch a melody over 2 bars
      note("c4 e4 g4 c5") |> s("piano") |> slow(2)

      # Create a long evolving drone
      note("c2") |> s("sine") |> slow(8)

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
  Shift pattern earlier in time (wraps around the cycle).

  Use to create anticipation effects or offset patterns against each other.
  The amount is in fractions of a cycle (0.25 = one quarter beat early).

  ## Examples

      # Anticipate the downbeat by 1/8 cycle
      s("bd") |> early(0.125)

      # Offset two patterns to create call-and-response
      s("bd sd") |> stack(s("hh hh") |> early(0.25))

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
  Shift pattern later in time (wraps around the cycle).

  Use for laid-back feels, delay effects, or offsetting patterns.
  The amount is in fractions of a cycle (0.25 = one quarter beat late).

  ## Examples

      # Create a lazy/laid-back snare
      s("~ sd ~ sd") |> late(0.05)

      # Offset hi-hats for groove
      s("hh*4") |> late(0.0625)

      iex> pattern = Pattern.new("bd sd") |> Pattern.Time.late(0.25)
      iex> events = Pattern.events(pattern)
      iex> hd(events).time
      0.25
  """
  def late(%Pattern{} = pattern, amount) when is_number(amount) do
    early(pattern, -amount)
  end

  @doc """
  Repeat each event N times within its duration, creating rolls and stutters.

  Unlike `fast`, which speeds up the whole pattern, `ply` repeats each
  individual event in place. Great for drum rolls, glitchy effects, or
  adding rhythmic complexity.

  ## Examples

      # Snare roll - each snare repeats 4 times
      s("~ sd ~ sd") |> ply(4)

      # Stuttering hi-hats
      s("hh*4") |> ply(2)

      # Combine with fast for complex rhythms
      s("bd sd") |> fast(2) |> ply(2)

      iex> pattern = Pattern.new("bd sd") |> Pattern.Time.ply(2)
      iex> events = Pattern.events(pattern)
      iex> length(events)
      4
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
  Squeeze the pattern into a portion of the cycle, leaving silence elsewhere.

  `compress(0.0, 0.5)` plays the full pattern in the first half, then silence.
  `compress(0.25, 0.75)` plays the pattern in the middle half of the cycle.

  Great for creating gaps, breaks, or fitting patterns into specific
  parts of a bar.

  ## Examples

      # Play drums only in first half of cycle
      s("bd sd hh cp") |> compress(0.0, 0.5)

      # Create a breakdown with silence
      s("bd*4") |> compress(0.0, 0.25)

      # Play in the middle 50%
      note("c4 e4 g4") |> s("sine") |> compress(0.25, 0.75)

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.Time.compress(0.25, 0.75)
      iex> events = Pattern.events(pattern)
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
  Zoom into a portion of the pattern and expand it to fill the cycle.

  `zoom(0.0, 0.5)` takes the first half of the pattern and stretches it.
  `zoom(0.25, 0.75)` extracts the middle portion and expands it.

  The inverse of `compress` - useful for focusing on part of a pattern
  or creating variations by sampling different sections.

  ## Examples

      # Focus on just the first half of the pattern
      s("bd sd hh cp") |> zoom(0.0, 0.5)  # Just "bd sd" expanded

      # Extract the middle section
      note("c4 d4 e4 f4 g4") |> zoom(0.25, 0.75)

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.Time.zoom(0.25, 0.75)
      iex> events = Pattern.events(pattern)
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
  Repeat the first portion of a pattern to fill the whole cycle.

  `linger(0.5)` takes the first half and repeats it twice.
  `linger(0.25)` takes the first quarter and repeats it 4 times.

  Creates hypnotic, looping effects by focusing on a small fragment.
  Also known as `fastgap` in Strudel/TidalCycles.

  ## Examples

      # Loop just the kick drum
      s("bd sd hh cp") |> linger(0.25)  # "bd bd bd bd"

      # Create a hypnotic 2-note loop from a longer phrase
      note("c4 e4 g4 c5") |> linger(0.5)  # "c4 e4 c4 e4"

      # Micro-loop for glitchy effects
      s("breaks") |> linger(0.125)

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.Time.linger(0.5)
      iex> events = Pattern.events(pattern)
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
