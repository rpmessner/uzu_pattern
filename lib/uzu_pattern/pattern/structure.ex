defmodule UzuPattern.Pattern.Structure do
  @moduledoc """
  Structural pattern manipulation functions.

  This module provides functions for modifying the structure of patterns,
  including reversing, filtering, degradation, and stereo effects.

  ## Functions

  - `rev/1` - Reverse pattern
  - `palindrome/1` - Forward then backward
  - `struct_fn/2` - Apply rhythmic structure
  - `mask/2` - Silence based on mask pattern
  - `degrade/1` - Remove ~50% of events randomly
  - `degrade_by/2` - Remove events with custom probability
  - `jux/2` - Apply function to right channel (stereo)
  - `jux_by/3` - Parameterized stereo jux

  ## Examples

      iex> import UzuPattern.Pattern.Structure
      iex> pattern = Pattern.new("bd sd hh") |> rev() |> degrade_by(0.3)
  """

  alias UzuPattern.Pattern

  @doc """
  Reverse the order of events in a pattern.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh") |> Pattern.Structure.rev()
      iex> events = Pattern.events(pattern)
      iex> hd(events).sound
      "hh"
  """
  def rev(%Pattern{} = pattern) do
    new_events =
      pattern.events
      |> Enum.map(fn event ->
        new_time = 1.0 - event.time - event.duration
        %{event | time: max(0.0, new_time)}
      end)
      |> Enum.sort_by(& &1.time)

    %{pattern | events: new_events}
  end

  @doc """
  Create a palindrome pattern (forward then backward).

  ## Examples

      iex> pattern = Pattern.new("bd sd hh") |> Pattern.Structure.palindrome()
      iex> length(Pattern.events(pattern))
      6
  """
  def palindrome(%Pattern{} = pattern) do
    UzuPattern.Pattern.Combinators.cat([pattern, rev(pattern)])
  end

  @doc """
  Apply rhythmic structure from a mini-notation pattern.

  Uses 'x' for events and '~' for rests. The structure pattern determines
  which events from the source pattern are kept.

  ## Examples

      iex> pattern = Pattern.new("c eb g") |> Pattern.Structure.struct_fn("x ~ x ~")
      iex> events = Pattern.events(pattern)
      iex> # Only events at positions 0 and 2 are kept (where 'x' appears)
  """
  def struct_fn(%Pattern{} = pattern, structure_string) when is_binary(structure_string) do
    # Parse the structure pattern
    struct_events = UzuParser.parse(structure_string)

    # Keep only pattern events that align with 'x' markers
    new_events =
      pattern.events
      |> Enum.filter(fn event ->
        # Check if there's a struct event at this time position
        Enum.any?(struct_events, fn struct_event ->
          # Allow small epsilon for floating point comparison
          abs(event.time - struct_event.time) < 0.001 and
            struct_event.sound != "~"
        end)
      end)

    %{pattern | events: new_events}
  end

  @doc """
  Silence events based on a mask pattern.

  Returns silence (removes events) when mask is 0 or '~'.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.Structure.mask("1 0 1 0")
      iex> events = Pattern.events(pattern)
      iex> # Only bd and hh remain (positions 0 and 2 where mask is 1)
  """
  def mask(%Pattern{} = pattern, mask_string) when is_binary(mask_string) do
    # Parse the mask pattern
    mask_events = UzuParser.parse(mask_string)

    # Keep only pattern events where mask is not 0 or ~
    new_events =
      pattern.events
      |> Enum.filter(fn event ->
        # Find the corresponding mask event
        Enum.any?(mask_events, fn mask_event ->
          # Check if times align and mask value is not 0 or ~
          abs(event.time - mask_event.time) < 0.001 and
            mask_event.sound != "~" and
            mask_event.sound != "0"
        end)
      end)

    %{pattern | events: new_events}
  end

  @doc """
  Randomly remove events with a given probability.

  Unlike `sometimes_by`, this operates on individual events, not the whole pattern.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.Structure.degrade_by(0.5)
      iex> # ~50% of events removed (randomly)
  """
  def degrade_by(%Pattern{} = pattern, probability)
      when is_float(probability) and probability >= 0.0 and probability <= 1.0 do
    new_events = Enum.filter(pattern.events, fn _event -> :rand.uniform() > probability end)
    %{pattern | events: new_events}
  end

  @doc """
  Randomly remove ~50% of events.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.Structure.degrade()
  """
  def degrade(%Pattern{} = pattern) do
    degrade_by(pattern, 0.5)
  end

  @doc """
  Apply a function to create a stereo effect.

  Creates two copies of the pattern: original panned left, transformed panned right.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Structure.jux(&Pattern.Structure.rev/1)
      iex> length(Pattern.events(pattern))
      4
  """
  def jux(%Pattern{} = pattern, fun) when is_function(fun, 1) do
    jux_by(pattern, 1.0, fun)
  end

  @doc """
  Apply a function to create a partial stereo effect.

  Like jux/2 but allows control over how much the transformed version is panned.
  Amount ranges from 0.0 (no effect) to 1.0 (full stereo separation).

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Structure.jux_by(0.5, &Pattern.Structure.rev/1)
      iex> length(Pattern.events(pattern))
      4
  """
  def jux_by(%Pattern{} = pattern, amount, fun)
      when is_number(amount) and amount >= 0.0 and amount <= 1.0 and is_function(fun, 1) do
    left_events = Enum.map(pattern.events, fn e -> %{e | params: Map.put(e.params, :pan, -amount)} end)
    right_pattern = fun.(pattern)
    right_events = Enum.map(right_pattern.events, fn e -> %{e | params: Map.put(e.params, :pan, amount)} end)

    all_events = Enum.sort_by(left_events ++ right_events, & &1.time)
    %{pattern | events: all_events}
  end
end
