defmodule UzuPattern.TimeSpanTest do
  use ExUnit.Case, async: true

  alias UzuPattern.TimeSpan
  alias UzuPattern.Time

  describe "new/2" do
    test "creates timespan from begin and end" do
      ts = TimeSpan.new(0, 1)
      assert Time.eq?(ts.begin, Time.zero())
      assert Time.eq?(ts.end, Time.one())
    end

    test "accepts floats and converts to rationals" do
      ts = TimeSpan.new(0.5, 1.0)
      assert_in_delta TimeSpan.begin_float(ts), 0.5, 0.0001
      assert_in_delta TimeSpan.end_float(ts), 1.0, 0.0001
    end

    test "accepts integers" do
      ts = TimeSpan.new(0, 1)
      assert Time.eq?(ts.begin, Time.new(0))
      assert Time.eq?(ts.end, Time.new(1))
    end
  end

  describe "duration/1" do
    test "calculates duration" do
      assert Time.eq?(TimeSpan.duration(TimeSpan.new(0, 1)), Time.one())
      assert Time.eq?(TimeSpan.duration(TimeSpan.new({1, 4}, {3, 4})), Time.half())
      assert Time.eq?(TimeSpan.duration(TimeSpan.new(0, 0)), Time.zero())
    end

    test "duration_float works" do
      assert_in_delta TimeSpan.duration_float(TimeSpan.new(0, 1)), 1.0, 0.0001
      assert_in_delta TimeSpan.duration_float(TimeSpan.new({1, 4}, {3, 4})), 0.5, 0.0001
    end
  end

  describe "midpoint/1" do
    test "calculates midpoint" do
      assert Time.eq?(TimeSpan.midpoint(TimeSpan.new(0, 1)), Time.half())
      mid = TimeSpan.midpoint(TimeSpan.new({1, 5}, {2, 5}))
      assert Time.eq?(mid, Time.new(3, 10))
    end
  end

  describe "intersection/2" do
    test "returns intersection of overlapping spans" do
      a = TimeSpan.new(0, {1, 2})
      b = TimeSpan.new({3, 10}, {4, 5})
      result = TimeSpan.intersection(a, b)
      assert Time.eq?(result.begin, Time.new(3, 10))
      assert Time.eq?(result.end, Time.half())
    end

    test "returns smaller span when one contains the other" do
      outer = TimeSpan.new(0, 1)
      inner = TimeSpan.new({1, 5}, {2, 5})
      result = TimeSpan.intersection(outer, inner)
      assert Time.eq?(result.begin, Time.new(1, 5))
      assert Time.eq?(result.end, Time.new(2, 5))
    end

    test "returns nil for non-overlapping spans" do
      a = TimeSpan.new(0, {3, 10})
      b = TimeSpan.new({1, 2}, {4, 5})
      assert TimeSpan.intersection(a, b) == nil
    end

    test "returns nil for adjacent spans (half-open intervals)" do
      a = TimeSpan.new(0, {1, 2})
      b = TimeSpan.new({1, 2}, 1)
      assert TimeSpan.intersection(a, b) == nil
    end

    test "handles identical spans" do
      ts = TimeSpan.new({1, 4}, {3, 4})
      result = TimeSpan.intersection(ts, ts)
      assert Time.eq?(result.begin, Time.new(1, 4))
      assert Time.eq?(result.end, Time.new(3, 4))
    end
  end

  describe "span_cycles/1" do
    test "returns single span if within one cycle" do
      ts = TimeSpan.new({1, 5}, {4, 5})
      [result] = TimeSpan.span_cycles(ts)
      assert Time.eq?(result.begin, Time.new(1, 5))
      assert Time.eq?(result.end, Time.new(4, 5))
    end

    test "splits span crossing one boundary" do
      ts = TimeSpan.new({1, 2}, {3, 2})
      [c1, c2] = TimeSpan.span_cycles(ts)

      assert Time.eq?(c1.begin, Time.half())
      assert Time.eq?(c1.end, Time.one())
      assert Time.eq?(c2.begin, Time.one())
      assert Time.eq?(c2.end, Time.new(3, 2))
    end

    test "splits span crossing multiple boundaries" do
      ts = TimeSpan.new({1, 2}, {23, 10})
      cycles = TimeSpan.span_cycles(ts)

      assert length(cycles) == 3
      [c1, c2, c3] = cycles

      assert Time.eq?(c1.begin, Time.half())
      assert Time.eq?(c1.end, Time.one())
      assert Time.eq?(c2.begin, Time.one())
      assert Time.eq?(c2.end, Time.new(2))
      assert Time.eq?(c3.begin, Time.new(2))
      assert Time.eq?(c3.end, Time.new(23, 10))
    end

    test "handles exact cycle boundaries" do
      ts = TimeSpan.new(0, 1)
      [result] = TimeSpan.span_cycles(ts)
      assert Time.eq?(result.begin, Time.zero())
      assert Time.eq?(result.end, Time.one())
    end

    test "handles multiple complete cycles" do
      ts = TimeSpan.new(0, 3)
      cycles = TimeSpan.span_cycles(ts)

      assert length(cycles) == 3
      [c1, c2, c3] = cycles

      assert Time.eq?(c1.begin, Time.zero())
      assert Time.eq?(c1.end, Time.one())
      assert Time.eq?(c2.begin, Time.one())
      assert Time.eq?(c2.end, Time.new(2))
      assert Time.eq?(c3.begin, Time.new(2))
      assert Time.eq?(c3.end, Time.new(3))
    end

    test "returns empty list for invalid span" do
      assert TimeSpan.span_cycles(TimeSpan.new(1, 0)) == []
      assert TimeSpan.span_cycles(TimeSpan.new({1, 2}, {1, 2})) == []
    end

    test "handles negative cycles" do
      ts = TimeSpan.new({-1, 2}, {1, 2})
      [c1, c2] = TimeSpan.span_cycles(ts)

      assert Time.eq?(c1.begin, Time.new(-1, 2))
      assert Time.eq?(c1.end, Time.zero())
      assert Time.eq?(c2.begin, Time.zero())
      assert Time.eq?(c2.end, Time.half())
    end
  end

  describe "contains?/2" do
    test "returns true for points inside span" do
      ts = TimeSpan.new(0, 1)
      assert TimeSpan.contains?(ts, Time.zero())
      assert TimeSpan.contains?(ts, Time.half())
      assert TimeSpan.contains?(ts, Time.new(99, 100))
    end

    test "returns false for end point (half-open interval)" do
      ts = TimeSpan.new(0, 1)
      refute TimeSpan.contains?(ts, Time.one())
    end

    test "returns false for points outside span" do
      ts = TimeSpan.new(0, 1)
      refute TimeSpan.contains?(ts, Time.new(-1, 10))
      refute TimeSpan.contains?(ts, Time.new(11, 10))
    end
  end

  describe "cycle_of/1" do
    test "returns cycle containing begin point" do
      assert TimeSpan.cycle_of(TimeSpan.new({1, 2}, 1)) == 0
      assert TimeSpan.cycle_of(TimeSpan.new(1, {3, 2})) == 1
      assert TimeSpan.cycle_of(TimeSpan.new({3, 2}, 2)) == 1
      assert TimeSpan.cycle_of(TimeSpan.new(3, 4)) == 3
    end

    test "handles negative cycles" do
      assert TimeSpan.cycle_of(TimeSpan.new({-1, 2}, 0)) == -1
      assert TimeSpan.cycle_of(TimeSpan.new({-3, 2}, -1)) == -2
    end
  end

  describe "shift/2" do
    test "shifts timespan by offset" do
      ts = TimeSpan.new(0, {1, 2})
      shifted = TimeSpan.shift(ts, 1)
      assert Time.eq?(shifted.begin, Time.one())
      assert Time.eq?(shifted.end, Time.new(3, 2))
    end

    test "shifts by negative offset" do
      ts = TimeSpan.new(0, {1, 2})
      shifted = TimeSpan.shift(ts, Time.new(-1, 4))
      assert Time.eq?(shifted.begin, Time.new(-1, 4))
      assert Time.eq?(shifted.end, Time.new(1, 4))
    end
  end

  describe "scale/2" do
    test "scales timespan by factor" do
      ts = TimeSpan.new(0, 1)
      scaled = TimeSpan.scale(ts, {1, 2})
      assert Time.eq?(scaled.begin, Time.zero())
      assert Time.eq?(scaled.end, Time.half())
    end

    test "scales by integer factor" do
      ts = TimeSpan.new(0, 1)
      scaled = TimeSpan.scale(ts, 2)
      assert Time.eq?(scaled.begin, Time.zero())
      assert Time.eq?(scaled.end, Time.new(2))
    end

    test "scales non-zero origin spans" do
      ts = TimeSpan.new({1, 2}, 1)
      scaled = TimeSpan.scale(ts, 2)
      assert Time.eq?(scaled.begin, Time.one())
      assert Time.eq?(scaled.end, Time.new(2))
    end
  end

  describe "float conversion" do
    test "to_float converts entire timespan" do
      ts = TimeSpan.new({1, 4}, {3, 4})
      float_ts = TimeSpan.to_float(ts)
      assert float_ts.begin == 0.25
      assert float_ts.end == 0.75
    end

    test "begin_float and end_float work" do
      ts = TimeSpan.new({1, 3}, {2, 3})
      assert_in_delta TimeSpan.begin_float(ts), 0.3333, 0.001
      assert_in_delta TimeSpan.end_float(ts), 0.6667, 0.001
    end
  end
end
