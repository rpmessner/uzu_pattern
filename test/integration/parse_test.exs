defmodule UzuPattern.Integration.ParseTest do
  @moduledoc """
  Integration tests for UzuPattern.parse/1.

  Tests end-to-end behavior from mini-notation string to events.
  Focus: realistic patterns, feature combinations, edge cases.

  Follows Strudel test conventions:
  - Focus on values and timing (behavior), not internal structure
  - Use helper functions for cleaner assertions
  - Source position tests separated
  """

  use ExUnit.Case, async: true

  alias Ratio
  alias UzuPattern.Hap
  alias UzuPattern.Pattern
  alias UzuPattern.Time
  alias UzuPattern.TimeSpan

  # Helper: parse string and get haps for cycle 0
  defp parse_events(pattern_string) do
    pattern_string
    |> UzuPattern.parse()
    |> UzuPattern.query(0)
  end

  # Strudel-style helpers
  defp sounds(haps), do: Enum.map(haps, &Hap.sound/1)

  # Sort haps by begin time
  defp sort_by_time(haps) do
    Enum.sort(haps, fn a, b -> Time.lt?(a.part.begin, b.part.begin) end)
  end

  # Check all haps have the same begin time
  defp all_same_time?(haps, expected) do
    Enum.all?(haps, fn h -> Time.eq?(h.part.begin, expected) end)
  end

  # Check all haps have same duration
  defp all_duration_eq?(haps, expected) do
    Enum.all?(haps, fn h -> Time.eq?(TimeSpan.duration(h.part), expected) end)
  end

  # Helper: assert locations match expected {start, end} tuples
  defp assert_locations_match(pattern, haps) do
    Enum.each(haps, fn hap ->
      case Hap.location(hap) do
        {start, end_pos} ->
          substring = String.slice(pattern, start, end_pos - start)
          sound = Hap.sound(hap)

          assert String.starts_with?(substring, sound) or substring == sound,
                 "Position mismatch: expected '#{sound}' at [#{start}:#{end_pos}], got '#{substring}'"

        nil ->
          :ok
      end
    end)
  end

  describe "basic sequences" do
    test "space-separated sounds with even timing" do
      haps = sort_by_time(parse_events("bd sd hh sd"))

      assert length(haps) == 4
      assert sounds(haps) == ["bd", "sd", "hh", "sd"]
      assert all_duration_eq?(haps, Time.new(1, 4))
      assert Time.eq?(hd(haps).part.begin, Time.zero())
      assert Time.eq?(List.last(haps).part.begin, Time.new(3, 4))
    end

    test "empty and whitespace patterns return empty list" do
      assert parse_events("") == []
      assert parse_events("   ") == []
    end

    test "rests occupy time slots but produce no events" do
      haps = sort_by_time(parse_events("bd ~ sd ~"))

      assert length(haps) == 2
      assert Time.eq?(hd(haps).part.begin, Time.zero())
      assert Time.eq?(Enum.at(haps, 1).part.begin, Time.half())
    end

    test "period separator works like space" do
      haps = parse_events("bd.sd.hh")

      assert length(haps) == 3
      assert sounds(haps) == ["bd", "sd", "hh"]
    end
  end

  describe "subdivisions" do
    test "brackets split time within their slot" do
      haps = parse_events("bd [sd hh] cp")

      assert length(haps) == 4
      assert sounds(haps) == ["bd", "sd", "hh", "cp"]
    end

    test "nested brackets subdivide recursively" do
      haps = parse_events("[[bd sd] hh]")

      assert length(haps) == 3
      assert sounds(haps) == ["bd", "sd", "hh"]
    end

    test "repetition modifier [bd sd]*2" do
      haps = parse_events("[bd sd]*2")

      assert length(haps) == 4
      assert sounds(haps) == ["bd", "sd", "bd", "sd"]
    end

    test "long subdivisions parse efficiently" do
      pattern = "bd [" <> String.duplicate("hh ", 50) <> "]"
      haps = parse_events(pattern)

      assert length(haps) == 51
    end
  end

  describe "polyphony (comma = simultaneous)" do
    test "comma creates simultaneous events at same time" do
      haps = parse_events("[bd,sd,hh]")

      assert length(haps) == 3
      assert all_same_time?(haps, Time.zero())
    end

    test "chord within sequence" do
      haps = parse_events("bd [sd,hh] cp")
      sd = Enum.find(haps, &(Hap.sound(&1) == "sd"))
      hh = Enum.find(haps, &(Hap.sound(&1) == "hh"))

      assert length(haps) == 4
      assert Time.eq?(sd.part.begin, hh.part.begin)
    end

    test "nested polyphony" do
      haps = parse_events("[[bd,sd] hh]")
      bd = Enum.find(haps, &(Hap.sound(&1) == "bd"))
      sd = Enum.find(haps, &(Hap.sound(&1) == "sd"))

      assert length(haps) == 3
      assert Time.eq?(bd.part.begin, sd.part.begin)
    end
  end

  describe "polymetric sequences" do
    test "groups have independent timing" do
      haps = parse_events("{bd sd hh, cp}")
      cp = Enum.find(haps, &(Hap.sound(&1) == "cp"))

      assert length(haps) == 4
      assert Time.eq?(TimeSpan.duration(cp.part), Time.one())
    end

    test "step control {bd sd}%4" do
      haps = parse_events("{bd sd}%4")

      assert length(haps) == 2
      assert all_duration_eq?(haps, Time.new(1, 4))
    end
  end

  describe "modifiers" do
    test "sample selection bd:1" do
      haps = parse_events("bd:1*3")

      assert length(haps) == 3
      assert Enum.all?(haps, &(Hap.sound(&1) == "bd" and Hap.sample(&1) == 1))
    end

    test "probability ? and ?0.25" do
      haps = parse_events("[bd? sd hh?0.25]")

      assert Enum.at(haps, 0).value[:probability] == 0.5
      assert Enum.at(haps, 1).value[:probability] == nil
      assert Enum.at(haps, 2).value[:probability] == 0.25
    end

    test "weight @ affects duration distribution" do
      haps = sort_by_time(parse_events("bd@2 sd"))

      # bd@2 gets 2/3, sd gets 1/3
      assert Time.eq?(TimeSpan.duration(Enum.at(haps, 0).part), Time.new(2, 3))
      assert Time.eq?(TimeSpan.duration(Enum.at(haps, 1).part), Time.new(1, 3))
    end

    test "elongation _ extends previous event" do
      haps = sort_by_time(parse_events("bd _ _ sd"))

      assert length(haps) == 2
      # bd spans 3/4 of the cycle
      assert Time.eq?(TimeSpan.duration(hd(haps).part), Time.new(3, 4))
    end

    test "division /2 slows pattern across cycles" do
      pattern = UzuPattern.parse("[bd sd]/2")

      # /2 means slow(2): pattern spans 2 cycles
      haps_0 = Pattern.query(pattern, 0)
      assert length(haps_0) == 1
      assert Hap.sound(hd(haps_0)) == "bd"

      haps_1 = Pattern.query(pattern, 1)
      assert length(haps_1) == 1
      assert Hap.sound(hd(haps_1)) == "sd"
    end

    test "sound parameters |gain:0.8|speed:2" do
      haps = parse_events("bd|gain:0.8|speed:2")

      assert length(haps) == 1
      hap = hd(haps)
      assert hap.value[:gain] == 0.8
      assert hap.value[:speed] == 2.0
    end
  end

  describe "alternation and random choice" do
    test "random choice bd|sd selects randomly per cycle" do
      pattern = UzuPattern.parse("bd|sd hh")

      # Random choice selects one of the options per cycle
      # The second element (hh) should always be present
      haps_0 = Pattern.query(pattern, 0)
      assert length(haps_0) == 2
      assert Hap.sound(Enum.at(haps_0, 0)) in ["bd", "sd"]
      assert Hap.sound(Enum.at(haps_0, 1)) == "hh"
    end

    test "alternation <bd sd> cycles through options" do
      pattern = UzuPattern.parse("<bd sd> hh cp")

      # Cycle 0: bd hh cp
      haps_0 = Pattern.query(pattern, 0)
      assert length(haps_0) == 3
      assert Hap.sound(Enum.at(haps_0, 0)) == "bd"

      # Cycle 1: sd hh cp
      haps_1 = Pattern.query(pattern, 1)
      assert length(haps_1) == 3
      assert Hap.sound(Enum.at(haps_1, 0)) == "sd"
    end
  end

  describe "euclidean rhythms" do
    test "bd(3,8) generates 3 hits over 8 steps" do
      haps = parse_events("hh bd(3,8)")

      assert length(haps) == 4
      assert Hap.sound(Enum.at(haps, 0)) == "hh"
      assert Enum.count(haps, &(Hap.sound(&1) == "bd")) == 3
    end

    test "cp(3,8) standalone" do
      haps = parse_events("cp(3,8)")

      assert length(haps) == 3
    end
  end

  describe "realistic patterns" do
    test "four-on-the-floor" do
      haps = parse_events("bd sd bd sd")

      assert length(haps) == 4
      assert all_duration_eq?(haps, Time.new(1, 4))
    end

    test "hihat subdivisions" do
      haps = parse_events("bd [hh hh] sd [hh hh]")

      assert length(haps) == 6
    end

    test "layered kick and hihat" do
      haps = parse_events("[bd,hh] [~,hh] [sd,hh] [~,hh]")

      assert length(haps) == 6
    end

    test "polyrhythm 3 against 4" do
      haps = parse_events("{bd bd bd bd, cp cp cp}")

      assert length(haps) == 7
    end
  end

  describe "event structure" do
    test "haps have all required fields" do
      [hap | _] = parse_events("bd:1")

      assert %Hap{} = hap
      assert is_binary(Hap.sound(hap))
      # Times are Ratio values for exact arithmetic
      assert %Ratio{} = hap.part.begin
      assert %Ratio{} = hap.part.end
      assert is_map(hap.value)
      assert Hap.sample(hap) == 1
    end

    test "all times within cycle bounds [0, 1)" do
      haps = parse_events("bd sd hh cp oh rim")

      Enum.each(haps, fn hap ->
        assert Time.gte?(hap.part.begin, Time.zero())
        assert Time.lt?(hap.part.begin, Time.one())
      end)
    end
  end

  describe "source position tracking" do
    test "simple sequence" do
      pattern = "bd sd"
      haps = parse_events(pattern)
      [bd, sd] = haps

      # "bd sd"
      #  01 34
      assert Hap.location(bd) == {0, 2}
      assert Hap.location(sd) == {3, 5}
      assert_locations_match(pattern, haps)
    end

    test "subdivision preserves inner positions" do
      pattern = "[bd sd]"
      haps = parse_events(pattern)
      [bd, sd] = haps

      # "[bd sd]"
      #  0123456
      assert Hap.location(bd) == {1, 3}
      assert Hap.location(sd) == {4, 6}
      assert_locations_match(pattern, haps)
    end

    test "nested subdivisions" do
      pattern = "[[bd] hh]"
      haps = parse_events(pattern)
      [bd, hh] = haps

      # "[[bd] hh]"
      #  012345678
      assert Hap.location(bd) == {2, 4}
      assert Hap.location(hh) == {6, 8}
      assert_locations_match(pattern, haps)
    end

    test "deeply nested subdivisions" do
      pattern = "[[[bd]]]"
      [bd] = parse_events(pattern)

      # "[[[bd]]]"
      #  01234567
      assert Hap.location(bd) == {3, 5}
      {start, end_pos} = Hap.location(bd)
      assert String.slice(pattern, start, end_pos - start) == "bd"
    end

    test "mixed pattern with subdivision" do
      pattern = "bd [sd hh] cp"
      haps = parse_events(pattern)

      assert_locations_match(pattern, haps)
    end

    test "sample selection includes modifier in position" do
      pattern = "bd:0 sd:1"
      haps = parse_events(pattern)
      [bd, sd] = haps

      # "bd:0 sd:1"
      #  012345678
      assert Hap.location(bd) == {0, 4}
      assert Hap.location(sd) == {5, 9}
    end

    test "division operator preserves inner positions" do
      p = UzuPattern.parse("[sd sd]/2")

      # "[sd sd]/2" with /2 spreads events across 2 cycles
      # Cycle 0 gets first sd, cycle 1 gets second sd
      [sd1] = Pattern.query(p, 0)
      [sd2] = Pattern.query(p, 1)

      # "[sd sd]/2"
      #  012345678
      assert Hap.location(sd1) == {1, 3}
      assert Hap.location(sd2) == {4, 6}
    end

    test "multiple nested subdivisions" do
      pattern = "[[bd sd] [hh cp]]"
      haps = parse_events(pattern)

      assert length(haps) == 4
      assert_locations_match(pattern, haps)
    end
  end
end
