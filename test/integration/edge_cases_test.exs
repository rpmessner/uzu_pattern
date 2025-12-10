defmodule UzuPattern.Integration.EdgeCasesTest do
  @moduledoc """
  Edge case and boundary condition tests.

  Covers: time boundaries, floating point precision, empty patterns,
  deterministic randomness, complex nesting, and unusual scenarios.
  """

  use ExUnit.Case, async: true

  alias UzuPattern.Pattern

  defp parse(str), do: UzuPattern.parse(str)

  # ============================================================================
  # Time Boundaries
  # ============================================================================

  describe "time boundaries" do
    test "events at exactly 0.0 are included" do
      pattern = parse("bd")
      [event] = Pattern.query(pattern, 0)
      assert event.time == 0.0
    end

    test "all times within cycle bounds [0, 1)" do
      events = parse("bd sd hh cp oh rim") |> Pattern.events()

      Enum.each(events, fn event ->
        assert event.time >= 0.0 and event.time < 1.0
      end)
    end
  end

  # ============================================================================
  # Floating Point Precision
  # ============================================================================

  describe "floating point precision" do
    test "times remain accurate after multiple transformations" do
      pattern =
        parse("bd sd hh cp")
        |> Pattern.fast(3)
        |> Pattern.slow(3)

      events = Pattern.query(pattern, 0)
      times = Enum.map(events, & &1.time)

      assert_in_delta Enum.at(times, 0), 0.0, 0.001
      assert_in_delta Enum.at(times, 1), 0.25, 0.001
      assert_in_delta Enum.at(times, 2), 0.5, 0.001
      assert_in_delta Enum.at(times, 3), 0.75, 0.001
    end

    test "durations sum to approximately 1.0" do
      pattern = parse("bd sd hh cp")
      events = Pattern.query(pattern, 0)
      total_duration = Enum.reduce(events, 0.0, fn e, acc -> acc + e.duration end)
      assert_in_delta total_duration, 1.0, 0.001
    end
  end

  # ============================================================================
  # Empty and Minimal Patterns
  # ============================================================================

  describe "empty and minimal patterns" do
    test "single event pattern" do
      pattern = Pattern.pure("bd")
      events = Pattern.query(pattern, 0)
      assert length(events) == 1
      assert hd(events).sound == "bd"
    end
  end

  # ============================================================================
  # Deterministic Randomness
  # ============================================================================

  describe "deterministic randomness" do
    test "degrade_by produces same results for same cycle" do
      pattern = parse("bd sd hh cp") |> Pattern.degrade_by(0.5)

      events_first = Pattern.query(pattern, 0)
      events_second = Pattern.query(pattern, 0)

      assert events_first == events_second
    end

    test "degrade_by produces different results for different cycles" do
      pattern = parse("bd sd hh cp") |> Pattern.degrade_by(0.5)

      results =
        0..19
        |> Enum.map(fn cycle -> length(Pattern.query(pattern, cycle)) end)
        |> Enum.uniq()

      assert length(results) > 1
    end
  end

  # ============================================================================
  # Complex Nesting
  # ============================================================================

  describe "complex nesting" do
    test "deeply nested slowcat" do
      inner = Pattern.slowcat([Pattern.pure("a"), Pattern.pure("b")])
      middle = Pattern.slowcat([inner, Pattern.pure("c")])
      outer = Pattern.slowcat([middle, Pattern.pure("d")])

      assert hd(Pattern.query(outer, 0)).sound == "a"
      assert hd(Pattern.query(outer, 1)).sound == "d"
    end

    test "stack of stacks" do
      inner1 = Pattern.stack([Pattern.pure("a"), Pattern.pure("b")])
      inner2 = Pattern.stack([Pattern.pure("c"), Pattern.pure("d")])
      outer = Pattern.stack([inner1, inner2])

      events = Pattern.query(outer, 0)
      sounds = Enum.map(events, & &1.sound) |> Enum.sort()
      assert sounds == ["a", "b", "c", "d"]
    end
  end

  # ============================================================================
  # Combinator Interactions
  # ============================================================================

  describe "combinator interactions" do
    test "every with stack" do
      pattern =
        Pattern.stack([parse("bd"), parse("hh")])
        |> Pattern.every(2, &Pattern.fast(&1, 2))

      events_0 = Pattern.query(pattern, 0)
      events_1 = Pattern.query(pattern, 1)

      assert length(events_0) > length(events_1)
    end

    test "jux with rev" do
      pattern = parse("bd sd hh") |> Pattern.jux(&Pattern.rev/1)
      events = Pattern.query(pattern, 0)

      assert length(events) == 6

      pans = Enum.map(events, fn e -> e.params[:pan] end)
      assert -1.0 in pans
      assert 1.0 in pans
    end
  end
end
