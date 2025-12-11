defmodule UzuPattern.TimeSpanTest do
  use ExUnit.Case, async: true

  alias UzuPattern.TimeSpan

  describe "new/2" do
    test "creates timespan from begin and end" do
      ts = TimeSpan.new(0.0, 1.0)
      assert ts.begin == 0.0
      assert ts.end == 1.0
    end

    test "accepts integers and converts to floats" do
      ts = TimeSpan.new(0, 1)
      assert ts.begin == 0.0
      assert ts.end == 1.0
    end
  end

  describe "duration/1" do
    test "calculates duration" do
      assert TimeSpan.duration(%{begin: 0.0, end: 1.0}) == 1.0
      assert TimeSpan.duration(%{begin: 0.25, end: 0.75}) == 0.5
      assert TimeSpan.duration(%{begin: 0.0, end: 0.0}) == 0.0
    end
  end

  describe "midpoint/1" do
    test "calculates midpoint" do
      assert TimeSpan.midpoint(%{begin: 0.0, end: 1.0}) == 0.5
      assert_in_delta TimeSpan.midpoint(%{begin: 0.2, end: 0.4}), 0.3, 0.0001
    end
  end

  describe "intersection/2" do
    test "returns intersection of overlapping spans" do
      a = %{begin: 0.0, end: 0.5}
      b = %{begin: 0.3, end: 0.8}
      assert TimeSpan.intersection(a, b) == %{begin: 0.3, end: 0.5}
    end

    test "returns smaller span when one contains the other" do
      outer = %{begin: 0.0, end: 1.0}
      inner = %{begin: 0.2, end: 0.4}
      assert TimeSpan.intersection(outer, inner) == %{begin: 0.2, end: 0.4}
      assert TimeSpan.intersection(inner, outer) == %{begin: 0.2, end: 0.4}
    end

    test "returns nil for non-overlapping spans" do
      a = %{begin: 0.0, end: 0.3}
      b = %{begin: 0.5, end: 0.8}
      assert TimeSpan.intersection(a, b) == nil
    end

    test "returns nil for adjacent spans (half-open intervals)" do
      a = %{begin: 0.0, end: 0.5}
      b = %{begin: 0.5, end: 1.0}
      assert TimeSpan.intersection(a, b) == nil
    end

    test "handles identical spans" do
      ts = %{begin: 0.25, end: 0.75}
      assert TimeSpan.intersection(ts, ts) == ts
    end
  end

  describe "span_cycles/1" do
    test "returns single span if within one cycle" do
      ts = %{begin: 0.2, end: 0.8}
      assert TimeSpan.span_cycles(ts) == [%{begin: 0.2, end: 0.8}]
    end

    test "splits span crossing one boundary" do
      ts = %{begin: 0.5, end: 1.5}

      assert TimeSpan.span_cycles(ts) == [
               %{begin: 0.5, end: 1.0},
               %{begin: 1.0, end: 1.5}
             ]
    end

    test "splits span crossing multiple boundaries" do
      ts = %{begin: 0.5, end: 2.3}

      assert TimeSpan.span_cycles(ts) == [
               %{begin: 0.5, end: 1.0},
               %{begin: 1.0, end: 2.0},
               %{begin: 2.0, end: 2.3}
             ]
    end

    test "handles exact cycle boundaries" do
      ts = %{begin: 0.0, end: 1.0}
      assert TimeSpan.span_cycles(ts) == [%{begin: 0.0, end: 1.0}]
    end

    test "handles multiple complete cycles" do
      ts = %{begin: 0.0, end: 3.0}

      assert TimeSpan.span_cycles(ts) == [
               %{begin: 0.0, end: 1.0},
               %{begin: 1.0, end: 2.0},
               %{begin: 2.0, end: 3.0}
             ]
    end

    test "returns empty list for invalid span" do
      assert TimeSpan.span_cycles(%{begin: 1.0, end: 0.0}) == []
      assert TimeSpan.span_cycles(%{begin: 0.5, end: 0.5}) == []
    end

    test "handles negative cycles" do
      ts = %{begin: -0.5, end: 0.5}

      assert TimeSpan.span_cycles(ts) == [
               %{begin: -0.5, end: 0.0},
               %{begin: 0.0, end: 0.5}
             ]
    end
  end

  describe "contains?/2" do
    test "returns true for points inside span" do
      ts = %{begin: 0.0, end: 1.0}
      assert TimeSpan.contains?(ts, 0.0)
      assert TimeSpan.contains?(ts, 0.5)
      assert TimeSpan.contains?(ts, 0.999)
    end

    test "returns false for end point (half-open interval)" do
      ts = %{begin: 0.0, end: 1.0}
      refute TimeSpan.contains?(ts, 1.0)
    end

    test "returns false for points outside span" do
      ts = %{begin: 0.0, end: 1.0}
      refute TimeSpan.contains?(ts, -0.1)
      refute TimeSpan.contains?(ts, 1.1)
    end
  end

  describe "cycle_of/1" do
    test "returns cycle containing begin point" do
      assert TimeSpan.cycle_of(%{begin: 0.5, end: 1.0}) == 0
      assert TimeSpan.cycle_of(%{begin: 1.0, end: 1.5}) == 1
      assert TimeSpan.cycle_of(%{begin: 1.5, end: 2.0}) == 1
      assert TimeSpan.cycle_of(%{begin: 3.0, end: 4.0}) == 3
    end

    test "handles negative cycles" do
      assert TimeSpan.cycle_of(%{begin: -0.5, end: 0.0}) == -1
      assert TimeSpan.cycle_of(%{begin: -1.5, end: -1.0}) == -2
    end
  end

  describe "shift/2" do
    test "shifts timespan by offset" do
      ts = %{begin: 0.0, end: 0.5}
      assert TimeSpan.shift(ts, 1.0) == %{begin: 1.0, end: 1.5}
      assert TimeSpan.shift(ts, -0.25) == %{begin: -0.25, end: 0.25}
    end
  end

  describe "scale/2" do
    test "scales timespan by factor" do
      ts = %{begin: 0.0, end: 1.0}
      assert TimeSpan.scale(ts, 0.5) == %{begin: 0.0, end: 0.5}
      assert TimeSpan.scale(ts, 2.0) == %{begin: 0.0, end: 2.0}
    end

    test "scales non-zero origin spans" do
      ts = %{begin: 0.5, end: 1.0}
      assert TimeSpan.scale(ts, 2.0) == %{begin: 1.0, end: 2.0}
    end
  end
end
