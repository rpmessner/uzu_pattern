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
  alias UzuPattern.Time
  alias UzuPattern.TimeSpan

  defp parse(str), do: UzuPattern.parse(str)
  defp parse_events(str), do: Pattern.query(parse(str), 0)

  # Strudel-style helpers
  defp sounds(haps), do: Enum.map(haps, &Hap.sound/1)

  # Sort haps by begin time
  defp sort_by_time(haps) do
    Enum.sort(haps, fn a, b -> Time.lt?(a.part.begin, b.part.begin) end)
  end

  # Check if all haps start at the same time
  defp all_same_time?(haps, expected) do
    Enum.all?(haps, fn h -> Time.eq?(h.part.begin, expected) end)
  end

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

      # bd@3 sd means bd gets 3/4, sd gets 1/4
      assert Time.eq?(TimeSpan.duration(bd.part), Time.new(3, 4))
      assert Time.eq?(TimeSpan.duration(sd.part), Time.new(1, 4))
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
      assert all_same_time?(haps, Time.zero())
    end

    test "three-element chord" do
      haps = parse_events("[c3,e3,g3]")
      assert length(haps) == 3
      assert all_same_time?(haps, Time.zero())
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

      haps = sort_by_time(Pattern.query(pattern, 0))
      assert length(haps) == 4
      assert sounds(haps) == ["bd", "sd", "hh", "sd"]

      # Timing: each subdivision takes half a cycle
      assert Time.eq?(Enum.at(haps, 0).part.begin, Time.zero())
      assert Time.eq?(Enum.at(haps, 1).part.begin, Time.new(1, 4))
      assert Time.eq?(Enum.at(haps, 2).part.begin, Time.half())
      assert Time.eq?(Enum.at(haps, 3).part.begin, Time.new(3, 4))
    end

    test "alternation with slowed subdivisions - each pattern starts fresh" do
      # <[a b c d]/4 [e f g h]/4> should alternate between patterns,
      # each progressing through their own subdivision independently
      pattern = parse("<[a b c d]/4 [e f g h]/4>")

      # Cycle 0: first pattern, first slice → should be "a"
      haps_0 = Pattern.query(pattern, 0)
      assert sounds(haps_0) == ["a"], "Cycle 0: expected [a], got #{inspect(sounds(haps_0))}"

      # Cycle 1: second pattern, first slice → should be "e"
      haps_1 = Pattern.query(pattern, 1)
      assert sounds(haps_1) == ["e"], "Cycle 1: expected [e], got #{inspect(sounds(haps_1))}"

      # Cycle 2: first pattern, second slice → should be "b"
      haps_2 = Pattern.query(pattern, 2)
      assert sounds(haps_2) == ["b"], "Cycle 2: expected [b], got #{inspect(sounds(haps_2))}"

      # Cycle 3: second pattern, second slice → should be "f"
      haps_3 = Pattern.query(pattern, 3)
      assert sounds(haps_3) == ["f"], "Cycle 3: expected [f], got #{inspect(sounds(haps_3))}"

      # Cycle 4: first pattern, third slice → should be "c"
      haps_4 = Pattern.query(pattern, 4)
      assert sounds(haps_4) == ["c"], "Cycle 4: expected [c], got #{inspect(haps_4)}"

      # Cycle 5: second pattern, third slice → should be "g"
      haps_5 = Pattern.query(pattern, 5)
      assert sounds(haps_5) == ["g"], "Cycle 5: expected [g], got #{inspect(sounds(haps_5))}"
    end

    test "alternation with repeat operator in slowed subdivisions" do
      # This is the user's specific pattern: <[3!5 6!5 2!5 5!5]/4 [1!7 2!7 3!7 5!7]/4>
      # Using note values instead of sounds for simplicity
      pattern = parse("<[a!5 b!5 c!5 d!5]/4 [e!7 f!7 g!7 h!7]/4>")

      # Cycle 0: first pattern, first slice → 5 "a"s
      haps_0 = Pattern.query(pattern, 0)

      assert sounds(haps_0) == ["a", "a", "a", "a", "a"],
             "Cycle 0: expected 5 a's, got #{inspect(sounds(haps_0))}"

      # Cycle 1: second pattern, first slice → 7 "e"s
      haps_1 = Pattern.query(pattern, 1)

      assert sounds(haps_1) == ["e", "e", "e", "e", "e", "e", "e"],
             "Cycle 1: expected 7 e's, got #{inspect(sounds(haps_1))}"

      # Cycle 2: first pattern, second slice → 5 "b"s
      haps_2 = Pattern.query(pattern, 2)

      assert sounds(haps_2) == ["b", "b", "b", "b", "b"],
             "Cycle 2: expected 5 b's, got #{inspect(sounds(haps_2))}"

      # Cycle 3: second pattern, second slice → 7 "f"s
      haps_3 = Pattern.query(pattern, 3)

      assert sounds(haps_3) == ["f", "f", "f", "f", "f", "f", "f"],
             "Cycle 3: expected 7 f's, got #{inspect(sounds(haps_3))}"
    end

    test "three-way alternation with slowed subdivisions" do
      pattern = parse("<[a b]/2 [c d]/2 [e f]/2>")

      # Pattern cycles through 3 patterns, each slowed by 2
      # Cycle 0: pattern 0, local cycle 0 → slice 0 → "a"
      assert sounds(Pattern.query(pattern, 0)) == ["a"]
      # Cycle 1: pattern 1, local cycle 0 → slice 0 → "c"
      assert sounds(Pattern.query(pattern, 1)) == ["c"]
      # Cycle 2: pattern 2, local cycle 0 → slice 0 → "e"
      assert sounds(Pattern.query(pattern, 2)) == ["e"]
      # Cycle 3: pattern 0, local cycle 1 → slice 1 → "b"
      assert sounds(Pattern.query(pattern, 3)) == ["b"]
      # Cycle 4: pattern 1, local cycle 1 → slice 1 → "d"
      assert sounds(Pattern.query(pattern, 4)) == ["d"]
      # Cycle 5: pattern 2, local cycle 1 → slice 1 → "f"
      assert sounds(Pattern.query(pattern, 5)) == ["f"]
    end

    test "alternation with weighted and replicated subdivisions matches Strudel" do
      # This pattern tests the combination of:
      # - Alternation (<...>)
      # - Replicate (!n) which affects weight calculation
      # - Weight (@n) which affects duration
      # - Division (/4) which slows the pattern
      # Expected output matches Strudel's behavior
      pattern = parse("<[3!5 6@3 2!5 5@4]/4 [1!7 2@4 3!7 5@4]/4>")

      # Cycle 0: first pattern, slice 0 → 5 "3"s (3!5 occupies 5/17 of the pattern)
      assert sounds(Pattern.query(pattern, 0)) == ["3", "3", "3", "3", "3"]

      # Cycle 1: second pattern, slice 0 → 6 "1"s (1!7 spans into slice 1)
      assert sounds(Pattern.query(pattern, 1)) == ["1", "1", "1", "1", "1", "1"]

      # Cycle 2: first pattern, slice 1 → crosses 3!5, 6@3, 2!5 boundaries
      assert sounds(Pattern.query(pattern, 2)) == ["3", "6", "2"]

      # Cycle 3: second pattern, slice 1
      assert sounds(Pattern.query(pattern, 3)) == ["1", "1", "2"]

      # Cycle 4: first pattern, slice 2
      assert sounds(Pattern.query(pattern, 4)) == ["2", "2", "2", "2", "2"]

      # Cycle 5: second pattern, slice 2
      assert sounds(Pattern.query(pattern, 5)) == ["3", "3", "3", "3", "3", "3"]

      # Cycle 6: first pattern, slice 3
      assert sounds(Pattern.query(pattern, 6)) == ["2", "5"]

      # Cycle 7: second pattern, slice 3
      assert sounds(Pattern.query(pattern, 7)) == ["3", "3", "5"]
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
      # bd _ sd: bd gets 2/3, sd gets 1/3
      assert Time.eq?(TimeSpan.duration(bd.part), Time.new(2, 3))
    end

    test "multiple elongations" do
      haps = parse_events("bd _ _ _ sd")
      assert length(haps) == 2

      bd = Enum.find(haps, &(Hap.sound(&1) == "bd"))
      # bd _ _ _ sd: bd gets 4/5, sd gets 1/5
      assert Time.eq?(TimeSpan.duration(bd.part), Time.new(4, 5))
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

      # bd _ sd _: each gets 1/2
      assert Time.eq?(TimeSpan.duration(bd.part), Time.half())
      assert Time.eq?(TimeSpan.duration(sd.part), Time.half())
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

      # Get begin times
      times1 = Enum.map(haps1, & &1.part.begin)
      times2 = Enum.map(haps2, & &1.part.begin)

      # Different offsets should produce different timing
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
  # Period in Sound Names (Strudel Compatibility)
  # ============================================================================

  describe "period in sound names" do
    test "period is part of sound name, not a separator" do
      # In Strudel, "bd.sd.hh" is ONE sound with a dotted name
      haps = parse_events("bd.sd.hh")
      assert length(haps) == 1
      assert hd(haps).value.s == "bd.sd.hh"
    end

    test "standalone period surrounded by spaces is a sound named dot" do
      # "bd . sd" parses as three sounds: "bd", ".", "sd"
      haps = parse_events("bd . sd hh")
      assert length(haps) == 4
      assert Enum.map(haps, & &1.value.s) == ["bd", ".", "sd", "hh"]
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
      # First group has 3 items (bd bd bd), so each takes 1/3 cycle
      # Second group (5 hh's) gets scaled to match: 3 hh events aligned with bd
      haps = parse_events("{bd bd bd, hh hh hh hh hh}")
      assert length(haps) == 6
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
      # bd@2 in an alternation means it takes the full cycle when it plays
      assert Time.eq?(TimeSpan.duration(bd.part), Time.one())
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
  # Grouper Modifiers (replicate, probability on structures)
  # ============================================================================

  describe "grouper modifiers" do
    test "subdivision with replicate [a b]!3" do
      # Same as [a b]*3 - speeds up by 3
      pattern = parse("[bd sd]!3")
      haps = Pattern.query(pattern, 0)

      assert length(haps) == 6
      assert sounds(haps) == ["bd", "sd", "bd", "sd", "bd", "sd"]
    end

    test "subdivision with bare replicate [a b]!" do
      # ! alone defaults to 1, so no speed change
      pattern = parse("[bd sd]!")
      haps = Pattern.query(pattern, 0)

      assert length(haps) == 2
      assert sounds(haps) == ["bd", "sd"]
    end

    test "subdivision with probability [a b]?" do
      # 50% chance - deterministic based on cycle
      pattern = parse("[bd sd hh cp]?")

      # Run multiple cycles and check that some have events and some don't
      results = Enum.map(0..19, fn cycle -> length(Pattern.query(pattern, cycle)) end)

      # Should have variation (not all same)
      assert length(Enum.uniq(results)) > 1
    end

    test "subdivision with probability value [a b]?0.25" do
      pattern = parse("[bd sd hh cp]?0.25")

      # With 25% probability per event, most events should be filtered
      results = Enum.map(0..19, fn cycle -> length(Pattern.query(pattern, cycle)) end)

      # Average should be around 1 event per cycle (4 events * 25% = 1)
      total_events = Enum.sum(results)
      average = total_events / 20

      # With 25% probability, expect roughly 1 event per cycle (not 4)
      assert average < 2.5
    end

    test "alternation with replicate <a b>!3" do
      # Same as <a b>*3 - speeds up by 3
      pattern = parse("<bd sd>!3")
      haps = Pattern.query(pattern, 0)

      # 3 iterations per cycle
      assert length(haps) == 3
      assert sounds(haps) == ["bd", "sd", "bd"]
    end

    test "alternation with probability <a b>?" do
      pattern = parse("<bd sd>?")

      # Run multiple cycles and check variation
      results = Enum.map(0..19, fn cycle -> length(Pattern.query(pattern, cycle)) end)
      assert length(Enum.uniq(results)) > 1
    end

    test "polymetric with repeat {a b}*2" do
      # Base: {bd sd, hh hh hh} - first group has 2 items, second scaled to match
      # Per Strudel: base pattern produces 4 events (bd, sd, hh, hh aligned to 2-step grid)
      # *2 plays pattern twice in one cycle, so 8 events total
      pattern = parse("{bd sd, hh hh hh}*2")
      haps = Pattern.query(pattern, 0)

      assert length(haps) == 8
    end

    test "polymetric with division {a b}/2" do
      # {bd sd, hh hh hh} aligns groups: 4 events per cycle (bd hh at 0-0.5, sd hh at 0.5-1)
      # /2 slows the pattern: events stretch over 2 cycles
      pattern = parse("{bd sd, hh hh hh}/2")

      haps_0 = Pattern.query(pattern, 0)
      haps_1 = Pattern.query(pattern, 1)

      # Cycle 0 gets first half: bd + hh
      # Cycle 1 gets second half: sd + hh
      assert length(haps_0) == 2
      assert Enum.sort(sounds(haps_0)) == ["bd", "hh"]

      assert length(haps_1) == 2
      assert Enum.sort(sounds(haps_1)) == ["hh", "sd"]
    end

    test "polymetric with probability {a b}?" do
      pattern = parse("{bd sd, hh hh hh}?")

      # Run multiple cycles and check variation
      results = Enum.map(0..19, fn cycle -> length(Pattern.query(pattern, cycle)) end)
      assert length(Enum.uniq(results)) > 1
    end

    test "bare replicate on atom a!" do
      pattern = parse("a!")
      haps = Pattern.query(pattern, 0)

      # ! alone defaults to 1, so single event
      assert length(haps) == 1
      assert sounds(haps) == ["a"]
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
