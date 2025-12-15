defmodule UzuPattern.Pattern.Conditional do
  @moduledoc """
  Conditional transformation functions for patterns.

  These functions apply transformations based on conditions:
  - `every/3`, `every/4` - Apply every N cycles
  - `sometimes/2`, `often/2`, `rarely/2` - Probability-based
  - `iter/2`, `iter_back/2` - Rotate pattern each cycle
  - `first_of/3`, `last_of/3` - Apply on specific cycles
  - `when_fn/3` - Apply when condition is true
  - `chunk/3`, `chunk_back/3` - Apply to rotating sections
  """

  alias UzuPattern.Pattern
  alias UzuPattern.Pattern.Time
  alias UzuPattern.Hap

  @doc """
  Apply a function every n cycles.

  ## Examples

      iex> p = Pattern.pure("bd")
      ...>     |> Pattern.every(2, &Pattern.fast(&1, 2))
      iex> length(Pattern.query(p, 0))  # cycle 0: fast applied
      2
      iex> length(Pattern.query(p, 1))  # cycle 1: no change
      1
  """
  def every(%Pattern{} = pattern, n, fun) when n > 0 and is_function(fun, 1) do
    Pattern.from_cycles(fn cycle ->
      if rem(cycle, n) == 0 do
        pattern |> fun.() |> Pattern.query(cycle)
      else
        Pattern.query(pattern, cycle)
      end
    end)
  end

  @doc """
  Apply a function every n cycles, starting at a given offset.

  - `every(pattern, 4, 0, f)` - apply on cycles 0, 4, 8, 12...
  - `every(pattern, 4, 1, f)` - apply on cycles 1, 5, 9, 13...
  """
  def every(%Pattern{} = pattern, n, offset, fun)
      when is_integer(n) and n > 0 and is_integer(offset) and offset >= 0 and offset < n and
             is_function(fun, 1) do
    Pattern.from_cycles(fn cycle ->
      if rem(cycle, n) == offset do
        pattern |> fun.() |> Pattern.query(cycle)
      else
        Pattern.query(pattern, cycle)
      end
    end)
  end

  @doc """
  Apply a function with a given probability per cycle.

  Uses cycle number as random seed for deterministic but varied behavior.
  """
  def sometimes_by(%Pattern{} = pattern, probability, fun)
      when is_float(probability) and probability >= 0.0 and probability <= 1.0 and
             is_function(fun, 1) do
    Pattern.from_cycles(fn cycle ->
      :rand.seed(:exsss, {cycle, cycle * 7, cycle * 13})

      if :rand.uniform() < probability do
        pattern |> fun.() |> Pattern.query(cycle)
      else
        Pattern.query(pattern, cycle)
      end
    end)
  end

  @doc """
  Apply a transformation 50% of the time.
  """
  def sometimes(%Pattern{} = pattern, fun) when is_function(fun, 1) do
    sometimes_by(pattern, 0.5, fun)
  end

  @doc """
  Apply a transformation 75% of the time.
  """
  def often(%Pattern{} = pattern, fun) when is_function(fun, 1) do
    sometimes_by(pattern, 0.75, fun)
  end

  @doc """
  Apply a transformation 25% of the time.
  """
  def rarely(%Pattern{} = pattern, fun) when is_function(fun, 1) do
    sometimes_by(pattern, 0.25, fun)
  end

  @doc """
  Rotate the pattern's starting point each cycle.

  Creates evolving grooves that shift phase over time.
  """
  def iter(%Pattern{} = pattern, n) when is_integer(n) and n > 0 do
    Pattern.from_cycles(fn cycle ->
      rotation = rem(cycle, n)

      if rotation == 0 do
        Pattern.query(pattern, cycle)
      else
        pattern |> Time.early(rotation / n) |> Pattern.query(cycle)
      end
    end)
  end

  @doc """
  Rotate the pattern start position backwards each cycle.

  Like iter/2 but rotates in reverse.
  """
  def iter_back(%Pattern{} = pattern, n) when is_integer(n) and n > 0 do
    Pattern.from_cycles(fn cycle ->
      rotation = rem(cycle, n)

      if rotation == 0 do
        Pattern.query(pattern, cycle)
      else
        backward_rotation = n - rotation
        pattern |> Time.early(backward_rotation / n) |> Pattern.query(cycle)
      end
    end)
  end

  @doc """
  Apply a function on the first cycle of every N cycles.

  Applies on cycles where (cycle mod n) == 0.
  """
  def first_of(%Pattern{} = pattern, n, fun)
      when is_integer(n) and n > 0 and is_function(fun, 1) do
    every(pattern, n, 0, fun)
  end

  @doc """
  Apply a function on the last cycle of every N cycles.

  Applies on cycles where (cycle mod n) == (n - 1).
  """
  def last_of(%Pattern{} = pattern, n, fun)
      when is_integer(n) and n > 0 and is_function(fun, 1) do
    every(pattern, n, n - 1, fun)
  end

  @doc """
  Apply a function when a condition function returns true.

  The condition function receives the cycle number.
  """
  def when_fn(%Pattern{} = pattern, condition_fn, fun)
      when is_function(condition_fn, 1) and is_function(fun, 1) do
    Pattern.from_cycles(fn cycle ->
      if condition_fn.(cycle) do
        pattern |> fun.() |> Pattern.query(cycle)
      else
        Pattern.query(pattern, cycle)
      end
    end)
  end

  @doc """
  Divide pattern into N parts, applying function to each part in turn per cycle.

  On cycle 0, the function is applied to part 0. On cycle 1, to part 1, etc.
  """
  def chunk(%Pattern{} = pattern, n, fun)
      when is_integer(n) and n > 0 and is_function(fun, 1) do
    Pattern.from_cycles(fn cycle ->
      chunk_index = rem(cycle, n)
      chunk_start = chunk_index / n
      chunk_end = (chunk_index + 1) / n

      haps = Pattern.query(pattern, cycle)

      Enum.map(haps, fn hap ->
        onset = Hap.onset(hap) || hap.part.begin

        if onset >= chunk_start and onset < chunk_end do
          temp_pattern = Pattern.from_haps([hap])

          case Pattern.query(fun.(temp_pattern), cycle) do
            [transformed] -> transformed
            _ -> hap
          end
        else
          hap
        end
      end)
    end)
  end

  @doc """
  Like chunk/3 but cycles through parts in reverse order.
  """
  def chunk_back(%Pattern{} = pattern, n, fun)
      when is_integer(n) and n > 0 and is_function(fun, 1) do
    Pattern.from_cycles(fn cycle ->
      chunk_index = n - 1 - rem(cycle, n)
      chunk_start = chunk_index / n
      chunk_end = (chunk_index + 1) / n

      haps = Pattern.query(pattern, cycle)

      Enum.map(haps, fn hap ->
        onset = Hap.onset(hap) || hap.part.begin

        if onset >= chunk_start and onset < chunk_end do
          temp_pattern = Pattern.from_haps([hap])

          case Pattern.query(fun.(temp_pattern), cycle) do
            [transformed] -> transformed
            _ -> hap
          end
        else
          hap
        end
      end)
    end)
  end
end
