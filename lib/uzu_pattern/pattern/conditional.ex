defmodule UzuPattern.Pattern.Conditional do
  @moduledoc """
  Cycle-aware conditional modifiers for patterns.

  These functions store transformations that are resolved at query time
  based on the cycle number, enabling patterns that evolve over time.

  ## Functions

  - `every/3` - Apply function every N cycles
  - `sometimes_by/3` - Apply with custom probability
  - `sometimes/2` - Apply with 50% probability
  - `often/2` - Apply with 75% probability
  - `rarely/2` - Apply with 25% probability
  - `iter/2` - Rotate pattern start each cycle
  - `iter_back/2` - Rotate backwards each cycle
  - `first_of/3` - Apply on first of N cycles
  - `last_of/3` - Apply on last of N cycles
  - `when_fn/3` - Apply when condition is true
  - `chunk/3` - Apply to rotating chunks
  - `chunk_back/3` - Apply to chunks in reverse

  ## Examples

      iex> import UzuPattern.Pattern.Conditional
      iex> pattern = Pattern.new("bd sd") |> every(4, &Pattern.Structure.rev/1)
  """

  alias UzuPattern.Pattern

  @doc """
  Apply a function every N cycles.

  This is a cycle-aware transformation - the function is applied based on
  the cycle number when `query/2` is called.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Conditional.every(4, &UzuPattern.Pattern.Structure.rev/1)
      iex> # On cycle 0, 4, 8... the pattern is reversed
      iex> Pattern.query(pattern, 0) |> length()
      2
  """
  def every(%Pattern{} = pattern, n, fun) when is_integer(n) and n > 0 and is_function(fun, 1) do
    transform = {:every, n, fun}
    %{pattern | transforms: pattern.transforms ++ [transform]}
  end

  @doc """
  Apply a function with a given probability per cycle.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Conditional.sometimes_by(0.5, &UzuPattern.Pattern.Structure.rev/1)
      iex> # 50% chance to reverse each cycle
  """
  def sometimes_by(%Pattern{} = pattern, probability, fun)
      when is_float(probability) and probability >= 0.0 and probability <= 1.0 and is_function(fun, 1) do
    transform = {:sometimes_by, probability, fun}
    %{pattern | transforms: pattern.transforms ++ [transform]}
  end

  @doc """
  Apply a function with 50% probability per cycle.

  ## Examples

      iex> pattern = Pattern.new("bd sd") |> Pattern.Conditional.sometimes(&UzuPattern.Pattern.Structure.rev/1)
  """
  def sometimes(%Pattern{} = pattern, fun) when is_function(fun, 1) do
    sometimes_by(pattern, 0.5, fun)
  end

  @doc """
  Apply a function with 75% probability per cycle.
  """
  def often(%Pattern{} = pattern, fun) when is_function(fun, 1) do
    sometimes_by(pattern, 0.75, fun)
  end

  @doc """
  Apply a function with 25% probability per cycle.
  """
  def rarely(%Pattern{} = pattern, fun) when is_function(fun, 1) do
    sometimes_by(pattern, 0.25, fun)
  end

  @doc """
  Rotate the pattern start position each cycle.

  Divides the pattern into N subdivisions and shifts the starting point by
  one subdivision each cycle. Creates evolving patterns.

  This is a cycle-aware transformation - resolved at query time.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.Conditional.iter(4)
      iex> # Cycle 0: starts at bd (subdivision 0)
      iex> # Cycle 1: starts at sd (subdivision 1)
      iex> # Cycle 2: starts at hh (subdivision 2)
      iex> # Cycle 3: starts at cp (subdivision 3)
      iex> # Cycle 4: wraps back to bd
  """
  def iter(%Pattern{} = pattern, n) when is_integer(n) and n > 0 do
    transform = {:iter, n}
    %{pattern | transforms: pattern.transforms ++ [transform]}
  end

  @doc """
  Rotate the pattern start position backwards each cycle.

  Like iter/2 but rotates in reverse. Also known as iter' in TidalCycles.

  ## Examples

      iex> pattern = Pattern.new("bd sd hh cp") |> Pattern.Conditional.iter_back(4)
      iex> # Cycle 0: starts at bd
      iex> # Cycle 1: starts at cp (backwards rotation)
      iex> # Cycle 2: starts at hh
  """
  def iter_back(%Pattern{} = pattern, n) when is_integer(n) and n > 0 do
    transform = {:iter_back, n}
    %{pattern | transforms: pattern.transforms ++ [transform]}
  end

  @doc """
  Apply a function every N cycles, starting from the first cycle.

  Similar to every/3, but only applies on cycles where (cycle mod n) == 0.

  ## Examples

      iex> pattern = Pattern.new("c3 d3 e3 g3") |> Pattern.Conditional.first_of(4, &UzuPattern.Pattern.Structure.rev/1)
      iex> # On cycles 0, 4, 8... the pattern is reversed
      iex> # On cycles 1, 2, 3, 5, 6, 7... the pattern is unchanged
  """
  def first_of(%Pattern{} = pattern, n, fun) when is_integer(n) and n > 0 and is_function(fun, 1) do
    transform = {:first_of, n, fun}
    %{pattern | transforms: pattern.transforms ++ [transform]}
  end

  @doc """
  Apply a function every N cycles, starting from the last cycle.

  Applies on cycles where (cycle mod n) == (n - 1).

  ## Examples

      iex> pattern = Pattern.new("c3 d3 e3 g3") |> Pattern.Conditional.last_of(4, &UzuPattern.Pattern.Structure.rev/1)
      iex> # On cycles 3, 7, 11... the pattern is reversed (last of each 4-cycle group)
  """
  def last_of(%Pattern{} = pattern, n, fun) when is_integer(n) and n > 0 and is_function(fun, 1) do
    transform = {:last_of, n, fun}
    %{pattern | transforms: pattern.transforms ++ [transform]}
  end

  @doc """
  Apply a function when a condition function returns true.

  The condition function receives the cycle number and should return a boolean.

  ## Examples

      iex> pattern = Pattern.new("c3 eb3 g3") |> Pattern.Conditional.when_fn(fn cycle -> rem(cycle, 2) == 1 end, &UzuPattern.Pattern.Structure.rev/1)
      iex> # Pattern is reversed on odd cycles
  """
  def when_fn(%Pattern{} = pattern, condition_fn, fun)
      when is_function(condition_fn, 1) and is_function(fun, 1) do
    transform = {:when_fn, condition_fn, fun}
    %{pattern | transforms: pattern.transforms ++ [transform]}
  end

  @doc """
  Divide pattern into N parts, applying function to each part in turn per cycle.

  On cycle 0, the function is applied to part 0. On cycle 1, to part 1, etc.
  Cycles through parts in order.

  ## Examples

      iex> pattern = Pattern.new("0 1 2 3") |> Pattern.Conditional.chunk(4, &UzuPattern.Pattern.Structure.rev/1)
      iex> # Cycle 0: first quarter reversed
      iex> # Cycle 1: second quarter reversed
      iex> # Cycle 2: third quarter reversed
      iex> # Cycle 3: fourth quarter reversed
  """
  def chunk(%Pattern{} = pattern, n, fun) when is_integer(n) and n > 0 and is_function(fun, 1) do
    transform = {:chunk, n, fun}
    %{pattern | transforms: pattern.transforms ++ [transform]}
  end

  @doc """
  Like chunk/3 but cycles through parts in reverse order.

  Also known as chunk' in TidalCycles.

  ## Examples

      iex> pattern = Pattern.new("0 1 2 3") |> Pattern.Conditional.chunk_back(4, &UzuPattern.Pattern.Structure.rev/1)
      iex> # Cycle 0: fourth quarter reversed
      iex> # Cycle 1: third quarter reversed
  """
  def chunk_back(%Pattern{} = pattern, n, fun) when is_integer(n) and n > 0 and is_function(fun, 1) do
    transform = {:chunk_back, n, fun}
    %{pattern | transforms: pattern.transforms ++ [transform]}
  end
end
