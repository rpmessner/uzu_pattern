defmodule UzuPattern.Integration.MiniNotationTest do
  @moduledoc """
  Tests for mini-notation parsing through UzuPattern.parse/1.

  Covers: whitespace handling, sound names, bracket nesting, modifiers,
  rests, polyphony, alternation, elongation, euclidean syntax, parameters.

  Follows Strudel test conventions - focus on behavior (values, timing).
  """

  use ExUnit.Case, async: true

  alias UzuPattern.Hap
  alias UzuPattern.Pattern

  defp parse(str), do: UzuPattern.parse(str)
  defp parse_events(str), do: Pattern.query(parse(str), 0)

  # Strudel-style helpers
  defp sounds(haps), do: Enum.map(haps, &Hap.sound/1)
  defp times(haps), do: Enum.map(haps, & &1.part.begin)
  defp durations(haps), do: Enum.map(haps, &(&1.part.end - &1.part.begin))

  # ============================================================================
  # Whitespace Handling
  # ============================================================================

  describe "whitespace handling" do
    test "leading whitespace is ignored" do
      haps = parse_events("   bd sd")
      assert length(haps) == 2
    end

    test "trailing whitespace is ignored" do
      haps = parse_events("bd sd   ")
      assert length(haps) == 2
    end

    test "multiple spaces between elements" do
      haps = parse_events("bd    sd    hh")
      assert length(haps) == 3
    end

    test "tabs are treated as whitespace" do
      haps = parse_events("bd\tsd\thh")
      assert length(haps) == 3
    end

    test "newlines in pattern" do
      haps = parse_events("bd\nsd\nhh")
      assert length(haps) == 3
    end

    test "mixed whitespace" do
      haps = parse_events("bd \t\n sd")
      assert length(haps) == 2
    end
  end

  # ============================================================================
  # Sound Names
  # ============================================================================

  describe "sound names" do
    test "single character sounds" do
      haps = parse_events("a b c")
      assert sounds(haps) == ["a", "b", "c"]
    end

    test "numeric sounds" do
      haps = parse_events("808 909 303")
      assert sounds(haps) == ["808", "909", "303"]
    end

    test "mixed alphanumeric" do
      haps = parse_events("bd2 sd1 hh808")
      assert sounds(haps) == ["bd2", "sd1", "hh808"]
    end

    test "underscores in sound names" do
      haps = parse_events("kick_drum snare_hit")
      assert sounds(haps) == ["kick_drum", "snare_hit"]
    end
  end

  # ============================================================================
  # Bracket Nesting
  # ============================================================================

  describe "bracket nesting" do
    test "single element in brackets" do
      haps = parse_events("[bd]")
      assert length(haps) == 1
      assert Hap.sound(hd(haps)) == "bd"
    end

    test "triple nested brackets" do
      haps = parse_events("[[[bd]]]")
      assert length(haps) == 1
      assert Hap.sound(hd(haps)) == "bd"
    end

    test "mixed nesting depths" do
      haps = parse_events("bd [sd [hh cp]] tom")
      assert length(haps) == 5
    end

    test "adjacent bracket groups" do
      haps = parse_events("[bd sd][hh cp]")
      assert length(haps) == 4
    end

    test "adjacent bracket groups with space" do
      haps = parse_events("[bd sd] [hh cp]")
      assert length(haps) == 4
    end
  end

  # ============================================================================
  # Modifiers
  # ============================================================================

  describe "modifiers" do
    test "sample and repeat" do
      haps = parse_events("bd:2*4")
      assert length(haps) == 4
      assert Enum.all?(haps, &(Hap.sample(&1) == 2))
    end

    test "repeat on subdivision" do
      haps = parse_events("[bd sd]*2")
      assert length(haps) == 4
      assert sounds(haps) == ["bd", "sd", "bd", "sd"]
    end

    test "division on subdivision" do
      pattern = parse("[bd sd hh cp]/2")
      haps_0 = Pattern.query(pattern, 0)
      haps_1 = Pattern.query(pattern, 1)

      assert length(haps_0) == 2
      assert length(haps_1) == 2
    end

    test "weight with multiple elements" do
      haps = parse_events("bd@3 sd")
      assert length(haps) == 2

      bd = Enum.find(haps, &(Hap.sound(&1) == "bd"))
      sd = Enum.find(haps, &(Hap.sound(&1) == "sd"))

      bd_dur = bd.part.end - bd.part.begin
      sd_dur = sd.part.end - sd.part.begin
      assert_in_delta bd_dur, 0.75, 0.01
      assert_in_delta sd_dur, 0.25, 0.01
    end

    test "probability on multiple elements" do
      haps = parse_events("bd? sd? hh?")
      assert length(haps) == 3
      assert Enum.all?(haps, &(&1.value[:probability] == 0.5))
    end

    test "custom probability values" do
      haps = parse_events("bd?0.25 sd?0.75")
      assert Enum.at(haps, 0).value[:probability] == 0.25
      assert Enum.at(haps, 1).value[:probability] == 0.75
    end
  end

  # ============================================================================
  # Rests
  # ============================================================================

  describe "rests" do
    test "single rest" do
      haps = parse_events("~")
      assert haps == []
    end

    test "rest in sequence" do
      haps = parse_events("bd ~ sd")
      assert length(haps) == 2
      assert sounds(haps) == ["bd", "sd"]
    end

    test "multiple consecutive rests" do
      haps = parse_events("bd ~ ~ ~ sd")
      assert length(haps) == 2
    end

    test "rest in subdivision" do
      haps = parse_events("[bd ~ sd ~]")
      assert length(haps) == 2
    end

    test "all rests" do
      haps = parse_events("~ ~ ~ ~")
      assert haps == []
    end
  end

  # ============================================================================
  # Polyphony
  # ============================================================================

  describe "polyphony" do
    test "two-element chord" do
      haps = parse_events("[bd,sd]")
      assert length(haps) == 2
      assert Enum.all?(times(haps), &(&1 == 0.0))
    end

    test "three-element chord" do
      haps = parse_events("[c3,e3,g3]")
      assert length(haps) == 3
      assert Enum.all?(times(haps), &(&1 == 0.0))
    end

    test "chord with rest" do
      haps = parse_events("[bd,~,sd]")
      assert length(haps) == 2
    end

    test "chord in sequence" do
      haps = parse_events("hh [bd,sd] hh")
      assert length(haps) == 4
    end

    test "nested chord" do
      haps = parse_events("[[bd,sd],hh]")
      assert length(haps) == 3
    end
  end

  # ============================================================================
  # Alternation
  # ============================================================================

  describe "alternation" do
    test "two-element alternation" do
      pattern = parse("<bd sd>")

      haps_0 = Pattern.query(pattern, 0)
      haps_1 = Pattern.query(pattern, 1)

      assert Hap.sound(hd(haps_0)) == "bd"
      assert Hap.sound(hd(haps_1)) == "sd"
    end

    test "single-element alternation" do
      pattern = parse("<bd>")
      haps = Pattern.query(pattern, 0)
      assert length(haps) == 1
      assert Hap.sound(hd(haps)) == "bd"
    end

    test "alternation with rests" do
      pattern = parse("<bd ~ sd>")

      haps_0 = Pattern.query(pattern, 0)
      haps_1 = Pattern.query(pattern, 1)
      haps_2 = Pattern.query(pattern, 2)

      assert Hap.sound(hd(haps_0)) == "bd"
      assert haps_1 == []
      assert Hap.sound(hd(haps_2)) == "sd"
    end

    test "nested alternation" do
      pattern = parse("<<a b> c>")

      haps_0 = Pattern.query(pattern, 0)
      haps_1 = Pattern.query(pattern, 1)

      assert Hap.sound(hd(haps_0)) == "a"
      assert Hap.sound(hd(haps_1)) == "c"
    end

    test "alternation in sequence" do
      pattern = parse("bd <sd hh> cp")

      haps_0 = Pattern.query(pattern, 0)
      haps_1 = Pattern.query(pattern, 1)

      sounds_0 = sounds(haps_0)
      sounds_1 = sounds(haps_1)

      assert "sd" in sounds_0
      assert "hh" in sounds_1
    end

    test "alternation with repeat modifier" do
      pattern = parse("<bd sd>*2")

      haps = Pattern.query(pattern, 0)
      assert length(haps) == 2
      assert sounds(haps) == ["bd", "sd"]
    end

    test "alternation with division modifier" do
      pattern = parse("<bd sd>/2")

      # /2 slows alternation - events occur at stretched times
      haps_0 = Pattern.query(pattern, 0)
      haps_2 = Pattern.query(pattern, 2)
      haps_4 = Pattern.query(pattern, 4)

      # bd at cycle 0, sd at cycle 2, bd at cycle 4
      assert sounds(haps_0) == ["bd"]
      assert sounds(haps_2) == ["sd"]
      assert sounds(haps_4) == ["bd"]
    end

    test "alternation with subdivision and repeat" do
      pattern = parse("<[bd sd] [hh sd]>*2")

      haps = Pattern.query(pattern, 0)
      assert length(haps) == 4
      assert sounds(haps) == ["bd", "sd", "hh", "sd"]

      # Timing: each subdivision takes half a cycle
      assert_in_delta Enum.at(times(haps), 0), 0.0, 0.01
      assert_in_delta Enum.at(times(haps), 1), 0.25, 0.01
      assert_in_delta Enum.at(times(haps), 2), 0.5, 0.01
      assert_in_delta Enum.at(times(haps), 3), 0.75, 0.01
    end
  end

  # ============================================================================
  # Elongation
  # ============================================================================

  describe "elongation" do
    test "single elongation" do
      haps = parse_events("bd _ sd")
      assert length(haps) == 2

      bd = Enum.find(haps, &(Hap.sound(&1) == "bd"))
      bd_dur = bd.part.end - bd.part.begin
      assert_in_delta bd_dur, 0.666, 0.01
    end

    test "multiple elongations" do
      haps = parse_events("bd _ _ _ sd")
      assert length(haps) == 2

      bd = Enum.find(haps, &(Hap.sound(&1) == "bd"))
      bd_dur = bd.part.end - bd.part.begin
      assert_in_delta bd_dur, 0.8, 0.01
    end

    test "elongation at start has no effect" do
      haps = parse_events("_ bd sd")
      assert length(haps) == 2
    end

    test "consecutive elements with elongations" do
      haps = parse_events("bd _ sd _")
      assert length(haps) == 2

      bd = Enum.find(haps, &(Hap.sound(&1) == "bd"))
      sd = Enum.find(haps, &(Hap.sound(&1) == "sd"))

      assert_in_delta bd.part.end - bd.part.begin, 0.5, 0.01
      assert_in_delta sd.part.end - sd.part.begin, 0.5, 0.01
    end
  end

  # ============================================================================
  # Euclidean Syntax
  # ============================================================================

  describe "euclidean syntax" do
    test "basic euclidean" do
      haps = parse_events("bd(3,8)")
      assert length(haps) == 3
    end

    test "euclidean with offset" do
      haps1 = parse_events("bd(3,8,0)")
      haps2 = parse_events("bd(3,8,1)")

      times1 = times(haps1)
      times2 = times(haps2)

      assert times1 != times2
    end

    test "euclidean in sequence" do
      haps = parse_events("hh bd(3,8) hh")
      assert length(haps) == 5
    end

    test "euclidean with sample" do
      haps = parse_events("bd:2(3,8)")
      assert length(haps) == 3
      assert Enum.all?(haps, &(Hap.sample(&1) == 2))
    end
  end

  # ============================================================================
  # Parameters
  # ============================================================================

  describe "parameter syntax" do
    test "single parameter" do
      haps = parse_events("bd|gain:0.5")
      assert length(haps) == 1
      assert hd(haps).value[:gain] == 0.5
    end

    test "multiple parameters" do
      haps = parse_events("bd|gain:0.5|speed:2")
      [hap] = haps
      assert hap.value[:gain] == 0.5
      assert hap.value[:speed] == 2.0
    end

    test "parameter on subdivision" do
      haps = parse_events("[bd sd]|gain:0.5")
      assert Enum.all?(haps, &(&1.value[:gain] == 0.5))
    end

    test "integer parameter values" do
      haps = parse_events("bd|cut:1")
      assert hd(haps).value[:cut] == 1
    end

    test "negative parameter values" do
      haps = parse_events("bd|pan:-0.5")
      assert hd(haps).value[:pan] == -0.5
    end
  end

  # ============================================================================
  # Period Separator
  # ============================================================================

  describe "period separator" do
    test "period creates subdivision" do
      haps = parse_events("bd . sd hh")
      assert length(haps) == 3
    end

    test "multiple periods" do
      haps = parse_events("bd . sd . hh cp")
      assert length(haps) == 4
    end
  end

  # ============================================================================
  # Complex Patterns
  # ============================================================================

  describe "complex realistic patterns" do
    test "drum pattern with subdivision" do
      haps = parse_events("bd [hh hh] sd [hh hh]")
      assert length(haps) == 6
    end

    test "pattern with all features" do
      pattern = parse("[bd:1 sd]*2 <hh cp>")

      haps_0 = Pattern.query(pattern, 0)
      haps_1 = Pattern.query(pattern, 1)

      assert length(haps_0) == 5
      assert length(haps_1) == 5
    end

    test "layered drum pattern" do
      haps = parse_events("[bd, hh hh hh hh] [sd, hh hh hh hh]")
      assert length(haps) == 10
    end

    test "polyrhythm" do
      haps = parse_events("{bd bd bd, hh hh hh hh hh}")
      assert length(haps) == 8
    end
  end

  # ============================================================================
  # Pattern Combinations (modifiers on structures)
  # ============================================================================

  describe "pattern combinations" do
    test "subdivision repeat on alternation elements" do
      # Each alternation element is a repeated subdivision
      pattern = parse("<[bd sd]*2 [hh cp]*2>")

      haps_0 = Pattern.query(pattern, 0)
      haps_1 = Pattern.query(pattern, 1)

      assert length(haps_0) == 4
      assert sounds(haps_0) == ["bd", "sd", "bd", "sd"]

      assert length(haps_1) == 4
      assert sounds(haps_1) == ["hh", "cp", "hh", "cp"]
    end

    test "nested modifiers" do
      # [[bd sd]*2]*2 = 8 events
      pattern = parse("[[bd sd]*2]*2")
      haps = Pattern.query(pattern, 0)

      assert length(haps) == 8
      assert sounds(haps) == ["bd", "sd", "bd", "sd", "bd", "sd", "bd", "sd"]
    end

    test "alternation inside subdivision with repeat" do
      # [<bd sd> hh]*2 - the *2 speeds up the whole subdivision,
      # which also speeds up the internal alternation
      pattern = parse("[<bd sd> hh]*2")

      haps_0 = Pattern.query(pattern, 0)

      assert length(haps_0) == 4
      # First iteration: bd hh, second iteration: sd hh
      # The alternation advances each time through
      assert sounds(haps_0) == ["bd", "hh", "sd", "hh"]
    end

    test "polyphony with alternation" do
      # Stack of alternations
      pattern = parse("[<bd sd>, <hh cp>]")

      haps_0 = Pattern.query(pattern, 0)
      haps_1 = Pattern.query(pattern, 1)

      # Cycle 0: bd and hh at same time
      assert length(haps_0) == 2
      assert Enum.sort(sounds(haps_0)) == ["bd", "hh"]

      # Cycle 1: sd and cp at same time
      assert length(haps_1) == 2
      assert Enum.sort(sounds(haps_1)) == ["cp", "sd"]
    end

    test "alternation with division inside repeat" do
      # <bd/2 sd>*2 - bd spans 2 cycles at half speed, but whole alt is doubled
      pattern = parse("<bd sd>*4")
      haps = Pattern.query(pattern, 0)

      # *4 means 4 iterations per cycle = 4 events
      assert length(haps) == 4
      assert sounds(haps) == ["bd", "sd", "bd", "sd"]
    end

    test "deeply nested structures" do
      # [<[bd sd] hh> cp]
      pattern = parse("[<[bd sd] hh> cp]")

      haps_0 = Pattern.query(pattern, 0)
      haps_1 = Pattern.query(pattern, 1)

      # Cycle 0: [bd sd] and cp
      assert length(haps_0) == 3
      # Cycle 1: hh and cp
      assert length(haps_1) == 2
    end

    test "weight with alternation" do
      pattern = parse("<bd@2 sd>")

      haps_0 = Pattern.query(pattern, 0)

      bd = Enum.find(haps_0, &(Hap.sound(&1) == "bd"))
      bd_dur = bd.part.end - bd.part.begin
      # bd should take full cycle in cycle 0
      assert_in_delta bd_dur, 1.0, 0.01
    end

    test "multiple alternations in sequence" do
      pattern = parse("<bd sd> <hh cp>")

      haps_0 = Pattern.query(pattern, 0)
      haps_1 = Pattern.query(pattern, 1)

      assert sounds(haps_0) == ["bd", "hh"]
      assert sounds(haps_1) == ["sd", "cp"]
    end
  end

  # ============================================================================
  # Skip: Empty brackets not supported
  # ============================================================================

  @tag :skip
  test "empty brackets" do
    haps = parse_events("bd [] sd")
    assert length(haps) >= 2
  end
end
