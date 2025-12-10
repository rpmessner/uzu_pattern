defmodule UzuPattern.Integration.ParseTest do
  @moduledoc """
  Integration tests for UzuPattern.parse/1.

  Tests end-to-end behavior from mini-notation string to events.
  Focus: realistic patterns, feature combinations, edge cases.
  """

  use ExUnit.Case, async: true

  alias UzuPattern.Event

  # Helper: parse string and get events for cycle 0
  defp parse_events(pattern_string) do
    pattern_string
    |> UzuPattern.parse()
    |> UzuPattern.query(0)
  end

  # Helper: assert event positions map back to original pattern substrings
  defp assert_positions_match(pattern, events) do
    Enum.each(events, fn event ->
      substring = String.slice(pattern, event.source_start, event.source_end - event.source_start)

      assert String.starts_with?(substring, event.sound) or substring == event.sound,
             "Position mismatch: expected '#{event.sound}' at [#{event.source_start}:#{event.source_end}], got '#{substring}'"
    end)
  end

  describe "basic sequences" do
    test "space-separated sounds with even timing" do
      events = parse_events("bd sd hh sd")

      assert length(events) == 4
      assert Enum.map(events, & &1.sound) == ["bd", "sd", "hh", "sd"]
      assert Enum.all?(events, &(&1.duration == 0.25))
      assert Enum.at(events, 0).time == 0.0
      assert_in_delta Enum.at(events, 3).time, 0.75, 0.01
    end

    test "empty and whitespace patterns return empty list" do
      assert parse_events("") == []
      assert parse_events("   ") == []
    end

    test "rests occupy time slots but produce no events" do
      events = parse_events("bd ~ sd ~")

      assert length(events) == 2
      assert Enum.at(events, 0).time == 0.0
      assert_in_delta Enum.at(events, 1).time, 0.5, 0.01
    end

    test "period separator works like space" do
      events = parse_events("bd.sd.hh")

      assert length(events) == 3
      assert Enum.map(events, & &1.sound) == ["bd", "sd", "hh"]
    end
  end

  describe "subdivisions" do
    test "brackets split time within their slot" do
      events = parse_events("bd [sd hh] cp")

      assert length(events) == 4
      assert Enum.map(events, & &1.sound) == ["bd", "sd", "hh", "cp"]
    end

    test "nested brackets subdivide recursively" do
      events = parse_events("[[bd sd] hh]")

      assert length(events) == 3
      assert Enum.map(events, & &1.sound) == ["bd", "sd", "hh"]
    end

    test "repetition modifier [bd sd]*2" do
      events = parse_events("[bd sd]*2")

      assert length(events) == 4
      assert Enum.map(events, & &1.sound) == ["bd", "sd", "bd", "sd"]
    end

    test "long subdivisions parse efficiently" do
      pattern = "bd [" <> String.duplicate("hh ", 50) <> "]"
      events = parse_events(pattern)

      assert length(events) == 51
    end
  end

  describe "polyphony (comma = simultaneous)" do
    test "comma creates simultaneous events at same time" do
      events = parse_events("[bd,sd,hh]")

      assert length(events) == 3
      assert Enum.all?(events, &(&1.time == 0.0))
    end

    test "chord within sequence" do
      events = parse_events("bd [sd,hh] cp")
      sd = Enum.find(events, &(&1.sound == "sd"))
      hh = Enum.find(events, &(&1.sound == "hh"))

      assert length(events) == 4
      assert sd.time == hh.time
    end

    test "nested polyphony" do
      events = parse_events("[[bd,sd] hh]")
      bd = Enum.find(events, &(&1.sound == "bd"))
      sd = Enum.find(events, &(&1.sound == "sd"))

      assert length(events) == 3
      assert_in_delta bd.time, sd.time, 0.01
    end
  end

  describe "polymetric sequences" do
    test "groups have independent timing" do
      events = parse_events("{bd sd hh, cp}")
      cp = Enum.find(events, &(&1.sound == "cp"))

      assert length(events) == 4
      assert_in_delta cp.duration, 1.0, 0.01
    end

    test "step control {bd sd}%4" do
      events = parse_events("{bd sd}%4")

      assert length(events) == 2
      assert Enum.all?(events, &(abs(&1.duration - 0.25) < 0.01))
    end
  end

  describe "modifiers" do
    test "sample selection bd:1" do
      events = parse_events("bd:1*3")

      assert length(events) == 3
      assert Enum.all?(events, &(&1.sound == "bd" and &1.sample == 1))
    end

    test "probability ? and ?0.25" do
      events = parse_events("[bd? sd hh?0.25]")

      assert Enum.at(events, 0).params == %{probability: 0.5}
      assert Enum.at(events, 1).params == %{}
      assert Enum.at(events, 2).params == %{probability: 0.25}
    end

    test "weight @ affects duration distribution" do
      events = parse_events("bd@2 sd")

      assert_in_delta Enum.at(events, 0).duration, 0.666, 0.01
      assert_in_delta Enum.at(events, 1).duration, 0.333, 0.01
    end

    test "elongation _ extends previous event" do
      events = parse_events("bd _ _ sd")

      assert length(events) == 2
      assert_in_delta Enum.at(events, 0).duration, 0.75, 0.01
    end

    test "division /2 slows pattern across cycles" do
      pattern = UzuPattern.parse("[bd sd]/2")

      # /2 means slow(2): pattern spans 2 cycles
      events_0 = UzuPattern.Pattern.query(pattern, 0)
      assert length(events_0) == 1
      assert hd(events_0).sound == "bd"

      events_1 = UzuPattern.Pattern.query(pattern, 1)
      assert length(events_1) == 1
      assert hd(events_1).sound == "sd"
    end

    test "sound parameters |gain:0.8|speed:2" do
      events = parse_events("bd|gain:0.8|speed:2")

      assert length(events) == 1
      assert hd(events).params == %{gain: 0.8, speed: 2.0}
    end
  end

  describe "alternation and random choice" do
    test "random choice bd|sd selects randomly per cycle" do
      pattern = UzuPattern.parse("bd|sd hh")

      # Random choice selects one of the options per cycle
      # The second element (hh) should always be present
      events_0 = UzuPattern.Pattern.query(pattern, 0)
      assert length(events_0) == 2
      assert Enum.at(events_0, 0).sound in ["bd", "sd"]
      assert Enum.at(events_0, 1).sound == "hh"
    end

    test "alternation <bd sd> cycles through options" do
      pattern = UzuPattern.parse("<bd sd> hh cp")

      # Cycle 0: bd hh cp
      events_0 = UzuPattern.Pattern.query(pattern, 0)
      assert length(events_0) == 3
      assert Enum.at(events_0, 0).sound == "bd"

      # Cycle 1: sd hh cp
      events_1 = UzuPattern.Pattern.query(pattern, 1)
      assert length(events_1) == 3
      assert Enum.at(events_1, 0).sound == "sd"
    end
  end

  describe "euclidean rhythms" do
    test "bd(3,8) generates 3 hits over 8 steps" do
      events = parse_events("hh bd(3,8)")

      assert length(events) == 4
      assert Enum.at(events, 0).sound == "hh"
      assert Enum.count(events, &(&1.sound == "bd")) == 3
    end

    test "cp(3,8) standalone" do
      events = parse_events("cp(3,8)")

      assert length(events) == 3
    end
  end

  describe "realistic patterns" do
    test "four-on-the-floor" do
      events = parse_events("bd sd bd sd")

      assert length(events) == 4
      assert_in_delta Enum.at(events, 0).duration, 0.25, 0.01
    end

    test "hihat subdivisions" do
      events = parse_events("bd [hh hh] sd [hh hh]")

      assert length(events) == 6
    end

    test "layered kick and hihat" do
      events = parse_events("[bd,hh] [~,hh] [sd,hh] [~,hh]")

      assert length(events) == 6
    end

    test "polyrhythm 3 against 4" do
      events = parse_events("{bd bd bd bd, cp cp cp}")

      assert length(events) == 7
    end
  end

  describe "event structure" do
    test "events have all required fields" do
      [event | _] = parse_events("bd:1")

      assert %Event{} = event
      assert is_binary(event.sound)
      assert is_float(event.time)
      assert is_float(event.duration)
      assert is_map(event.params)
      assert event.sample == 1
    end

    test "all times within cycle bounds [0, 1)" do
      events = parse_events("bd sd hh cp oh rim")

      Enum.each(events, fn event ->
        assert event.time >= 0.0 and event.time < 1.0
      end)
    end
  end

  describe "source position tracking" do
    test "simple sequence" do
      pattern = "bd sd"
      events = parse_events(pattern)
      [bd, sd] = events

      # "bd sd"
      #  01 34
      assert {bd.source_start, bd.source_end} == {0, 2}
      assert {sd.source_start, sd.source_end} == {3, 5}
      assert_positions_match(pattern, events)
    end

    test "subdivision preserves inner positions" do
      pattern = "[bd sd]"
      events = parse_events(pattern)
      [bd, sd] = events

      # "[bd sd]"
      #  0123456
      assert {bd.source_start, bd.source_end} == {1, 3}
      assert {sd.source_start, sd.source_end} == {4, 6}
      assert_positions_match(pattern, events)
    end

    test "nested subdivisions" do
      pattern = "[[bd] hh]"
      events = parse_events(pattern)
      [bd, hh] = events

      # "[[bd] hh]"
      #  012345678
      assert {bd.source_start, bd.source_end} == {2, 4}
      assert {hh.source_start, hh.source_end} == {6, 8}
      assert_positions_match(pattern, events)
    end

    test "deeply nested subdivisions" do
      pattern = "[[[bd]]]"
      [bd] = parse_events(pattern)

      # "[[[bd]]]"
      #  01234567
      assert {bd.source_start, bd.source_end} == {3, 5}
      assert String.slice(pattern, bd.source_start, bd.source_end - bd.source_start) == "bd"
    end

    test "mixed pattern with subdivision" do
      pattern = "bd [sd hh] cp"
      events = parse_events(pattern)

      assert_positions_match(pattern, events)
    end

    test "sample selection includes modifier in position" do
      pattern = "bd:0 sd:1"
      events = parse_events(pattern)
      [bd, sd] = events

      # "bd:0 sd:1"
      #  012345678
      assert {bd.source_start, bd.source_end} == {0, 4}
      assert {sd.source_start, sd.source_end} == {5, 9}
    end

    test "division operator preserves inner positions" do
      p = UzuPattern.parse("[sd sd]/2")

      # "[sd sd]/2" with /2 spreads events across 2 cycles
      # Cycle 0 gets first sd, cycle 1 gets second sd
      [sd1] = UzuPattern.Pattern.query(p, 0)
      [sd2] = UzuPattern.Pattern.query(p, 1)

      # "[sd sd]/2"
      #  012345678
      assert {sd1.source_start, sd1.source_end} == {1, 3}
      assert {sd2.source_start, sd2.source_end} == {4, 6}
    end

    test "multiple nested subdivisions" do
      pattern = "[[bd sd] [hh cp]]"
      events = parse_events(pattern)

      assert length(events) == 4
      assert_positions_match(pattern, events)
    end
  end
end
