defmodule UzuPattern.Pattern.Combinators do
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
  Stack multiple patterns to play simultaneously.

  ## Examples

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
  Concatenate patterns to play sequentially.

  ## Examples

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
    cat([pattern, UzuPattern.Pattern.Structure.rev(pattern)])
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
  Superimpose a transformed version on top of the original pattern.

  Stacks the pattern with a transformed copy of itself.

  ## Examples

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
  Create multiple delayed copies with decreasing gain.

  Parameters:
  - n: number of echoes
  - time_offset: time between echoes (in cycles)
  - gain_factor: multiplier for gain reduction (0.0-1.0)

  ## Examples

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
