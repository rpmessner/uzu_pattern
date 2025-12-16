defmodule UzuPattern.Pattern.TimeTest do
  @moduledoc """
  Tests for time manipulation functions.

  Functions: fast, slow, early, late, ply, compress, zoom, linger
  """

  use ExUnit.Case, async: true

  alias UzuPattern.Hap
  alias UzuPattern.Pattern
  alias UzuPattern.Time
  alias UzuPattern.TimeSpan

  defp parse(str), do: UzuPattern.parse(str)

  # Strudel-style helpers
  defp sounds(haps), do: Enum.map(haps, &Hap.sound/1)

  # Sort haps by part begin time using exact rational comparison
  defp sort_by_time(haps) do
    Enum.sort(haps, fn a, b -> Time.lt?(a.part.begin, b.part.begin) end)
  end

  describe "fast/2" do
    test "plays pattern twice per cycle with factor 2" do
      pattern = parse("bd sd") |> Pattern.fast(2)
      haps = sort_by_time(Pattern.events(pattern))

      assert length(haps) == 4
      assert sounds(haps) == ["bd", "sd", "bd", "sd"]
      assert Time.eq?(Enum.at(haps, 0).part.begin, Time.zero())
      assert Time.eq?(Enum.at(haps, 1).part.begin, Time.new(1, 4))
      assert Time.eq?(Enum.at(haps, 2).part.begin, Time.half())
      assert Time.eq?(Enum.at(haps, 3).part.begin, Time.new(3, 4))
    end

    test "slows pattern with factor < 1" do
      pattern = parse("bd sd hh cp") |> Pattern.fast(0.5)

      haps_0 = Pattern.query(pattern, 0)
      assert length(haps_0) == 2
      assert sounds(haps_0) == ["bd", "sd"]

      haps_1 = Pattern.query(pattern, 1)
      assert length(haps_1) == 2
      assert sounds(haps_1) == ["hh", "cp"]
    end

    test "fast maintains pattern at high cycles" do
      pattern = parse("bd sd") |> Pattern.fast(2)

      haps_0 = Pattern.query(pattern, 0)
      haps_100 = Pattern.query(pattern, 100)

      assert length(haps_0) == length(haps_100)
      assert sounds(haps_0) == sounds(haps_100)
    end

    test "fast compression keeps events in bounds" do
      pattern = parse("bd sd hh cp") |> Pattern.fast(4)
      haps = Pattern.query(pattern, 0)

      Enum.each(haps, fn hap ->
        assert Time.gte?(hap.part.begin, Time.zero())
        assert Time.lt?(hap.part.begin, Time.one())
      end)
    end
  end

  describe "slow/2" do
    test "slows pattern across multiple cycles" do
      pattern = parse("bd sd") |> Pattern.slow(2)

      haps_0 = Pattern.query(pattern, 0)
      assert length(haps_0) == 1
      assert Hap.sound(hd(haps_0)) == "bd"

      haps_1 = Pattern.query(pattern, 1)
      assert length(haps_1) == 1
      assert Hap.sound(hd(haps_1)) == "sd"
    end

    test "slow spreads correctly across many cycles" do
      pattern = parse("a b c d") |> Pattern.slow(4)

      assert Hap.sound(hd(Pattern.query(pattern, 0))) == "a"
      assert Hap.sound(hd(Pattern.query(pattern, 1))) == "b"
      assert Hap.sound(hd(Pattern.query(pattern, 2))) == "c"
      assert Hap.sound(hd(Pattern.query(pattern, 3))) == "d"
      assert Hap.sound(hd(Pattern.query(pattern, 4))) == "a"
      assert Hap.sound(hd(Pattern.query(pattern, 100))) == "a"
    end
  end

  describe "early/2" do
    test "shifts pattern earlier with wrap" do
      pattern = parse("bd sd") |> Pattern.early(0.25)
      haps = sort_by_time(Pattern.events(pattern))

      assert Time.eq?(Enum.at(haps, 0).part.begin, Time.new(1, 4))
      assert Time.eq?(Enum.at(haps, 1).part.begin, Time.new(3, 4))
    end

    test "early wraps correctly at boundaries" do
      pattern = parse("bd") |> Pattern.early(0.5)
      [hap] = Pattern.query(pattern, 0)
      assert Time.eq?(hap.part.begin, Time.half())
    end
  end

  describe "late/2" do
    test "shifts pattern later with wrap" do
      pattern = parse("bd sd") |> Pattern.late(0.25)
      haps = sort_by_time(Pattern.events(pattern))

      assert Time.eq?(Enum.at(haps, 0).part.begin, Time.new(1, 4))
      assert Time.eq?(Enum.at(haps, 1).part.begin, Time.new(3, 4))
    end

    test "late wraps correctly at boundaries" do
      pattern = parse("bd") |> Pattern.late(0.75)
      [hap] = Pattern.query(pattern, 0)
      assert Time.eq?(hap.part.begin, Time.new(3, 4))
    end
  end

  describe "ply/2" do
    test "repeats each event N times" do
      pattern = parse("bd sd") |> Pattern.ply(2)
      haps = Pattern.events(pattern)

      assert length(haps) == 4
    end

    test "divides duration correctly" do
      pattern = parse("bd sd") |> Pattern.ply(3)
      haps = Pattern.events(pattern)

      assert length(haps) == 6
      # Duration should be 1/6 (half of original 1/2, divided by 3)
      assert Time.eq?(TimeSpan.duration(hd(haps).part), Time.new(1, 6))
    end

    test "spaces repetitions evenly within event duration" do
      pattern = parse("bd") |> Pattern.ply(4)
      haps = sort_by_time(Pattern.events(pattern))

      assert length(haps) == 4
      assert Time.eq?(Enum.at(haps, 0).part.begin, Time.zero())
      assert Time.eq?(Enum.at(haps, 1).part.begin, Time.new(1, 4))
      assert Time.eq?(Enum.at(haps, 2).part.begin, Time.half())
      assert Time.eq?(Enum.at(haps, 3).part.begin, Time.new(3, 4))
    end

    test "maintains event properties" do
      pattern = parse("bd:2") |> Pattern.ply(2)
      haps = Pattern.events(pattern)

      assert Enum.all?(haps, fn h -> Hap.sample(h) == 2 end)
      assert Enum.all?(haps, fn h -> Hap.sound(h) == "bd" end)
    end

    test "works with multiple events" do
      pattern = parse("bd sd hh") |> Pattern.ply(2)
      haps = Pattern.events(pattern)

      assert length(haps) == 6

      sound_list = sounds(haps)
      assert Enum.count(sound_list, &(&1 == "bd")) == 2
      assert Enum.count(sound_list, &(&1 == "sd")) == 2
      assert Enum.count(sound_list, &(&1 == "hh")) == 2
    end
  end

  describe "compress/3" do
    test "fits pattern into time segment" do
      pattern = parse("bd sd hh cp") |> Pattern.compress(0.25, 0.75)
      haps = Pattern.events(pattern)

      assert Enum.all?(haps, fn h ->
               Time.gte?(h.part.begin, Time.new(1, 4)) and Time.lt?(h.part.begin, Time.new(3, 4))
             end)
    end

    test "maintains event count" do
      pattern = parse("bd sd hh cp") |> Pattern.compress(0.25, 0.75)
      haps = Pattern.events(pattern)

      assert length(haps) == 4
    end

    test "scales times proportionally" do
      pattern = parse("bd sd") |> Pattern.compress(0.0, 0.5)
      haps = sort_by_time(Pattern.events(pattern))

      assert Time.eq?(Enum.at(haps, 0).part.begin, Time.zero())
      assert Time.eq?(Enum.at(haps, 1).part.begin, Time.new(1, 4))
    end

    test "scales durations proportionally" do
      pattern = parse("bd sd") |> Pattern.compress(0.0, 0.5)
      haps = Pattern.events(pattern)

      assert Time.eq?(TimeSpan.duration(Enum.at(haps, 0).part), Time.new(1, 4))
      assert Time.eq?(TimeSpan.duration(Enum.at(haps, 1).part), Time.new(1, 4))
    end

    test "creates rhythmic gap" do
      pattern = parse("bd sd") |> Pattern.compress(0.25, 0.75)
      haps = Pattern.events(pattern)

      assert Enum.all?(haps, fn h -> Time.gte?(h.part.begin, Time.new(1, 4)) end)
      assert Enum.all?(haps, fn h -> Time.lte?(h.part.end, Time.new(3, 4)) end)
    end

    test "maintains event properties" do
      pattern = parse("bd:3 sd:2") |> Pattern.compress(0.25, 0.75)
      haps = Pattern.events(pattern)

      assert Hap.sound(Enum.at(haps, 0)) == "bd"
      assert Hap.sample(Enum.at(haps, 0)) == 3
      assert Hap.sound(Enum.at(haps, 1)) == "sd"
      assert Hap.sample(Enum.at(haps, 1)) == 2
    end
  end

  describe "zoom/3" do
    test "extracts and expands time segment" do
      pattern = parse("bd sd hh cp") |> Pattern.zoom(0.25, 0.75)
      haps = Pattern.events(pattern)

      assert length(haps) == 2
      sound_list = sounds(haps)
      assert "sd" in sound_list
      assert "hh" in sound_list
    end

    test "expands extracted segment to full cycle" do
      pattern = parse("bd sd hh cp") |> Pattern.zoom(0.5, 1.0)
      haps = sort_by_time(Pattern.events(pattern))

      assert length(haps) == 2
      assert Time.eq?(Enum.at(haps, 0).part.begin, Time.zero())
      assert Time.eq?(Enum.at(haps, 1).part.begin, Time.half())
    end

    test "scales durations correctly" do
      pattern = parse("bd sd") |> Pattern.zoom(0.0, 0.5)
      haps = Pattern.events(pattern)

      assert length(haps) == 1
      assert Time.eq?(TimeSpan.duration(hd(haps).part), Time.one())
    end

    test "filters events outside window" do
      pattern = parse("bd sd hh cp") |> Pattern.zoom(0.25, 0.5)
      haps = Pattern.events(pattern)

      assert length(haps) == 1
      assert Hap.sound(hd(haps)) == "sd"
    end

    test "maintains event properties" do
      pattern = parse("bd:1 sd:2 hh:3 cp:4") |> Pattern.zoom(0.25, 0.75)
      haps = Pattern.events(pattern)

      assert Hap.sound(Enum.at(haps, 0)) == "sd"
      assert Hap.sample(Enum.at(haps, 0)) == 2
      assert Hap.sound(Enum.at(haps, 1)) == "hh"
      assert Hap.sample(Enum.at(haps, 1)) == 3
    end

    test "zoom is inverse of compress" do
      original = parse("bd sd hh cp")
      zoomed = Pattern.zoom(original, 0.25, 0.75)

      assert length(Pattern.events(zoomed)) == 2
    end
  end

  describe "linger/2" do
    test "repeats fraction of pattern" do
      pattern = parse("bd sd hh cp") |> Pattern.linger(0.5)
      haps = Pattern.events(pattern)

      assert length(haps) == 4

      sound_list = sounds(haps)
      assert Enum.count(sound_list, &(&1 == "bd")) == 2
      assert Enum.count(sound_list, &(&1 == "sd")) == 2
    end

    test "linger(0.25) repeats first quarter 4 times" do
      pattern = parse("bd sd hh cp") |> Pattern.linger(0.25)
      haps = Pattern.events(pattern)

      assert length(haps) == 4
      assert Enum.all?(haps, fn h -> Hap.sound(h) == "bd" end)
    end

    test "linger(1.0) keeps pattern unchanged" do
      original = parse("bd sd hh cp")
      lingered = Pattern.linger(original, 1.0)

      assert length(Pattern.events(lingered)) == 4
      original_sounds = sounds(Pattern.events(original))
      lingered_sounds = sounds(Pattern.events(lingered))
      assert original_sounds == lingered_sounds
    end

    test "spaces repetitions correctly" do
      pattern = parse("bd sd") |> Pattern.linger(0.5)
      haps = sort_by_time(Pattern.events(pattern))

      assert length(haps) == 2
      assert Enum.all?(haps, fn h -> Hap.sound(h) == "bd" end)

      assert Time.eq?(Enum.at(haps, 0).part.begin, Time.zero())
      assert Time.eq?(Enum.at(haps, 1).part.begin, Time.half())
    end

    test "maintains event properties" do
      pattern = parse("bd:3 sd:2 hh:1 cp:0") |> Pattern.linger(0.5)
      haps = Pattern.events(pattern)

      bd_haps = Enum.filter(haps, fn h -> Hap.sound(h) == "bd" end)
      sd_haps = Enum.filter(haps, fn h -> Hap.sound(h) == "sd" end)

      assert length(bd_haps) == 2
      assert Enum.all?(bd_haps, fn h -> Hap.sample(h) == 3 end)

      assert length(sd_haps) == 2
      assert Enum.all?(sd_haps, fn h -> Hap.sample(h) == 2 end)
    end

    test "linger(0.333) repeats first third 3 times" do
      pattern = parse("bd sd hh") |> Pattern.linger(0.333)
      haps = Pattern.events(pattern)

      assert length(haps) == 3
      assert Enum.all?(haps, fn h -> Hap.sound(h) == "bd" end)
    end
  end

  describe "fast/2 with pattern arguments" do
    test "fast with mini-notation string alternates speeds" do
      pattern = parse("bd sd") |> Pattern.fast("<2 4>")

      # Cycle 0: fast(2) - 4 events
      haps_0 = Pattern.query(pattern, 0)
      assert length(haps_0) == 4
      assert sounds(haps_0) == ["bd", "sd", "bd", "sd"]

      # Cycle 1: fast(4) - 8 events
      haps_1 = Pattern.query(pattern, 1)
      assert length(haps_1) == 8
      assert sounds(haps_1) == ["bd", "sd", "bd", "sd", "bd", "sd", "bd", "sd"]
    end

    test "fast with pattern argument uses squeeze semantics" do
      factor_pattern =
        UzuPattern.Pattern.slowcat([
          UzuPattern.Pattern.pure("2"),
          UzuPattern.Pattern.pure("4")
        ])

      pattern = parse("bd sd") |> Pattern.fast(factor_pattern)

      # Cycle 0: fast(2)
      haps_0 = Pattern.query(pattern, 0)
      assert length(haps_0) == 4

      # Cycle 1: fast(4)
      haps_1 = Pattern.query(pattern, 1)
      assert length(haps_1) == 8
    end

    test "fast string argument returns unchanged pattern on invalid string" do
      pattern = parse("bd sd") |> Pattern.fast("invalid")
      haps = Pattern.query(pattern, 0)
      # Should return original unchanged pattern (2 events)
      assert length(haps) == 2
    end
  end

  describe "slow/2 with pattern arguments" do
    test "slow with mini-notation string alternates speeds" do
      pattern = parse("bd sd hh cp") |> Pattern.slow("<2 4>")

      # Cycle 0: slow(2) - first half of pattern
      haps_0 = Pattern.query(pattern, 0)
      assert length(haps_0) == 2
      assert sounds(haps_0) == ["bd", "sd"]

      # Cycle 1: slow(4) - first quarter of pattern
      haps_1 = Pattern.query(pattern, 1)
      assert length(haps_1) == 1
      assert sounds(haps_1) == ["bd"]

      # Cycle 2: slow(2) again - first half (each cycle is independent)
      haps_2 = Pattern.query(pattern, 2)
      assert length(haps_2) == 2
      assert sounds(haps_2) == ["bd", "sd"]
    end

    test "slow with pattern argument" do
      factor_pattern =
        UzuPattern.Pattern.slowcat([
          UzuPattern.Pattern.pure("2"),
          UzuPattern.Pattern.pure("4")
        ])

      pattern = parse("bd sd hh cp") |> Pattern.slow(factor_pattern)

      # Cycle 0: slow(2) - 2 events
      haps_0 = Pattern.query(pattern, 0)
      assert length(haps_0) == 2
    end
  end

  describe "fast/slow round trip" do
    test "fast/slow preserves structure" do
      pattern = parse("bd sd")

      transformed = pattern |> Pattern.fast(2) |> Pattern.slow(2)

      original_haps = sort_by_time(Pattern.query(pattern, 0))
      transformed_haps = sort_by_time(Pattern.query(transformed, 0))

      assert length(original_haps) == length(transformed_haps)

      Enum.zip(original_haps, transformed_haps)
      |> Enum.each(fn {orig, trans} ->
        assert Hap.sound(orig) == Hap.sound(trans)
        assert Time.eq?(orig.part.begin, trans.part.begin)
      end)
    end

    test "fast of slow of fast" do
      pattern =
        parse("bd sd hh cp")
        |> Pattern.fast(2)
        |> Pattern.slow(2)
        |> Pattern.fast(2)

      haps = Pattern.query(pattern, 0)
      assert length(haps) == 8
    end
  end
end
