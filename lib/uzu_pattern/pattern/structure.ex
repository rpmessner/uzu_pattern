defmodule UzuPattern.Pattern.Structure do
  @moduledoc """
  Structure manipulation functions for patterns.

  These functions modify the structure and arrangement of events:
  - `rev/1`, `palindrome/1` - Reverse patterns
  - `struct_fn/2`, `mask/2` - Apply rhythmic structure
  - `degrade/1`, `degrade_by/2` - Random event removal
  - `jux/2`, `jux_by/3` - Stereo effects
  - `superimpose/2`, `off/3` - Layer transformed copies
  - `echo/4` - Rhythmic echoes
  - `striate/2`, `chop/2` - Slice patterns
  """

  alias UzuPattern.Pattern
  alias UzuPattern.Pattern.Effects

  @doc """
  Reverse the pattern within each cycle.
  """
  def rev(%Pattern{} = pattern) do
    Pattern.new(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.map(fn event ->
        %{event | time: 1.0 - event.time - event.duration}
      end)
      |> Enum.sort_by(& &1.time)
    end)
  end

  @doc """
  Create a palindrome pattern (forward then backward within each cycle).
  """
  def palindrome(%Pattern{} = pattern) do
    Pattern.fastcat([pattern, rev(pattern)])
  end

  @doc """
  Apply rhythmic structure from a structural pattern.

  Uses a pattern to determine which events from the source pattern are kept.
  Events in the structure pattern with non-rest values mark positions to keep.
  """
  def struct_fn(%Pattern{} = pattern, %Pattern{} = structure) do
    Pattern.new(fn cycle ->
      pattern_events = Pattern.query(pattern, cycle)
      struct_events = Pattern.query(structure, cycle)

      Enum.filter(pattern_events, fn event ->
        Enum.any?(struct_events, fn struct_event ->
          abs(event.time - struct_event.time) < 0.001
        end)
      end)
    end)
  end

  @doc """
  Silence events based on a mask pattern.

  Events are kept only where the mask pattern has non-zero, non-rest events.
  Mask values of "0" or "~" will filter out corresponding events.
  """
  def mask(%Pattern{} = pattern, %Pattern{} = mask_pattern) do
    Pattern.new(fn cycle ->
      pattern_events = Pattern.query(pattern, cycle)
      mask_events = Pattern.query(mask_pattern, cycle)

      active_mask_events =
        Enum.filter(mask_events, fn event ->
          event.sound not in ["0", "~", "rest"]
        end)

      Enum.filter(pattern_events, fn event ->
        Enum.any?(active_mask_events, fn mask_event ->
          abs(event.time - mask_event.time) < 0.001
        end)
      end)
    end)
  end

  @doc """
  Randomly remove events with a given probability.

  Uses cycle number as seed for deterministic randomness.
  """
  def degrade_by(%Pattern{} = pattern, probability)
      when is_float(probability) and probability >= 0.0 and probability <= 1.0 do
    Pattern.new(fn cycle ->
      :rand.seed(:exsss, {cycle, cycle * 7, cycle * 13})

      pattern
      |> Pattern.query(cycle)
      |> Enum.filter(fn _event -> :rand.uniform() > probability end)
    end)
  end

  @doc """
  Randomly remove ~50% of events.
  """
  def degrade(%Pattern{} = pattern) do
    degrade_by(pattern, 0.5)
  end

  @doc """
  Create a stereo effect by playing original and transformed versions in different ears.

  Original plays on the left, transformed version plays on the right.
  """
  def jux(%Pattern{} = pattern, fun) when is_function(fun, 1) do
    jux_by(pattern, 1.0, fun)
  end

  @doc """
  Apply a function to create a partial stereo effect.

  Amount controls pan separation (0.0 = no effect, 1.0 = full stereo).
  Pan values range from -1.0 (left) to 1.0 (right).
  """
  def jux_by(%Pattern{} = pattern, amount, fun)
      when is_number(amount) and amount >= 0.0 and amount <= 1.0 and is_function(fun, 1) do
    left_pan = -amount
    right_pan = amount

    left_pattern = Effects.pan(pattern, left_pan)
    right_pattern = pattern |> fun.() |> Effects.pan(right_pan)

    Pattern.stack([left_pattern, right_pattern])
  end

  @doc """
  Layer the original pattern with a transformed copy of itself.

  Superimpose is perfect for creating thickness and movement
  by combining the original with a modified version.
  """
  def superimpose(%Pattern{} = pattern, fun) when is_function(fun, 1) do
    Pattern.stack([pattern, fun.(pattern)])
  end

  @doc """
  Superimpose a delayed and transformed copy of the pattern.

  The transformed copy is offset by the given time amount.
  """
  def off(%Pattern{} = pattern, time_offset, fun)
      when is_number(time_offset) and is_function(fun, 1) do
    alias UzuPattern.Pattern.Time
    transformed = pattern |> fun.() |> Time.late(time_offset)
    Pattern.stack([pattern, transformed])
  end

  @doc """
  Create rhythmic echoes that fade out over time.

  Unlike the `delay` effect (which uses the audio engine), `echo`
  creates actual copies of events in the pattern, each quieter
  than the last.
  """
  def echo(%Pattern{} = pattern, n, time_offset, gain_factor)
      when is_integer(n) and n > 0 and is_number(time_offset) and
             is_number(gain_factor) and gain_factor >= 0.0 and gain_factor <= 1.0 do
    Pattern.new(fn cycle ->
      base_events = Pattern.query(pattern, cycle)

      echoes =
        for i <- 1..n do
          offset = time_offset * i
          gain_mult = :math.pow(gain_factor, i)

          Enum.map(base_events, fn e ->
            new_time = e.time + offset
            wrapped_time = new_time - Float.floor(new_time)
            current_gain = Map.get(e.params, :gain, 1.0)

            %{e | time: wrapped_time, params: Map.put(e.params, :gain, current_gain * gain_mult)}
          end)
        end
        |> List.flatten()

      Enum.sort_by(base_events ++ echoes, & &1.time)
    end)
  end

  @doc """
  Slice pattern into N parts and interleave them (stutter effect).
  """
  def striate(%Pattern{} = pattern, n) when is_integer(n) and n > 1 do
    Pattern.new(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.flat_map(fn event ->
        slice_duration = event.duration / n

        for i <- 0..(n - 1) do
          %{event | time: event.time + i * slice_duration, duration: slice_duration}
        end
      end)
      |> Enum.sort_by(& &1.time)
    end)
  end

  @doc """
  Chop pattern into N pieces.

  Divides each event into N equal parts.
  """
  def chop(%Pattern{} = pattern, n) when is_integer(n) and n > 1 do
    Pattern.new(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.flat_map(fn event ->
        piece_duration = event.duration / n

        for i <- 0..(n - 1) do
          %{event | time: event.time + i * piece_duration, duration: piece_duration}
        end
      end)
      |> Enum.sort_by(& &1.time)
    end)
  end
end
