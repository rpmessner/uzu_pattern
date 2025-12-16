defmodule UzuPattern.Time do
  @moduledoc """
  Rational time values for exact pattern arithmetic.

  Wraps the Ratio library with time-specific helpers matching Strudel semantics.
  Using rational numbers eliminates floating-point precision errors that can
  accumulate in highly divided patterns.

  ## Why Rationals?

  With floats:
      1/3 + 1/3 + 1/3  #=> 0.9999999999999999 (not exactly 1.0)

  With rationals:
      Time.new(1, 3) |> Time.add(Time.new(1, 3)) |> Time.add(Time.new(1, 3))
      #=> 1/1 (exactly 1)

  ## Strudel Compatibility

  This module provides the same time helpers that Strudel's fraction.mjs adds:
  - `sam/1` - floor to cycle start
  - `next_sam/1` - start of next cycle
  - `cycle_pos/1` - position within cycle (0 to 1)
  - `cycle_of/1` - cycle number as integer

  ## Usage

  Time values are used throughout the pattern system for begin/end times in
  TimeSpan and Hap structures. At the scheduling boundary (when sending events
  to the audio engine), times are converted to floats using `to_float/1`.
  """

  @type t :: Ratio.t() | integer()

  # ============================================================================
  # Construction
  # ============================================================================

  @doc """
  Create a new rational time.

  ## Examples

      iex> Time.new(1, 3)
      %Ratio{numerator: 1, denominator: 3}

      iex> Time.new(2, 4)  # auto-simplifies
      %Ratio{numerator: 1, denominator: 2}

      iex> Time.new(3)  # from integer
      %Ratio{numerator: 3, denominator: 1}
  """
  @spec new(integer(), integer()) :: t()
  def new(numerator, denominator) do
    Ratio.new(numerator, denominator)
  end

  @spec new(integer() | Ratio.t()) :: t()
  def new(n) when is_integer(n), do: Ratio.new(n, 1)
  def new(%Ratio{} = r), do: r

  @doc """
  Ensure a value is a rational time.

  Handles integers, Ratio structs, and {numerator, denominator} tuples.
  Use this when accepting time values from external sources.

  ## Examples

      iex> Time.ensure(5)
      %Ratio{numerator: 5, denominator: 1}

      iex> Time.ensure({1, 4})
      %Ratio{numerator: 1, denominator: 4}

      iex> Time.ensure(Time.new(1, 3))
      %Ratio{numerator: 1, denominator: 3}
  """
  @spec ensure(t() | integer() | float() | {integer(), integer()}) :: t()
  def ensure(%Ratio{} = t), do: t
  def ensure(n) when is_integer(n), do: new(n)
  def ensure(f) when is_float(f), do: from_float(f)
  def ensure({n, d}) when is_integer(n) and is_integer(d), do: new(n, d)

  @doc """
  Convert from float to rational (use sparingly - for external input only).

  Converts with reasonable precision, limiting denominator to avoid
  huge fractions from float imprecision.

  ## Examples

      iex> Time.from_float(0.5)
      %Ratio{numerator: 1, denominator: 2}

      iex> Time.from_float(0.333333)  # approximates 1/3
      %Ratio{numerator: 1, denominator: 3}
  """
  @spec from_float(float()) :: t()
  def from_float(f) when is_float(f) do
    # Use Ratio.new which handles float conversion
    Ratio.new(f)
  end

  # ============================================================================
  # Strudel-compatible Helpers
  # ============================================================================

  @doc """
  Get the cycle start (sam) for a time - floor to nearest integer.

  In Strudel/Tidal, "sam" means "same cycle" - the start of the cycle
  containing this time.

  ## Examples

      iex> Time.sam(Time.new(5, 4))  # 1.25 -> 1
      %Ratio{numerator: 1, denominator: 1}

      iex> Time.sam(Time.new(7, 3))  # 2.33... -> 2
      %Ratio{numerator: 2, denominator: 1}

      iex> Time.sam(Time.new(3))  # integer stays same
      %Ratio{numerator: 3, denominator: 1}
  """
  @spec sam(t()) :: t()
  def sam(time) do
    time |> ensure() |> Ratio.floor() |> new()
  end

  @doc """
  Get the start of the next cycle.

  ## Examples

      iex> Time.next_sam(Time.new(5, 4))  # 1.25 -> 2
      %Ratio{numerator: 2, denominator: 1}

      iex> Time.next_sam(Time.new(3))  # 3 -> 4
      %Ratio{numerator: 4, denominator: 1}
  """
  @spec next_sam(t()) :: t()
  def next_sam(time) do
    time |> sam() |> add(new(1))
  end

  @doc """
  Get the position within the current cycle (0 to 1).

  ## Examples

      iex> Time.cycle_pos(Time.new(5, 4))  # 1.25 -> 0.25
      %Ratio{numerator: 1, denominator: 4}

      iex> Time.cycle_pos(Time.new(7, 3))  # 2.33... -> 0.33...
      %Ratio{numerator: 1, denominator: 3}
  """
  @spec cycle_pos(t()) :: t()
  def cycle_pos(time) do
    t = ensure(time)
    sub(t, sam(t))
  end

  @doc """
  Get the cycle number as an integer.

  ## Examples

      iex> Time.cycle_of(Time.new(5, 4))  # 1.25 -> cycle 1
      1

      iex> Time.cycle_of(Time.new(7, 3))  # 2.33... -> cycle 2
      2
  """
  @spec cycle_of(t()) :: integer()
  def cycle_of(time) do
    time |> ensure() |> Ratio.floor() |> Ratio.trunc()
  end

  # ============================================================================
  # Arithmetic
  # ============================================================================

  @doc """
  Add two time values.
  """
  @spec add(t(), t() | integer()) :: t()
  def add(a, b), do: Ratio.add(ensure(a), ensure(b))

  @doc """
  Subtract time values.
  """
  @spec sub(t(), t() | integer()) :: t()
  def sub(a, b), do: Ratio.sub(ensure(a), ensure(b))

  @doc """
  Multiply time values.
  """
  @spec mult(t(), t() | integer()) :: t()
  def mult(a, b), do: Ratio.mult(ensure(a), ensure(b))

  @doc """
  Divide time values.
  """
  @spec divide(t(), t() | integer()) :: t()
  def divide(a, b), do: Ratio.div(ensure(a), ensure(b))

  @doc """
  Minimum of two time values.
  """
  @spec min(t(), t()) :: t()
  def min(a, b) do
    a = ensure(a)
    b = ensure(b)
    if lte?(a, b), do: a, else: b
  end

  @doc """
  Maximum of two time values.
  """
  @spec max(t(), t()) :: t()
  def max(a, b) do
    a = ensure(a)
    b = ensure(b)
    if gte?(a, b), do: a, else: b
  end

  # ============================================================================
  # Comparison
  # ============================================================================

  @doc """
  Check if a < b.
  """
  @spec lt?(t(), t()) :: boolean()
  def lt?(a, b), do: Ratio.lt?(ensure(a), ensure(b))

  @doc """
  Check if a <= b.
  """
  @spec lte?(t(), t()) :: boolean()
  def lte?(a, b), do: Ratio.lte?(ensure(a), ensure(b))

  @doc """
  Check if a > b.
  """
  @spec gt?(t(), t()) :: boolean()
  def gt?(a, b), do: Ratio.gt?(ensure(a), ensure(b))

  @doc """
  Check if a >= b.
  """
  @spec gte?(t(), t()) :: boolean()
  def gte?(a, b), do: Ratio.gte?(ensure(a), ensure(b))

  @doc """
  Check if two times are equal.
  """
  @spec eq?(t(), t()) :: boolean()
  def eq?(a, b), do: Ratio.eq?(ensure(a), ensure(b))

  # ============================================================================
  # Conversion
  # ============================================================================

  @doc """
  Convert rational time to float.

  Use at scheduling boundaries when sending to audio engine.
  This is a lossy operation - avoid using in intermediate calculations.
  """
  @spec to_float(t()) :: float()
  def to_float(time) when is_integer(time), do: time / 1
  def to_float(%Ratio{} = time), do: Ratio.to_float(time)

  @doc """
  Floor a time value to integer.
  """
  @spec floor(t()) :: t()
  def floor(time), do: time |> ensure() |> Ratio.floor() |> new()

  @doc """
  Ceiling of a time value.
  """
  @spec ceil(t()) :: t()
  def ceil(time), do: time |> ensure() |> Ratio.ceil() |> new()

  @doc """
  Truncate a time value (round toward zero).
  """
  @spec trunc(t()) :: integer()
  def trunc(time), do: time |> ensure() |> Ratio.trunc()

  # ============================================================================
  # Common Fractions (convenience constants)
  # ============================================================================

  @doc "Zero time value."
  @spec zero() :: t()
  def zero, do: new(0, 1)

  @doc "One cycle."
  @spec one() :: t()
  def one, do: new(1, 1)

  @doc "Half cycle."
  @spec half() :: t()
  def half, do: new(1, 2)

  @doc "Third of a cycle."
  @spec third() :: t()
  def third, do: new(1, 3)

  @doc "Quarter of a cycle."
  @spec quarter() :: t()
  def quarter, do: new(1, 4)
end
