defmodule UzuPattern.Pattern.TimeTest do
  @moduledoc """
  Tests for time manipulation functions.

  Functions: fast, slow, early, late, ply, compress, zoom, linger
  """

  use ExUnit.Case, async: true

  alias UzuPattern.Pattern

  defp parse(str), do: UzuPattern.parse(str)

  describe "fast/2" do
    test "plays pattern twice per cycle with factor 2" do
      pattern = parse("bd sd") |> Pattern.fast(2)
      events = Pattern.events(pattern)

      assert length(events) == 4
      assert Enum.map(events, & &1.sound) == ["bd", "sd", "bd", "sd"]
      assert Enum.at(events, 0).time == 0.0
      assert Enum.at(events, 1).time == 0.25
      assert Enum.at(events, 2).time == 0.5
      assert Enum.at(events, 3).time == 0.75
    end

    test "slows pattern with factor < 1" do
      pattern = parse("bd sd hh cp") |> Pattern.fast(0.5)

      events_0 = Pattern.query(pattern, 0)
      assert length(events_0) == 2
      assert Enum.map(events_0, & &1.sound) == ["bd", "sd"]

      events_1 = Pattern.query(pattern, 1)
      assert length(events_1) == 2
      assert Enum.map(events_1, & &1.sound) == ["hh", "cp"]
    end

    test "fast maintains pattern at high cycles" do
      pattern = parse("bd sd") |> Pattern.fast(2)

      events_0 = Pattern.query(pattern, 0)
      events_100 = Pattern.query(pattern, 100)

      assert length(events_0) == length(events_100)
      assert Enum.map(events_0, & &1.sound) == Enum.map(events_100, & &1.sound)
    end

    test "fast compression keeps events in bounds" do
      pattern = parse("bd sd hh cp") |> Pattern.fast(4)
      events = Pattern.query(pattern, 0)

      Enum.each(events, fn event ->
        assert event.time >= 0.0
        assert event.time < 1.0
      end)
    end
  end

  describe "slow/2" do
    test "slows pattern across multiple cycles" do
      pattern = parse("bd sd") |> Pattern.slow(2)

      events_0 = Pattern.query(pattern, 0)
      assert length(events_0) == 1
      assert hd(events_0).sound == "bd"

      events_1 = Pattern.query(pattern, 1)
      assert length(events_1) == 1
      assert hd(events_1).sound == "sd"
    end

    test "slow spreads correctly across many cycles" do
      pattern = parse("a b c d") |> Pattern.slow(4)

      assert hd(Pattern.query(pattern, 0)).sound == "a"
      assert hd(Pattern.query(pattern, 1)).sound == "b"
      assert hd(Pattern.query(pattern, 2)).sound == "c"
      assert hd(Pattern.query(pattern, 3)).sound == "d"
      assert hd(Pattern.query(pattern, 4)).sound == "a"
      assert hd(Pattern.query(pattern, 100)).sound == "a"
    end
  end

  describe "early/2" do
    test "shifts pattern earlier with wrap" do
      pattern = parse("bd sd") |> Pattern.early(0.25)
      events = Pattern.events(pattern)

      times = Enum.map(events, & &1.time) |> Enum.sort()
      assert_in_delta Enum.at(times, 0), 0.25, 0.01
      assert_in_delta Enum.at(times, 1), 0.75, 0.01
    end

    test "early wraps correctly at boundaries" do
      pattern = parse("bd") |> Pattern.early(0.5)
      [event] = Pattern.query(pattern, 0)
      assert_in_delta event.time, 0.5, 0.001
    end
  end

  describe "late/2" do
    test "shifts pattern later with wrap" do
      pattern = parse("bd sd") |> Pattern.late(0.25)
      events = Pattern.events(pattern)

      times = Enum.map(events, & &1.time) |> Enum.sort()
      assert_in_delta Enum.at(times, 0), 0.25, 0.01
      assert_in_delta Enum.at(times, 1), 0.75, 0.01
    end

    test "late wraps correctly at boundaries" do
      pattern = parse("bd") |> Pattern.late(0.75)
      [event] = Pattern.query(pattern, 0)
      assert_in_delta event.time, 0.75, 0.001
    end
  end

  describe "ply/2" do
    test "repeats each event N times" do
      pattern = parse("bd sd") |> Pattern.ply(2)
      events = Pattern.events(pattern)

      assert length(events) == 4
    end

    test "divides duration correctly" do
      pattern = parse("bd sd") |> Pattern.ply(3)
      events = Pattern.events(pattern)

      assert length(events) == 6
      assert_in_delta Enum.at(events, 0).duration, 0.5 / 3, 0.01
    end

    test "spaces repetitions evenly within event duration" do
      pattern = parse("bd") |> Pattern.ply(4)
      events = Pattern.events(pattern)

      assert length(events) == 4
      assert_in_delta Enum.at(events, 0).time, 0.0, 0.01
      assert_in_delta Enum.at(events, 1).time, 0.25, 0.01
      assert_in_delta Enum.at(events, 2).time, 0.5, 0.01
      assert_in_delta Enum.at(events, 3).time, 0.75, 0.01
    end

    test "maintains event properties" do
      pattern = parse("bd:2") |> Pattern.ply(2)
      events = Pattern.events(pattern)

      assert Enum.all?(events, fn e -> e.sample == 2 end)
      assert Enum.all?(events, fn e -> e.sound == "bd" end)
    end

    test "works with multiple events" do
      pattern = parse("bd sd hh") |> Pattern.ply(2)
      events = Pattern.events(pattern)

      assert length(events) == 6

      sounds = Enum.map(events, & &1.sound)
      assert Enum.count(sounds, &(&1 == "bd")) == 2
      assert Enum.count(sounds, &(&1 == "sd")) == 2
      assert Enum.count(sounds, &(&1 == "hh")) == 2
    end
  end

  describe "compress/3" do
    test "fits pattern into time segment" do
      pattern = parse("bd sd hh cp") |> Pattern.compress(0.25, 0.75)
      events = Pattern.events(pattern)

      assert Enum.all?(events, fn e -> e.time >= 0.25 and e.time < 0.75 end)
    end

    test "maintains event count" do
      pattern = parse("bd sd hh cp") |> Pattern.compress(0.25, 0.75)
      events = Pattern.events(pattern)

      assert length(events) == 4
    end

    test "scales times proportionally" do
      pattern = parse("bd sd") |> Pattern.compress(0.0, 0.5)
      events = Pattern.events(pattern)

      assert_in_delta Enum.at(events, 0).time, 0.0, 0.01
      assert_in_delta Enum.at(events, 1).time, 0.25, 0.01
    end

    test "scales durations proportionally" do
      pattern = parse("bd sd") |> Pattern.compress(0.0, 0.5)
      events = Pattern.events(pattern)

      assert_in_delta Enum.at(events, 0).duration, 0.25, 0.01
      assert_in_delta Enum.at(events, 1).duration, 0.25, 0.01
    end

    test "creates rhythmic gap" do
      pattern = parse("bd sd") |> Pattern.compress(0.25, 0.75)
      events = Pattern.events(pattern)

      assert Enum.all?(events, fn e -> e.time >= 0.25 end)
      assert Enum.all?(events, fn e -> e.time + e.duration <= 0.75 end)
    end

    test "maintains event properties" do
      pattern = parse("bd:3 sd:2") |> Pattern.compress(0.25, 0.75)
      events = Pattern.events(pattern)

      assert Enum.at(events, 0).sound == "bd"
      assert Enum.at(events, 0).sample == 3
      assert Enum.at(events, 1).sound == "sd"
      assert Enum.at(events, 1).sample == 2
    end
  end

  describe "zoom/3" do
    test "extracts and expands time segment" do
      pattern = parse("bd sd hh cp") |> Pattern.zoom(0.25, 0.75)
      events = Pattern.events(pattern)

      assert length(events) == 2
      sounds = Enum.map(events, & &1.sound)
      assert "sd" in sounds
      assert "hh" in sounds
    end

    test "expands extracted segment to full cycle" do
      pattern = parse("bd sd hh cp") |> Pattern.zoom(0.5, 1.0)
      events = Pattern.events(pattern)

      assert length(events) == 2
      assert_in_delta Enum.at(events, 0).time, 0.0, 0.01
      assert_in_delta Enum.at(events, 1).time, 0.5, 0.01
    end

    test "scales durations correctly" do
      pattern = parse("bd sd") |> Pattern.zoom(0.0, 0.5)
      events = Pattern.events(pattern)

      assert length(events) == 1
      assert_in_delta Enum.at(events, 0).duration, 1.0, 0.01
    end

    test "filters events outside window" do
      pattern = parse("bd sd hh cp") |> Pattern.zoom(0.25, 0.5)
      events = Pattern.events(pattern)

      assert length(events) == 1
      assert hd(events).sound == "sd"
    end

    test "maintains event properties" do
      pattern = parse("bd:1 sd:2 hh:3 cp:4") |> Pattern.zoom(0.25, 0.75)
      events = Pattern.events(pattern)

      assert Enum.at(events, 0).sound == "sd"
      assert Enum.at(events, 0).sample == 2
      assert Enum.at(events, 1).sound == "hh"
      assert Enum.at(events, 1).sample == 3
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
      events = Pattern.events(pattern)

      assert length(events) == 4

      sounds = Enum.map(events, & &1.sound)
      assert Enum.count(sounds, &(&1 == "bd")) == 2
      assert Enum.count(sounds, &(&1 == "sd")) == 2
    end

    test "linger(0.25) repeats first quarter 4 times" do
      pattern = parse("bd sd hh cp") |> Pattern.linger(0.25)
      events = Pattern.events(pattern)

      assert length(events) == 4
      assert Enum.all?(events, fn e -> e.sound == "bd" end)
    end

    test "linger(1.0) keeps pattern unchanged" do
      original = parse("bd sd hh cp")
      lingered = Pattern.linger(original, 1.0)

      assert length(Pattern.events(lingered)) == 4
      original_sounds = Enum.map(Pattern.events(original), & &1.sound)
      lingered_sounds = Enum.map(Pattern.events(lingered), & &1.sound)
      assert original_sounds == lingered_sounds
    end

    test "spaces repetitions correctly" do
      pattern = parse("bd sd") |> Pattern.linger(0.5)
      events = Pattern.events(pattern)

      assert length(events) == 2
      assert Enum.all?(events, fn e -> e.sound == "bd" end)

      times = Enum.map(events, & &1.time)
      assert_in_delta Enum.at(times, 0), 0.0, 0.01
      assert_in_delta Enum.at(times, 1), 0.5, 0.01
    end

    test "maintains event properties" do
      pattern = parse("bd:3 sd:2 hh:1 cp:0") |> Pattern.linger(0.5)
      events = Pattern.events(pattern)

      bd_events = Enum.filter(events, fn e -> e.sound == "bd" end)
      sd_events = Enum.filter(events, fn e -> e.sound == "sd" end)

      assert length(bd_events) == 2
      assert Enum.all?(bd_events, fn e -> e.sample == 3 end)

      assert length(sd_events) == 2
      assert Enum.all?(sd_events, fn e -> e.sample == 2 end)
    end

    test "linger(0.333) repeats first third 3 times" do
      pattern = parse("bd sd hh") |> Pattern.linger(0.333)
      events = Pattern.events(pattern)

      assert length(events) == 3
      assert Enum.all?(events, fn e -> e.sound == "bd" end)
    end
  end

  describe "fast/slow round trip" do
    test "fast/slow preserves structure" do
      pattern = parse("bd sd")

      transformed = pattern |> Pattern.fast(2) |> Pattern.slow(2)

      original_events = Pattern.query(pattern, 0)
      transformed_events = Pattern.query(transformed, 0)

      assert length(original_events) == length(transformed_events)

      Enum.zip(original_events, transformed_events)
      |> Enum.each(fn {orig, trans} ->
        assert orig.sound == trans.sound
        assert_in_delta orig.time, trans.time, 0.001
      end)
    end

    test "fast of slow of fast" do
      pattern =
        parse("bd sd hh cp")
        |> Pattern.fast(2)
        |> Pattern.slow(2)
        |> Pattern.fast(2)

      events = Pattern.query(pattern, 0)
      assert length(events) == 8
    end
  end
end
