defmodule UzuPattern.TimeSpan do
  @moduledoc """
  A time interval with begin and end points.

  TimeSpan is the foundation for Strudel-compatible timing. It represents
  a half-open interval [begin, end) - includes begin, excludes end.

  ## Why TimeSpan?

  Strudel/Tidal use TimeSpan for precise event timing:

  - `whole` timespan: When an event naturally occurs (its full duration)
  - `part` timespan: The portion intersecting a query window

  When you query cycle [0, 1) but an event spans [0.8, 1.2), you get:
  - whole: [0.8, 1.2) - the true event extent
  - part: [0.8, 1.0) - clipped to your query

  ## Note on Precision

  Strudel uses arbitrary-precision fractions for exact arithmetic.
  We use floats for simplicity. This may accumulate errors over very
  long patterns - we can switch to Ratio/Decimal later if needed.
  """

  @type t :: %{begin: float(), end: float()}

  @doc """
  Create a new timespan from begin to end.
  """
  @spec new(number(), number()) :: t()
  def new(begin_time, end_time) do
    %{begin: begin_time / 1, end: end_time / 1}
  end

  @doc """
  Duration of the timespan (end - begin).
  """
  @spec duration(t()) :: float()
  def duration(%{begin: b, end: e}), do: e - b

  @doc """
  Midpoint of the timespan.

  Useful for sampling continuous values - take the value at the middle
  of the query window.
  """
  @spec midpoint(t()) :: float()
  def midpoint(%{begin: b, end: e}), do: (b + e) / 2

  @doc """
  Returns the intersection of two timespans, or nil if they don't overlap.

  The intersection is the portion of time that both spans cover.
  """
  @spec intersection(t(), t()) :: t() | nil
  def intersection(%{begin: b1, end: e1}, %{begin: b2, end: e2}) do
    new_begin = max(b1, b2)
    new_end = min(e1, e2)

    if new_begin < new_end do
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
  def span_cycles(%{begin: b, end: e}) when b >= e, do: []

  def span_cycles(%{begin: b, end: e}) do
    # Find the next cycle boundary after begin
    next_boundary = Float.floor(b) + 1.0

    if next_boundary >= e do
      # Entire span is within one cycle
      [%{begin: b, end: e}]
    else
      # Split at boundary and recurse
      [%{begin: b, end: next_boundary} | span_cycles(%{begin: next_boundary, end: e})]
    end
  end

  @doc """
  Check if a timespan contains a point (half-open: includes begin, excludes end).
  """
  @spec contains?(t(), number()) :: boolean()
  def contains?(%{begin: b, end: e}, point) do
    point >= b and point < e
  end

  @doc """
  Get the cycle number that contains the begin point.
  """
  @spec cycle_of(t()) :: integer()
  def cycle_of(%{begin: b}) do
    trunc(Float.floor(b))
  end

  @doc """
  Shift a timespan by an offset.
  """
  @spec shift(t(), number()) :: t()
  def shift(%{begin: b, end: e}, offset) do
    %{begin: b + offset, end: e + offset}
  end

  @doc """
  Scale a timespan by a factor around the origin.
  """
  @spec scale(t(), number()) :: t()
  def scale(%{begin: b, end: e}, factor) do
    %{begin: b * factor, end: e * factor}
  end
end
