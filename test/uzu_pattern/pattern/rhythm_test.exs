defmodule UzuPattern.Pattern.RhythmTest do
  @moduledoc """
  Tests for rhythm generation functions.

  Functions: euclid, euclid_rot, swing, swing_by
  """

  use ExUnit.Case, async: true

  alias UzuPattern.Hap
  alias UzuPattern.Pattern

  defp parse(str), do: UzuPattern.parse(str)

  # Strudel-style helpers
  defp sounds(haps), do: Enum.map(haps, &Hap.sound/1)
  defp times(haps), do: Enum.map(haps, & &1.part.begin)

  describe "euclid/3" do
    test "generates Euclidean rhythm" do
      pattern = parse("bd sd hh cp bd sd hh cp") |> Pattern.euclid(3, 8)
      haps = Pattern.events(pattern)

      assert length(haps) == 3
    end

    test "euclid(5, 8) generates correct pattern" do
      pattern = parse("a b c d e f g h") |> Pattern.euclid(5, 8)
      haps = Pattern.events(pattern)

      assert length(haps) == 5
    end

    test "euclid with events matching step count" do
      pattern = parse("a b c d e f g h") |> Pattern.euclid(3, 8)
      haps = Pattern.events(pattern)

      assert length(haps) == 3
      assert Hap.sound(Enum.at(haps, 0)) == "a"
      assert Hap.sound(Enum.at(haps, 1)) == "d"
      assert Hap.sound(Enum.at(haps, 2)) == "g"
    end

    test "euclid(0, n) produces no events" do
      pattern = Pattern.pure("bd") |> Pattern.euclid(0, 8)
      haps = Pattern.query(pattern, 0)
      assert haps == []
    end

    test "euclid(n, n) keeps all events" do
      pattern = Pattern.pure("bd") |> Pattern.euclid(4, 4)
      haps = Pattern.query(pattern, 0)
      assert length(haps) == 1
    end

    test "euclid(1, 1) produces single event" do
      pattern = Pattern.pure("bd") |> Pattern.euclid(1, 1)
      haps = Pattern.query(pattern, 0)
      assert length(haps) == 1
    end
  end

  describe "euclid_rot/4" do
    test "rotates Euclidean rhythm" do
      pattern = parse("bd sd hh cp bd sd hh cp") |> Pattern.euclid_rot(3, 8, 2)
      haps = Pattern.events(pattern)

      assert length(haps) == 3
    end

    test "rotation changes which events are kept" do
      p1 = parse("a b c d e f g h") |> Pattern.euclid(3, 8)
      p2 = parse("a b c d e f g h") |> Pattern.euclid_rot(3, 8, 1)

      haps1 = Pattern.events(p1)
      haps2 = Pattern.events(p2)

      assert length(haps1) == length(haps2)

      sounds1 = sounds(haps1)
      sounds2 = sounds(haps2)
      assert sounds1 != sounds2 or sounds1 == []
    end

    test "euclid_rot offset wraps around" do
      pattern1 = Pattern.pure("bd") |> Pattern.euclid_rot(3, 8, 0)
      pattern2 = Pattern.pure("bd") |> Pattern.euclid_rot(3, 8, 8)

      haps1 = Pattern.query(pattern1, 0)
      haps2 = Pattern.query(pattern2, 0)

      times1 = times(haps1)
      times2 = times(haps2)

      assert times1 == times2
    end
  end

  describe "swing/2" do
    test "applies swing timing" do
      pattern = parse("hh hh hh hh hh hh hh hh") |> Pattern.swing(4)
      haps = Pattern.events(pattern)

      assert length(haps) == 8
    end

    test "modifies event timing" do
      original = parse("hh hh hh hh")
      swung = parse("hh hh hh hh") |> Pattern.swing(2)

      original_times = times(Pattern.events(original))
      swung_times = times(Pattern.events(swung))

      assert original_times != swung_times
    end
  end

  describe "swing_by/3" do
    test "applies parameterized swing" do
      pattern = parse("hh hh hh hh hh hh hh hh") |> Pattern.swing_by(0.5, 4)
      haps = Pattern.events(pattern)

      assert length(haps) == 8
    end

    test "swing_by(0, n) does not change timing" do
      original = parse("hh hh hh hh")
      swung = parse("hh hh hh hh") |> Pattern.swing_by(0.0, 2)

      original_times = times(Pattern.events(original))
      swung_times = times(Pattern.events(swung))

      assert original_times == swung_times
    end

    test "different swing amounts create different timings" do
      p1 = parse("hh hh hh hh") |> Pattern.swing_by(0.25, 2)
      p2 = parse("hh hh hh hh") |> Pattern.swing_by(0.5, 2)

      times1 = times(Pattern.events(p1))
      times2 = times(Pattern.events(p2))

      assert times1 != times2
    end
  end
end
