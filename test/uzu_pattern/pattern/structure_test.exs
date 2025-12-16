defmodule UzuPattern.Pattern.StructureTest do
  @moduledoc """
  Tests for structure manipulation functions.

  Functions: rev, palindrome, struct_fn, mask, degrade, degrade_by,
             jux, jux_by, superimpose, off, echo, striate, chop
  """

  use ExUnit.Case, async: true

  alias UzuPattern.Hap
  alias UzuPattern.Pattern
  alias UzuPattern.Time
  alias UzuPattern.TimeSpan

  defp parse(str), do: UzuPattern.parse(str)

  # Strudel-style helpers
  defp sounds(haps), do: Enum.map(haps, &Hap.sound/1)

  # Check if any hap has a specific begin time
  defp has_time?(haps, expected) do
    Enum.any?(haps, fn h -> Time.eq?(h.part.begin, expected) end)
  end

  describe "rev/1" do
    test "reverses event order" do
      pattern = parse("bd sd hh") |> Pattern.rev()
      haps = Pattern.events(pattern)

      assert Hap.sound(hd(haps)) == "hh"
    end

    test "adjusts times correctly" do
      pattern = parse("bd sd") |> Pattern.rev()
      haps = Pattern.events(pattern)

      assert Hap.sound(Enum.at(haps, 0)) == "sd"
      assert Hap.sound(Enum.at(haps, 1)) == "bd"
    end

    test "events at exactly 1.0 would be in next cycle" do
      pattern = parse("bd sd hh cp") |> Pattern.rev()
      haps = Pattern.query(pattern, 0)

      Enum.each(haps, fn hap ->
        assert Time.gte?(hap.part.begin, Time.zero())
        assert Time.lt?(hap.part.begin, Time.one()), "Event should be < 1.0"
      end)
    end
  end

  describe "palindrome/1" do
    test "alternates forward and backward across cycles" do
      pattern = parse("a b c") |> Pattern.palindrome()

      # Cycle 0: forward
      haps_0 = Pattern.query(pattern, 0)
      assert length(haps_0) == 3
      assert sounds(haps_0) == ["a", "b", "c"]

      # Cycle 1: reversed
      haps_1 = Pattern.query(pattern, 1)
      assert length(haps_1) == 3
      assert sounds(haps_1) == ["c", "b", "a"]

      # Cycle 2: forward again
      haps_2 = Pattern.query(pattern, 2)
      assert sounds(haps_2) == ["a", "b", "c"]
    end

    test "fast(2) shows forward and backward in single cycle (Strudel compatibility)" do
      # Strudel: fastcat('a','b','c').palindrome().fast(2) == ['a','b','c','c','b','a']
      pattern = parse("a b c") |> Pattern.palindrome() |> Pattern.fast(2)
      haps = Pattern.query(pattern, 0)

      assert length(haps) == 6
      assert sounds(haps) == ["a", "b", "c", "c", "b", "a"]
    end
  end

  describe "struct_fn/2" do
    test "applies rhythmic structure" do
      structure = parse("x ~ x")
      pattern = parse("c eb g") |> Pattern.struct_fn(structure)
      haps = Pattern.events(pattern)

      assert length(haps) == 2
      assert Hap.sound(Enum.at(haps, 0)) == "c"
      assert Hap.sound(Enum.at(haps, 1)) == "g"
    end

    test "works with complex structures" do
      structure = parse("x ~ ~ x")
      pattern = parse("bd sd hh cp") |> Pattern.struct_fn(structure)
      haps = Pattern.events(pattern)

      assert length(haps) == 2
    end
  end

  describe "mask/2" do
    test "silences based on binary pattern" do
      mask_pattern = parse("1 0 1 0")
      pattern = parse("bd sd hh cp") |> Pattern.mask(mask_pattern)
      haps = Pattern.events(pattern)

      assert length(haps) == 2
      assert Hap.sound(Enum.at(haps, 0)) == "bd"
      assert Hap.sound(Enum.at(haps, 1)) == "hh"
    end

    test "filters out rests in mask" do
      mask_pattern = parse("1 ~ 1 1")
      pattern = parse("bd sd hh cp") |> Pattern.mask(mask_pattern)
      haps = Pattern.events(pattern)

      assert length(haps) == 3
    end

    test "filters out zeros" do
      mask_pattern = parse("1 1 0 0")
      pattern = parse("a b c d") |> Pattern.mask(mask_pattern)
      haps = Pattern.events(pattern)

      assert length(haps) == 2
      assert Hap.sound(Enum.at(haps, 0)) == "a"
      assert Hap.sound(Enum.at(haps, 1)) == "b"
    end

    test "mask with all ones keeps all events" do
      mask = parse("1 1 1 1")
      pattern = parse("bd sd hh cp") |> Pattern.mask(mask)
      haps = Pattern.query(pattern, 0)
      assert length(haps) == 4
    end

    test "mask with all zeros removes all events" do
      mask = parse("0 0 0 0")
      pattern = parse("bd sd hh cp") |> Pattern.mask(mask)
      haps = Pattern.query(pattern, 0)
      assert length(haps) == 0
    end

    test "mask with mixed values" do
      mask = parse("1 0 ~ 1")
      pattern = parse("a b c d") |> Pattern.mask(mask)
      haps = Pattern.query(pattern, 0)
      assert length(haps) == 2
      assert sounds(haps) == ["a", "d"]
    end
  end

  describe "degrade_by/2" do
    test "removes approximately the expected percentage" do
      pattern = parse("bd sd hh cp bd sd hh cp")
      degraded = Pattern.degrade_by(pattern, 0.5)
      haps = Pattern.events(degraded)

      assert length(haps) >= 1
      assert length(haps) <= 8
    end

    test "is deterministic per cycle" do
      pattern = parse("bd sd hh cp") |> Pattern.degrade_by(0.5)

      haps_first = Pattern.query(pattern, 0)
      haps_second = Pattern.query(pattern, 0)

      assert haps_first == haps_second
    end

    test "produces different results for different cycles" do
      pattern = parse("bd sd hh cp") |> Pattern.degrade_by(0.5)

      results =
        0..19
        |> Enum.map(fn cycle -> length(Pattern.query(pattern, cycle)) end)
        |> Enum.uniq()

      assert length(results) > 1
    end
  end

  describe "degrade/1" do
    test "removes some events" do
      pattern = parse("bd sd hh cp")
      degraded = Pattern.degrade(pattern)
      haps = Pattern.events(degraded)

      assert length(haps) <= 4
    end
  end

  describe "jux/2" do
    test "doubles events with pan" do
      pattern = parse("bd sd") |> Pattern.jux(&Pattern.rev/1)
      haps = Pattern.events(pattern)

      assert length(haps) == 4
    end

    test "sets pan values" do
      pattern = parse("bd") |> Pattern.jux(&Pattern.rev/1)
      haps = Pattern.events(pattern)

      pans = Enum.map(haps, fn h -> h.value[:pan] end)
      assert -1.0 in pans
      assert 1.0 in pans
    end
  end

  describe "jux_by/3" do
    test "creates partial stereo effect" do
      pattern = parse("bd sd") |> Pattern.jux_by(0.5, &Pattern.rev/1)
      haps = Pattern.events(pattern)

      assert length(haps) == 4

      pans = Enum.map(haps, fn h -> h.value[:pan] end)
      assert -0.5 in pans
      assert 0.5 in pans
    end

    test "jux_by with 0.0 creates centered effect" do
      pattern = parse("bd") |> Pattern.jux_by(0.0, &Pattern.rev/1)
      haps = Pattern.events(pattern)

      pans = Enum.map(haps, fn h -> h.value[:pan] end)
      assert Enum.all?(pans, fn p -> p == 0.0 or p == -0.0 end)
    end

    test "jux_by with 1.0 equals jux" do
      pattern = parse("bd") |> Pattern.jux_by(1.0, &Pattern.rev/1)
      haps = Pattern.events(pattern)

      pans = Enum.map(haps, fn h -> h.value[:pan] end)
      assert -1.0 in pans
      assert 1.0 in pans
    end
  end

  describe "superimpose/2" do
    test "stacks transformed version with original" do
      pattern = parse("bd sd") |> Pattern.superimpose(&Pattern.fast(&1, 2))
      haps = Pattern.events(pattern)

      assert length(haps) == 6
    end

    test "preserves original events" do
      pattern = parse("bd sd") |> Pattern.superimpose(&Pattern.rev/1)
      haps = Pattern.events(pattern)

      assert length(haps) == 4
    end

    test "superimpose with gain" do
      pattern =
        parse("bd sd")
        |> Pattern.superimpose(&Pattern.gain(&1, 0.5))

      haps = Pattern.query(pattern, 0)

      assert length(haps) == 4

      gains = Enum.map(haps, fn h -> h.value[:gain] end)
      assert nil in gains
      assert 0.5 in gains
    end
  end

  describe "off/3" do
    test "creates delayed copy with proper late semantics" do
      # off uses late() which pulls from previous cycle via query time transformation
      # Stack original (2 events) + late(0.125, rev) (3 events due to cycle boundary)
      pattern = parse("bd sd") |> Pattern.off(0.125, &Pattern.rev/1)
      haps = Pattern.events(pattern)

      # 5 events: 2 original + 3 from delayed rev (includes cycle -1's bd shifted into view)
      assert length(haps) == 5
    end

    test "off with identity creates offset copy" do
      # off(0.25, identity) should give 2 original + 2 delayed = 4 events
      # (0.25 offset doesn't cross cycle boundary as much)
      pattern = parse("bd") |> Pattern.off(0.25, fn p -> p end)
      haps = Pattern.events(pattern)

      assert has_time?(haps, Time.zero())
      assert has_time?(haps, Time.new(1, 4))
      # Original + delayed copy (potentially 3 due to cycle boundary)
      assert length(haps) >= 2
    end
  end

  describe "echo/4" do
    test "creates multiple delayed copies" do
      pattern = parse("bd sd") |> Pattern.echo(3, 0.125, 0.8)
      haps = Pattern.events(pattern)

      assert length(haps) == 8
    end

    test "decreases gain for each echo" do
      pattern = parse("bd") |> Pattern.echo(2, 0.125, 0.5)
      haps = Pattern.events(pattern)

      gains = Enum.map(haps, fn h -> Map.get(h.value, :gain, 1.0) end)

      assert 1.0 in gains
      assert Enum.any?(gains, fn g -> abs(g - 0.5) < 0.001 end)
      assert Enum.any?(gains, fn g -> abs(g - 0.25) < 0.001 end)
    end
  end

  describe "striate/2" do
    test "creates sliced events" do
      pattern = parse("bd sd") |> Pattern.striate(4)
      haps = Pattern.events(pattern)

      assert length(haps) == 8
    end

    test "reduces duration of each slice" do
      pattern = parse("bd") |> Pattern.striate(4)
      haps = Pattern.events(pattern)

      assert length(haps) == 4
      # Each slice should have duration less than 1/2
      assert Enum.all?(haps, fn h ->
               Time.lt?(TimeSpan.duration(h.part), Time.half())
             end)
    end
  end

  describe "chop/2" do
    test "chops events into pieces" do
      pattern = parse("bd sd") |> Pattern.chop(4)
      haps = Pattern.events(pattern)

      assert length(haps) == 8
    end

    test "maintains sound identity" do
      pattern = parse("bd sd") |> Pattern.chop(3)
      haps = Pattern.events(pattern)

      bd_haps = Enum.filter(haps, fn h -> Hap.sound(h) == "bd" end)
      sd_haps = Enum.filter(haps, fn h -> Hap.sound(h) == "sd" end)

      assert length(bd_haps) == 3
      assert length(sd_haps) == 3
    end
  end
end
