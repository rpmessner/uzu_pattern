defmodule UzuPattern.Integration.EdgeCasesTest do
  @moduledoc """
  Edge case and boundary condition tests.

  Covers: time boundaries, floating point precision, empty patterns,
  deterministic randomness, complex nesting, and unusual scenarios.

  Follows Strudel test conventions - focus on behavior (values, timing).
  """

  use ExUnit.Case, async: true

  alias UzuPattern.Hap
  alias UzuPattern.Pattern

  defp parse(str), do: UzuPattern.parse(str)

  # Strudel-style helpers
  defp sounds(haps), do: Enum.map(haps, &Hap.sound/1)
  defp times(haps), do: Enum.map(haps, & &1.part.begin)
  defp durations(haps), do: Enum.map(haps, &(&1.part.end - &1.part.begin))

  # ============================================================================
  # Time Boundaries
  # ============================================================================

  describe "time boundaries" do
    test "events at exactly 0.0 are included" do
      pattern = parse("bd")
      [hap] = Pattern.query(pattern, 0)
      assert hap.part.begin == 0.0
    end

    test "all times within cycle bounds [0, 1)" do
      haps = parse("bd sd hh cp oh rim") |> Pattern.events()

      Enum.each(haps, fn hap ->
        assert hap.part.begin >= 0.0 and hap.part.begin < 1.0
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

      haps = Pattern.query(pattern, 0)
      hap_times = times(haps)

      assert_in_delta Enum.at(hap_times, 0), 0.0, 0.001
      assert_in_delta Enum.at(hap_times, 1), 0.25, 0.001
      assert_in_delta Enum.at(hap_times, 2), 0.5, 0.001
      assert_in_delta Enum.at(hap_times, 3), 0.75, 0.001
    end

    test "durations sum to approximately 1.0" do
      pattern = parse("bd sd hh cp")
      haps = Pattern.query(pattern, 0)
      total_duration = Enum.reduce(durations(haps), 0.0, &(&1 + &2))
      assert_in_delta total_duration, 1.0, 0.001
    end
  end

  # ============================================================================
  # Empty and Minimal Patterns
  # ============================================================================

  describe "empty and minimal patterns" do
    test "single event pattern" do
      pattern = Pattern.pure("bd")
      haps = Pattern.query(pattern, 0)
      assert length(haps) == 1
      assert Hap.sound(hd(haps)) == "bd"
    end
  end

  # ============================================================================
  # Deterministic Randomness
  # ============================================================================

  describe "deterministic randomness" do
    test "degrade_by produces same results for same cycle" do
      pattern = parse("bd sd hh cp") |> Pattern.degrade_by(0.5)

      haps_first = Pattern.query(pattern, 0)
      haps_second = Pattern.query(pattern, 0)

      assert haps_first == haps_second
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

      assert Hap.sound(hd(Pattern.query(outer, 0))) == "a"
      assert Hap.sound(hd(Pattern.query(outer, 1))) == "d"
    end

    test "stack of stacks" do
      inner1 = Pattern.stack([Pattern.pure("a"), Pattern.pure("b")])
      inner2 = Pattern.stack([Pattern.pure("c"), Pattern.pure("d")])
      outer = Pattern.stack([inner1, inner2])

      haps = Pattern.query(outer, 0)
      assert sounds(haps) |> Enum.sort() == ["a", "b", "c", "d"]
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

      haps_0 = Pattern.query(pattern, 0)
      haps_1 = Pattern.query(pattern, 1)

      assert length(haps_0) > length(haps_1)
    end

    test "jux with rev" do
      pattern = parse("bd sd hh") |> Pattern.jux(&Pattern.rev/1)
      haps = Pattern.query(pattern, 0)

      assert length(haps) == 6

      pans = Enum.map(haps, & &1.value[:pan])
      assert -1.0 in pans
      assert 1.0 in pans
    end
  end
end
