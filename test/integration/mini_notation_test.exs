defmodule UzuPattern.Integration.MiniNotationTest do
  @moduledoc """
  Tests for mini-notation parsing through UzuPattern.parse/1.

  Covers: whitespace handling, sound names, bracket nesting, modifiers,
  rests, polyphony, alternation, elongation, euclidean syntax, parameters.
  """

  use ExUnit.Case, async: true

  alias UzuPattern.Pattern

  defp parse(str), do: UzuPattern.parse(str)
  defp parse_events(str), do: Pattern.query(parse(str), 0)

  # ============================================================================
  # Whitespace Handling
  # ============================================================================

  describe "whitespace handling" do
    test "leading whitespace is ignored" do
      events = parse_events("   bd sd")
      assert length(events) == 2
    end

    test "trailing whitespace is ignored" do
      events = parse_events("bd sd   ")
      assert length(events) == 2
    end

    test "multiple spaces between elements" do
      events = parse_events("bd    sd    hh")
      assert length(events) == 3
    end

    test "tabs are treated as whitespace" do
      events = parse_events("bd\tsd\thh")
      assert length(events) == 3
    end

    test "newlines in pattern" do
      events = parse_events("bd\nsd\nhh")
      assert length(events) == 3
    end

    test "mixed whitespace" do
      events = parse_events("bd \t\n sd")
      assert length(events) == 2
    end
  end

  # ============================================================================
  # Sound Names
  # ============================================================================

  describe "sound names" do
    test "single character sounds" do
      events = parse_events("a b c")
      assert Enum.map(events, & &1.sound) == ["a", "b", "c"]
    end

    test "numeric sounds" do
      events = parse_events("808 909 303")
      assert Enum.map(events, & &1.sound) == ["808", "909", "303"]
    end

    test "mixed alphanumeric" do
      events = parse_events("bd2 sd1 hh808")
      assert Enum.map(events, & &1.sound) == ["bd2", "sd1", "hh808"]
    end

    test "underscores in sound names" do
      events = parse_events("kick_drum snare_hit")
      sounds = Enum.map(events, & &1.sound)
      assert sounds == ["kick_drum", "snare_hit"]
    end
  end

  # ============================================================================
  # Bracket Nesting
  # ============================================================================

  describe "bracket nesting" do
    test "single element in brackets" do
      events = parse_events("[bd]")
      assert length(events) == 1
      assert hd(events).sound == "bd"
    end

    test "triple nested brackets" do
      events = parse_events("[[[bd]]]")
      assert length(events) == 1
      assert hd(events).sound == "bd"
    end

    test "mixed nesting depths" do
      events = parse_events("bd [sd [hh cp]] tom")
      assert length(events) == 5
    end

    test "adjacent bracket groups" do
      events = parse_events("[bd sd][hh cp]")
      assert length(events) == 4
    end

    test "adjacent bracket groups with space" do
      events = parse_events("[bd sd] [hh cp]")
      assert length(events) == 4
    end
  end

  # ============================================================================
  # Modifiers
  # ============================================================================

  describe "modifiers" do
    test "sample and repeat" do
      events = parse_events("bd:2*4")
      assert length(events) == 4
      assert Enum.all?(events, fn e -> e.sample == 2 end)
    end

    test "repeat on subdivision" do
      events = parse_events("[bd sd]*2")
      assert length(events) == 4
      sounds = Enum.map(events, & &1.sound)
      assert sounds == ["bd", "sd", "bd", "sd"]
    end

    test "division on subdivision" do
      pattern = parse("[bd sd hh cp]/2")
      events_0 = Pattern.query(pattern, 0)
      events_1 = Pattern.query(pattern, 1)

      assert length(events_0) == 2
      assert length(events_1) == 2
    end

    test "weight with multiple elements" do
      events = parse_events("bd@3 sd")
      assert length(events) == 2

      bd = Enum.find(events, &(&1.sound == "bd"))
      sd = Enum.find(events, &(&1.sound == "sd"))

      assert_in_delta bd.duration, 0.75, 0.01
      assert_in_delta sd.duration, 0.25, 0.01
    end

    test "probability on multiple elements" do
      events = parse_events("bd? sd? hh?")
      assert length(events) == 3
      assert Enum.all?(events, fn e -> e.params[:probability] == 0.5 end)
    end

    test "custom probability values" do
      events = parse_events("bd?0.25 sd?0.75")
      assert Enum.at(events, 0).params[:probability] == 0.25
      assert Enum.at(events, 1).params[:probability] == 0.75
    end
  end

  # ============================================================================
  # Rests
  # ============================================================================

  describe "rests" do
    test "single rest" do
      events = parse_events("~")
      assert events == []
    end

    test "rest in sequence" do
      events = parse_events("bd ~ sd")
      assert length(events) == 2
      sounds = Enum.map(events, & &1.sound)
      assert sounds == ["bd", "sd"]
    end

    test "multiple consecutive rests" do
      events = parse_events("bd ~ ~ ~ sd")
      assert length(events) == 2
    end

    test "rest in subdivision" do
      events = parse_events("[bd ~ sd ~]")
      assert length(events) == 2
    end

    test "all rests" do
      events = parse_events("~ ~ ~ ~")
      assert events == []
    end
  end

  # ============================================================================
  # Polyphony
  # ============================================================================

  describe "polyphony" do
    test "two-element chord" do
      events = parse_events("[bd,sd]")
      assert length(events) == 2
      assert Enum.all?(events, fn e -> e.time == 0.0 end)
    end

    test "three-element chord" do
      events = parse_events("[c3,e3,g3]")
      assert length(events) == 3
      assert Enum.all?(events, fn e -> e.time == 0.0 end)
    end

    test "chord with rest" do
      events = parse_events("[bd,~,sd]")
      assert length(events) == 2
    end

    test "chord in sequence" do
      events = parse_events("hh [bd,sd] hh")
      assert length(events) == 4
    end

    test "nested chord" do
      events = parse_events("[[bd,sd],hh]")
      assert length(events) == 3
    end
  end

  # ============================================================================
  # Alternation
  # ============================================================================

  describe "alternation" do
    test "two-element alternation" do
      pattern = parse("<bd sd>")

      events_0 = Pattern.query(pattern, 0)
      events_1 = Pattern.query(pattern, 1)

      assert hd(events_0).sound == "bd"
      assert hd(events_1).sound == "sd"
    end

    test "single-element alternation" do
      pattern = parse("<bd>")
      events = Pattern.query(pattern, 0)
      assert length(events) == 1
      assert hd(events).sound == "bd"
    end

    test "alternation with rests" do
      pattern = parse("<bd ~ sd>")

      events_0 = Pattern.query(pattern, 0)
      events_1 = Pattern.query(pattern, 1)
      events_2 = Pattern.query(pattern, 2)

      assert hd(events_0).sound == "bd"
      assert events_1 == []
      assert hd(events_2).sound == "sd"
    end

    test "nested alternation" do
      pattern = parse("<<a b> c>")

      events_0 = Pattern.query(pattern, 0)
      events_1 = Pattern.query(pattern, 1)

      assert hd(events_0).sound == "a"
      assert hd(events_1).sound == "c"
    end

    test "alternation in sequence" do
      pattern = parse("bd <sd hh> cp")

      events_0 = Pattern.query(pattern, 0)
      events_1 = Pattern.query(pattern, 1)

      sounds_0 = Enum.map(events_0, & &1.sound)
      sounds_1 = Enum.map(events_1, & &1.sound)

      assert "sd" in sounds_0
      assert "hh" in sounds_1
    end
  end

  # ============================================================================
  # Elongation
  # ============================================================================

  describe "elongation" do
    test "single elongation" do
      events = parse_events("bd _ sd")
      assert length(events) == 2

      bd = Enum.find(events, &(&1.sound == "bd"))
      assert_in_delta bd.duration, 0.666, 0.01
    end

    test "multiple elongations" do
      events = parse_events("bd _ _ _ sd")
      assert length(events) == 2

      bd = Enum.find(events, &(&1.sound == "bd"))
      assert_in_delta bd.duration, 0.8, 0.01
    end

    test "elongation at start has no effect" do
      events = parse_events("_ bd sd")
      assert length(events) == 2
    end

    test "consecutive elements with elongations" do
      events = parse_events("bd _ sd _")
      assert length(events) == 2

      bd = Enum.find(events, &(&1.sound == "bd"))
      sd = Enum.find(events, &(&1.sound == "sd"))

      assert_in_delta bd.duration, 0.5, 0.01
      assert_in_delta sd.duration, 0.5, 0.01
    end
  end

  # ============================================================================
  # Euclidean Syntax
  # ============================================================================

  describe "euclidean syntax" do
    test "basic euclidean" do
      events = parse_events("bd(3,8)")
      assert length(events) == 3
    end

    test "euclidean with offset" do
      events1 = parse_events("bd(3,8,0)")
      events2 = parse_events("bd(3,8,1)")

      times1 = Enum.map(events1, & &1.time)
      times2 = Enum.map(events2, & &1.time)

      assert times1 != times2
    end

    test "euclidean in sequence" do
      events = parse_events("hh bd(3,8) hh")
      assert length(events) == 5
    end

    test "euclidean with sample" do
      events = parse_events("bd:2(3,8)")
      assert length(events) == 3
      assert Enum.all?(events, fn e -> e.sample == 2 end)
    end
  end

  # ============================================================================
  # Parameters
  # ============================================================================

  describe "parameter syntax" do
    test "single parameter" do
      events = parse_events("bd|gain:0.5")
      assert length(events) == 1
      assert hd(events).params[:gain] == 0.5
    end

    test "multiple parameters" do
      events = parse_events("bd|gain:0.5|speed:2")
      [event] = events
      assert event.params[:gain] == 0.5
      assert event.params[:speed] == 2.0
    end

    test "parameter on subdivision" do
      events = parse_events("[bd sd]|gain:0.5")
      assert Enum.all?(events, fn e -> e.params[:gain] == 0.5 end)
    end

    test "integer parameter values" do
      events = parse_events("bd|cut:1")
      assert hd(events).params[:cut] == 1
    end

    test "negative parameter values" do
      events = parse_events("bd|pan:-0.5")
      assert hd(events).params[:pan] == -0.5
    end
  end

  # ============================================================================
  # Period Separator
  # ============================================================================

  describe "period separator" do
    test "period creates subdivision" do
      events = parse_events("bd . sd hh")
      assert length(events) == 3
    end

    test "multiple periods" do
      events = parse_events("bd . sd . hh cp")
      assert length(events) == 4
    end
  end

  # ============================================================================
  # Complex Patterns
  # ============================================================================

  describe "complex realistic patterns" do
    test "drum pattern with subdivision" do
      events = parse_events("bd [hh hh] sd [hh hh]")
      assert length(events) == 6
    end

    test "pattern with all features" do
      pattern = parse("[bd:1 sd]*2 <hh cp>")

      events_0 = Pattern.query(pattern, 0)
      events_1 = Pattern.query(pattern, 1)

      assert length(events_0) == 5
      assert length(events_1) == 5
    end

    test "layered drum pattern" do
      events = parse_events("[bd, hh hh hh hh] [sd, hh hh hh hh]")
      assert length(events) == 10
    end

    test "polyrhythm" do
      events = parse_events("{bd bd bd, hh hh hh hh hh}")
      assert length(events) == 8
    end
  end

  # ============================================================================
  # Skip: Empty brackets not supported
  # ============================================================================

  @tag :skip
  test "empty brackets" do
    events = parse_events("bd [] sd")
    assert length(events) >= 2
  end
end
