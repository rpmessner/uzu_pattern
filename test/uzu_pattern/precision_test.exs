defmodule UzuPattern.PrecisionTest do
  @moduledoc """
  Tests verifying that rational time arithmetic provides exact precision.

  These tests verify the core motivation for the Ratio migration:
  eliminating floating-point drift in pattern timing.
  """

  use ExUnit.Case, async: true

  alias UzuPattern.Time
  alias UzuPattern.TimeSpan
  alias UzuPattern.Pattern

  describe "rational time precision" do
    test "1/3 + 1/3 + 1/3 equals exactly 1" do
      third = Time.new(1, 3)
      result = third |> Time.add(third) |> Time.add(third)

      assert Time.eq?(result, Time.one())
    end

    test "1/7 * 7 equals exactly 1" do
      seventh = Time.new(1, 7)
      result = Time.mult(seventh, 7)

      assert Time.eq?(result, Time.one())
    end

    test "1/11 + 1/11 + ... (11 times) equals exactly 1" do
      eleventh = Time.new(1, 11)
      result = Enum.reduce(1..11, Time.zero(), fn _i, acc -> Time.add(acc, eleventh) end)

      assert Time.eq?(result, Time.one())
    end

    test "fast(3) |> slow(3) returns events at exact original positions" do
      # Create a simple pattern with one event
      pattern = Pattern.pure("bd")

      # Speed up by 3, then slow down by 3 - should return to original timing
      transformed = pattern |> Pattern.fast(3) |> Pattern.slow(3)

      # Get events from both patterns
      original_haps = Pattern.query(pattern, 0)
      transformed_haps = Pattern.query(transformed, 0)

      assert length(original_haps) == length(transformed_haps)

      # Event positions should be exactly equal
      [orig] = original_haps
      [trans] = transformed_haps

      assert Time.eq?(orig.part.begin, trans.part.begin)
      assert Time.eq?(orig.part.end, trans.part.end)
    end

    test "fast(7) produces events at exact 1/7 intervals" do
      pattern = Pattern.pure("bd") |> Pattern.fast(7)
      haps = Pattern.query(pattern, 0)

      assert length(haps) == 7

      # Each event should be at exact 1/7 intervals
      expected_times = Enum.map(0..6, fn i -> Time.new(i, 7) end)

      Enum.zip(haps, expected_times)
      |> Enum.each(fn {hap, expected} ->
        assert Time.eq?(hap.part.begin, expected),
               "Expected #{inspect(expected)}, got #{inspect(hap.part.begin)}"
      end)
    end

    test "fastcat of 3 patterns produces events at exact 1/3 intervals" do
      pattern =
        Pattern.fastcat([
          Pattern.pure("a"),
          Pattern.pure("b"),
          Pattern.pure("c")
        ])

      haps = Pattern.query(pattern, 0)

      assert length(haps) == 3

      # Check exact positions
      assert Time.eq?(Enum.at(haps, 0).part.begin, Time.new(0, 1))
      assert Time.eq?(Enum.at(haps, 1).part.begin, Time.new(1, 3))
      assert Time.eq?(Enum.at(haps, 2).part.begin, Time.new(2, 3))

      # Check exact durations
      Enum.each(haps, fn hap ->
        dur = TimeSpan.duration(hap.part)
        assert Time.eq?(dur, Time.new(1, 3))
      end)
    end

    test "nested fast operations maintain precision" do
      # fast(3) inside fast(5) should produce events at 1/15 intervals
      pattern = Pattern.pure("bd") |> Pattern.fast(3) |> Pattern.fast(5)

      haps = Pattern.query(pattern, 0)

      assert length(haps) == 15

      # First event at 0, last at 14/15
      first = hd(haps)
      last = List.last(haps)

      assert Time.eq?(first.part.begin, Time.zero())
      assert Time.eq?(last.part.begin, Time.new(14, 15))
    end
  end

  describe "cycle boundary precision" do
    test "span_cycles splits exactly at integer boundaries" do
      span = TimeSpan.new(Time.new(1, 4), Time.new(9, 4))
      cycles = TimeSpan.span_cycles(span)

      assert length(cycles) == 3

      # First span: [1/4, 1)
      [c1, c2, c3] = cycles
      assert Time.eq?(c1.begin, Time.new(1, 4))
      assert Time.eq?(c1.end, Time.one())

      # Second span: [1, 2)
      assert Time.eq?(c2.begin, Time.one())
      assert Time.eq?(c2.end, Time.new(2))

      # Third span: [2, 9/4)
      assert Time.eq?(c3.begin, Time.new(2))
      assert Time.eq?(c3.end, Time.new(9, 4))
    end

    test "sam (cycle start) is exact" do
      # 5/4 should have sam = 1
      assert Time.eq?(Time.sam(Time.new(5, 4)), Time.one())

      # 7/3 should have sam = 2
      assert Time.eq?(Time.sam(Time.new(7, 3)), Time.new(2))

      # 10/10 = 1 should have sam = 1
      assert Time.eq?(Time.sam(Time.new(10, 10)), Time.one())
    end

    test "cycle_pos is exact fractional part" do
      # 5/4 has cycle_pos = 1/4
      assert Time.eq?(Time.cycle_pos(Time.new(5, 4)), Time.new(1, 4))

      # 7/3 has cycle_pos = 1/3
      assert Time.eq?(Time.cycle_pos(Time.new(7, 3)), Time.new(1, 3))
    end
  end

  describe "float conversion at boundary" do
    test "to_float converts for audio scheduling" do
      span = TimeSpan.new(Time.new(1, 4), Time.new(3, 4))
      float_span = TimeSpan.to_float(span)

      assert float_span.begin == 0.25
      assert float_span.end == 0.75
    end

    test "float helpers work on timespans" do
      span = TimeSpan.new(Time.new(1, 3), Time.new(2, 3))

      # Should be close to expected values
      assert_in_delta TimeSpan.begin_float(span), 0.333333, 0.0001
      assert_in_delta TimeSpan.end_float(span), 0.666667, 0.0001
      assert_in_delta TimeSpan.duration_float(span), 0.333333, 0.0001
    end
  end
end
