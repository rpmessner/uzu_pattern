defmodule UzuPattern.Pattern.Combinators do
  alias UzuPattern.Pattern.Structure

  @moduledoc """
  Pattern combination and layering functions.

  This module provides functions for combining patterns in various ways,
  including stacking (simultaneous play), concatenation (sequential play),
  and creating delayed/transformed copies.

  ## Functions

  - `stack/1` - Play patterns simultaneously
  - `cat/1` - Play patterns sequentially
  - `palindrome/1` - Forward then backward pattern
  - `append/2` - Append second pattern after first
  - `superimpose/2` - Stack with transformation
  - `off/3` - Delayed copy with transform
  - `echo/3` - Multiple delayed copies with gain decay
  - `striate/2` - Interleave time slices
  - `chop/2` - Slice into equal pieces

  ## Examples

      iex> import UzuPattern.Pattern.Combinators
      iex> p1 = Pattern.new("bd")
      iex> p2 = Pattern.new("sd")
      iex> combined = stack([p1, p2])
  """

  alias UzuPattern.Pattern

  @doc """
  Layer multiple patterns to play at the same time.

  Stack is fundamental for building up complex beats from simple parts.
  Each pattern plays simultaneously, like tracks in a DAW.

  ## Examples

      # Classic drum pattern - kick, snare, and hi-hats together
      s("bd ~ bd ~") |> stack(s("~ sd ~ sd")) |> stack(s("hh*8"))

      # Layer a bass with chords
      note("c2") |> s("bass") |> stack(note("[c4,e4,g4]") |> s("piano"))

      # Using list form
      stack([s("bd*4"), s("hh*8"), s("~ sd ~ sd")])

      iex> p1 = Pattern.new("bd")
      iex> p2 = Pattern.new("sd")
      iex> combined = Pattern.Combinators.stack([p1, p2])
      iex> length(Pattern.events(combined))
      2
  """
  def stack(patterns) when is_list(patterns) do
    all_events =
      patterns
      |> Enum.flat_map(fn %Pattern{events: events} -> events end)
      |> Enum.sort_by(& &1.time)

    %Pattern{events: all_events, transforms: []}
  end

  @doc """
  Join patterns to play one after another in sequence.

  `cat` divides the cycle between the patterns, so each gets
  an equal share of time. Use for creating longer phrases
  that evolve over the cycle.

  ## Examples

      # Verse and chorus in one cycle
      s("bd sd") |> cat([s("bd*4")])  # First half simple, second half busy

      # A-B pattern structure
      cat([note("c4 e4"), note("g4 c5")])

      # Four-part sequence
      cat([s("bd"), s("sd"), s("hh"), s("cp")])

      iex> p1 = Pattern.new("bd")
      iex> p2 = Pattern.new("sd")
      iex> combined = Pattern.Combinators.cat([p1, p2])
      iex> events = Pattern.events(combined)
      iex> Enum.at(events, 1).time
      0.5
  """
  def cat(patterns) when is_list(patterns) do
    count = length(patterns)
    segment_duration = 1.0 / count

    all_events =
      patterns
      |> Enum.with_index()
      |> Enum.flat_map(fn {%Pattern{events: events}, index} ->
        offset = index * segment_duration

        Enum.map(events, fn event ->
          %{event | time: offset + event.time * segment_duration, duration: event.duration * segment_duration}
        end)
      end)
      |> Enum.sort_by(& &1.time)

    %Pattern{events: all_events, transforms: []}
  end

  @doc """
  Create a palindrome pattern (forward then backward).

  ## Examples

      iex> pattern = Pattern.new("bd sd hh") |> Pattern.Combinators.palindrome()
      iex> length(Pattern.events(pattern))
      6
  """
  def palindrome(%Pattern{} = pattern) do
    cat([pattern, Structure.rev(pattern)])
  end

  @doc """
  Append a second pattern after the first pattern.

  The second pattern plays in the next cycle.

  ## Examples

      iex> p1 = Pattern.new("bd sd")
      iex> p2 = Pattern.new("hh cp")
      iex> pattern = Pattern.Combinators.append(p1, p2)
      iex> length(Pattern.events(pattern))
      4
  """
  def append(%Pattern{} = pattern, %Pattern{} = other) do
    # Shift other pattern's events to start after this pattern
    shifted_events =
      Enum.map(other.events, fn e ->
        %{e | time: e.time + 1.0}
      end)

    all_events = Enum.sort_by(pattern.events ++ shifted_events, & &1.time)
    %{pattern | events: all_events}
  end

  @doc """
  Layer the original pattern with a transformed copy of itself.

  Superimpose is perfect for creating thickness and movement
  by combining the original with a modified version - like adding
  a harmony or rhythmic variation on top.

  ## Examples

      # Original plus double-speed version
      s("bd sd hh cp") |> superimpose(&fast(&1, 2))

      # Add a delayed, quieter copy
      note("c4 e4 g4") |> superimpose(&(late(&1, 0.125) |> gain(&1, 0.5)))

      # Layer with pitch-shifted version
      note("c3 e3 g3") |> s("sine") |> superimpose(&note(&1, "c4 e4 g4"))

      iex> pattern = Pattern.new("c3 eb3 g3") |> Pattern.Combinators.superimpose(&UzuPattern.Pattern.Time.fast(&1, 2))
      iex> events = Pattern.events(pattern)
      iex> length(events) > 3
      true
  """
  def superimpose(%Pattern{} = pattern, fun) when is_function(fun, 1) do
    transformed = fun.(pattern)
    all_events = Enum.sort_by(pattern.events ++ transformed.events, & &1.time)
    %{pattern | events: all_events}
  end

  @doc """
  Superimpose a delayed and transformed copy of the pattern.

  The transformed copy is offset by the given time amount.

  ## Examples

      iex> pattern = Pattern.new("c3 eb3 g3") |> Pattern.Combinators.off(0.125, &UzuPattern.Pattern.Time.fast(&1, 2))
      iex> length(Pattern.events(pattern)) > 3
      true
  """
  def off(%Pattern{} = pattern, time_offset, fun)
      when is_number(time_offset) and is_function(fun, 1) do
    transformed = fun.(pattern)

    offset_events =
      Enum.map(transformed.events, fn e ->
        new_time = e.time + time_offset
        wrapped_time = new_time - Float.floor(new_time)
        %{e | time: wrapped_time}
      end)

    all_events = Enum.sort_by(pattern.events ++ offset_events, & &1.time)
    %{pattern | events: all_events}
  end

  @doc """
  Create rhythmic echoes that fade out over time.

  Unlike the `delay` effect (which uses the audio engine), `echo`
  creates actual copies of events in the pattern, each quieter
  than the last.

  Parameters:
  - `n`: how many echoes
  - `time_offset`: time between echoes (fraction of cycle)
  - `gain_factor`: how much quieter each echo gets (0.8 = 20% quieter)

  ## Examples

      # Snare with 3 fading echoes
      s("~ sd ~ ~") |> echo(3, 0.125, 0.6)

      # Melodic echoes for arpeggio effect
      note("c4") |> s("piano") |> echo(4, 0.25, 0.7)

      # Stutter effect with rapid quiet echoes
      s("bd") |> echo(6, 0.0625, 0.5)

      iex> pattern = Pattern.new("bd sd") |> Pattern.Combinators.echo(3, 0.125, 0.8)
      iex> length(Pattern.events(pattern)) > 2
      true
  """
  def echo(%Pattern{} = pattern, n, time_offset, gain_factor)
      when is_integer(n) and n > 0 and is_number(time_offset) and is_number(gain_factor) and
             gain_factor >= 0.0 and gain_factor <= 1.0 do
    echoes =
      for i <- 1..n do
        offset = time_offset * i
        gain = :math.pow(gain_factor, i)

        Enum.map(pattern.events, fn e ->
          new_time = e.time + offset
          wrapped_time = new_time - Float.floor(new_time)
          current_gain = Map.get(e.params, :gain, 1.0)

          %{e | time: wrapped_time, params: Map.put(e.params, :gain, current_gain * gain)}
        end)
      end
      |> List.flatten()

    all_events = Enum.sort_by(pattern.events ++ echoes, & &1.time)
    %{pattern | events: all_events}
  end

  @doc """
  Slice pattern into N parts and interleave them.

  Each event is divided into slices, creating a stuttering effect.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Combinators.striate(4)
      iex> length(Pattern.events(pattern)) > 2
      true
  """
  def striate(%Pattern{} = pattern, n) when is_integer(n) and n > 1 do
    new_events =
      pattern.events
      |> Enum.flat_map(fn event ->
        slice_duration = event.duration / n

        for i <- 0..(n - 1) do
          %{event | time: event.time + i * slice_duration, duration: slice_duration}
        end
      end)
      |> Enum.sort_by(& &1.time)

    %{pattern | events: new_events}
  end

  @doc """
  Chop pattern into N pieces.

  Divides each event into N equal parts.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Combinators.chop(4)
      iex> length(Pattern.events(pattern)) == 8
      true
  """
  def chop(%Pattern{} = pattern, n) when is_integer(n) and n > 1 do
    new_events =
      pattern.events
      |> Enum.flat_map(fn event ->
        piece_duration = event.duration / n

        for i <- 0..(n - 1) do
          %{event | time: event.time + i * piece_duration, duration: piece_duration}
        end
      end)
      |> Enum.sort_by(& &1.time)

    %{pattern | events: new_events}
  end
end
