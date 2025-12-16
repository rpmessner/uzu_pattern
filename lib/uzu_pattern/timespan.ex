defmodule UzuPattern.TimeSpan do
  @moduledoc """
  A time interval with begin and end points using rational arithmetic.

  TimeSpan is the foundation for Strudel-compatible timing. It represents
  a half-open interval [begin, end) - includes begin, excludes end.

  ## Why TimeSpan?

  Strudel/Tidal use TimeSpan for precise event timing:

  - `whole` timespan: When an event naturally occurs (its full duration)
  - `part` timespan: The portion intersecting a query window

  When you query cycle [0, 1) but an event spans [0.8, 1.2), you get:
  - whole: [0.8, 1.2) - the true event extent
  - part: [0.8, 1.0) - clipped to your query

  ## Rational Precision

  TimeSpan uses rational numbers (Ratio) for exact arithmetic.
  This eliminates floating-point drift in divided patterns:

      # With floats (problematic):
      1/3 + 1/3 + 1/3 = 0.9999... (not exactly 1)

      # With rationals (exact):
      Time.new(1,3) + Time.new(1,3) + Time.new(1,3) = 1/1

  This ensures patterns like `fast(3) |> slow(3)` return exactly to
  their original timing.
  """

  alias UzuPattern.Time

  @type t :: %{begin: Time.t(), end: Time.t()}

  @doc """
  Create a new timespan from begin to end.

  Accepts integers, Ratio structs, or {numerator, denominator} tuples.

  ## Examples

      iex> TimeSpan.new(0, 1)
      %{begin: %Ratio{...}, end: %Ratio{...}}

      iex> TimeSpan.new(Time.new(1, 4), Time.new(1, 2))
      %{begin: %Ratio{numerator: 1, denominator: 4}, ...}
  """
  @spec new(Time.t() | integer() | {integer(), integer()}, Time.t() | integer() | {integer(), integer()}) :: t()
  def new(begin_time, end_time) do
    %{
      begin: Time.ensure(begin_time),
      end: Time.ensure(end_time)
    }
  end

  @doc """
  Duration of the timespan (end - begin).
  """
  @spec duration(t()) :: Time.t()
  def duration(%{begin: b, end: e}), do: Time.sub(e, b)

  @doc """
  Midpoint of the timespan.

  Useful for sampling continuous values - take the value at the middle
  of the query window.
  """
  @spec midpoint(t()) :: Time.t()
  def midpoint(%{begin: b, end: e}) do
    Time.divide(Time.add(b, e), 2)
  end

  @doc """
  Returns the intersection of two timespans, or nil if they don't overlap.

  The intersection is the portion of time that both spans cover.
  """
  @spec intersection(t(), t()) :: t() | nil
  def intersection(%{begin: b1, end: e1}, %{begin: b2, end: e2}) do
    new_begin = Time.max(b1, b2)
    new_end = Time.min(e1, e2)

    if Time.lt?(new_begin, new_end) do
      %{begin: new_begin, end: new_end}
    else
      nil
    end
  end

  @doc """
  Split a timespan at cycle boundaries.

  Cycles are integer boundaries (0, 1, 2, ...). A span crossing a boundary
  gets split into multiple spans, one per cycle.

  This is essential for pattern queries - when you query [0.5, 2.3), you're
  really querying three separate cycle portions:
  - [0.5, 1.0) in cycle 0
  - [1.0, 2.0) in cycle 1
  - [2.0, 2.3) in cycle 2
  """
  @spec span_cycles(t()) :: [t()]
  def span_cycles(%{begin: b, end: e}) do
    if Time.gte?(b, e) do
      []
    else
      do_span_cycles(b, e, [])
    end
  end

  defp do_span_cycles(begin_time, end_time, acc) do
    if Time.gte?(begin_time, end_time) do
      Enum.reverse(acc)
    else
      next = Time.next_sam(begin_time)
      span_end = Time.min(next, end_time)
      span = %{begin: begin_time, end: span_end}
      do_span_cycles(next, end_time, [span | acc])
    end
  end

  @doc """
  Check if a timespan contains a point (half-open: includes begin, excludes end).
  """
  @spec contains?(t(), Time.t()) :: boolean()
  def contains?(%{begin: b, end: e}, point) do
    p = Time.ensure(point)
    Time.gte?(p, b) and Time.lt?(p, e)
  end

  @doc """
  Check if two timespans are equal (same begin and end).
  """
  @spec eq?(t(), t()) :: boolean()
  def eq?(%{begin: b1, end: e1}, %{begin: b2, end: e2}) do
    Time.eq?(b1, b2) and Time.eq?(e1, e2)
  end

  @doc """
  Get the cycle number that contains the begin point.
  """
  @spec cycle_of(t()) :: integer()
  def cycle_of(%{begin: b}) do
    Time.cycle_of(b)
  end

  @doc """
  Shift a timespan by an offset.
  """
  @spec shift(t(), Time.t() | integer()) :: t()
  def shift(%{begin: b, end: e}, offset) do
    o = Time.ensure(offset)
    %{begin: Time.add(b, o), end: Time.add(e, o)}
  end

  @doc """
  Scale a timespan by a factor around the origin.
  """
  @spec scale(t(), Time.t() | integer()) :: t()
  def scale(%{begin: b, end: e}, factor) do
    f = Time.ensure(factor)
    %{begin: Time.mult(b, f), end: Time.mult(e, f)}
  end

  @doc """
  Create a timespan for a whole cycle.

  ## Examples

      iex> TimeSpan.whole_cycle(2)
      %{begin: Time.new(2), end: Time.new(3)}
  """
  @spec whole_cycle(integer()) :: t()
  def whole_cycle(cycle) when is_integer(cycle) do
    new(cycle, cycle + 1)
  end

  # ============================================================================
  # Conversion helpers for scheduler boundary
  # ============================================================================

  @doc """
  Convert a timespan to float values for audio scheduling.

  Use this at the boundary when sending events to Web Audio or SuperCollider.
  """
  @spec to_float(t()) :: %{begin: float(), end: float()}
  def to_float(%{begin: b, end: e}) do
    %{begin: Time.to_float(b), end: Time.to_float(e)}
  end

  @doc """
  Convert a timespan to a float map, normalizing to cycle-relative time.

  This subtracts the cycle offset so times are in [0, 1) range.
  """
  @spec to_float_relative(t(), integer()) :: %{begin: float(), end: float()}
  def to_float_relative(%{begin: b, end: e}, cycle) do
    offset = Time.new(cycle)

    %{
      begin: Time.to_float(Time.sub(b, offset)),
      end: Time.to_float(Time.sub(e, offset))
    }
  end

  @doc """
  Get begin time as float.
  """
  @spec begin_float(t()) :: float()
  def begin_float(%{begin: b}), do: Time.to_float(b)

  @doc """
  Get end time as float.
  """
  @spec end_float(t()) :: float()
  def end_float(%{end: e}), do: Time.to_float(e)

  @doc """
  Get duration as float.
  """
  @spec duration_float(t()) :: float()
  def duration_float(%{begin: b, end: e}) do
    Time.to_float(Time.sub(e, b))
  end
end
