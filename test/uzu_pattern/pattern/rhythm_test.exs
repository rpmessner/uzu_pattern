defmodule UzuPattern.Pattern.RhythmTest do
  @moduledoc """
  Tests for rhythm generation functions.

  Functions: euclid, euclid_rot, swing, swing_by
  """

  use ExUnit.Case, async: true

  alias UzuPattern.Pattern

  defp parse(str), do: UzuPattern.parse(str)

  describe "euclid/3" do
    test "generates Euclidean rhythm" do
      pattern = parse("bd sd hh cp bd sd hh cp") |> Pattern.euclid(3, 8)
      events = Pattern.events(pattern)

      assert length(events) == 3
    end

    test "euclid(5, 8) generates correct pattern" do
      pattern = parse("a b c d e f g h") |> Pattern.euclid(5, 8)
      events = Pattern.events(pattern)

      assert length(events) == 5
    end

    test "euclid with events matching step count" do
      pattern = parse("a b c d e f g h") |> Pattern.euclid(3, 8)
      events = Pattern.events(pattern)

      assert length(events) == 3
      assert Enum.at(events, 0).sound == "a"
      assert Enum.at(events, 1).sound == "d"
      assert Enum.at(events, 2).sound == "g"
    end

    test "euclid(0, n) produces no events" do
      pattern = Pattern.pure("bd") |> Pattern.euclid(0, 8)
      events = Pattern.query(pattern, 0)
      assert events == []
    end

    test "euclid(n, n) keeps all events" do
      pattern = Pattern.pure("bd") |> Pattern.euclid(4, 4)
      events = Pattern.query(pattern, 0)
      assert length(events) == 1
    end

    test "euclid(1, 1) produces single event" do
      pattern = Pattern.pure("bd") |> Pattern.euclid(1, 1)
      events = Pattern.query(pattern, 0)
      assert length(events) == 1
    end
  end

  describe "euclid_rot/4" do
    test "rotates Euclidean rhythm" do
      pattern = parse("bd sd hh cp bd sd hh cp") |> Pattern.euclid_rot(3, 8, 2)
      events = Pattern.events(pattern)

      assert length(events) == 3
    end

    test "rotation changes which events are kept" do
      p1 = parse("a b c d e f g h") |> Pattern.euclid(3, 8)
      p2 = parse("a b c d e f g h") |> Pattern.euclid_rot(3, 8, 1)

      events1 = Pattern.events(p1)
      events2 = Pattern.events(p2)

      assert length(events1) == length(events2)

      sounds1 = Enum.map(events1, fn e -> e.sound end)
      sounds2 = Enum.map(events2, fn e -> e.sound end)
      assert sounds1 != sounds2 or sounds1 == []
    end

    test "euclid_rot offset wraps around" do
      pattern1 = Pattern.pure("bd") |> Pattern.euclid_rot(3, 8, 0)
      pattern2 = Pattern.pure("bd") |> Pattern.euclid_rot(3, 8, 8)

      events1 = Pattern.query(pattern1, 0)
      events2 = Pattern.query(pattern2, 0)

      times1 = Enum.map(events1, & &1.time)
      times2 = Enum.map(events2, & &1.time)

      assert times1 == times2
    end
  end

  describe "swing/2" do
    test "applies swing timing" do
      pattern = parse("hh hh hh hh hh hh hh hh") |> Pattern.swing(4)
      events = Pattern.events(pattern)

      assert length(events) == 8
    end

    test "modifies event timing" do
      original = parse("hh hh hh hh")
      swung = parse("hh hh hh hh") |> Pattern.swing(2)

      original_times = Pattern.events(original) |> Enum.map(fn e -> e.time end)
      swung_times = Pattern.events(swung) |> Enum.map(fn e -> e.time end)

      assert original_times != swung_times
    end
  end

  describe "swing_by/3" do
    test "applies parameterized swing" do
      pattern = parse("hh hh hh hh hh hh hh hh") |> Pattern.swing_by(0.5, 4)
      events = Pattern.events(pattern)

      assert length(events) == 8
    end

    test "swing_by(0, n) does not change timing" do
      original = parse("hh hh hh hh")
      swung = parse("hh hh hh hh") |> Pattern.swing_by(0.0, 2)

      original_times = Pattern.events(original) |> Enum.map(fn e -> e.time end)
      swung_times = Pattern.events(swung) |> Enum.map(fn e -> e.time end)

      assert original_times == swung_times
    end

    test "different swing amounts create different timings" do
      p1 = parse("hh hh hh hh") |> Pattern.swing_by(0.25, 2)
      p2 = parse("hh hh hh hh") |> Pattern.swing_by(0.5, 2)

      times1 = Pattern.events(p1) |> Enum.map(fn e -> e.time end)
      times2 = Pattern.events(p2) |> Enum.map(fn e -> e.time end)

      assert times1 != times2
    end
  end
end
