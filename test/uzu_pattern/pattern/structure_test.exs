defmodule UzuPattern.Pattern.StructureTest do
  @moduledoc """
  Tests for structure manipulation functions.

  Functions: rev, palindrome, struct_fn, mask, degrade, degrade_by,
             jux, jux_by, superimpose, off, echo, striate, chop
  """

  use ExUnit.Case, async: true

  alias UzuPattern.Pattern

  defp parse(str), do: UzuPattern.parse(str)

  describe "rev/1" do
    test "reverses event order" do
      pattern = parse("bd sd hh") |> Pattern.rev()
      events = Pattern.events(pattern)

      assert hd(events).sound == "hh"
    end

    test "adjusts times correctly" do
      pattern = parse("bd sd") |> Pattern.rev()
      events = Pattern.events(pattern)

      assert Enum.at(events, 0).sound == "sd"
      assert Enum.at(events, 1).sound == "bd"
    end

    test "events at exactly 1.0 would be in next cycle" do
      pattern = parse("bd sd hh cp") |> Pattern.rev()
      events = Pattern.query(pattern, 0)

      Enum.each(events, fn event ->
        assert event.time >= 0.0
        assert event.time < 1.0, "Event at time #{event.time} should be < 1.0"
      end)
    end
  end

  describe "palindrome/1" do
    test "creates forward then backward pattern" do
      pattern = parse("bd sd hh") |> Pattern.palindrome()
      events = Pattern.events(pattern)

      assert length(events) == 6
    end
  end

  describe "struct_fn/2" do
    test "applies rhythmic structure" do
      structure = parse("x ~ x")
      pattern = parse("c eb g") |> Pattern.struct_fn(structure)
      events = Pattern.events(pattern)

      assert length(events) == 2
      assert Enum.at(events, 0).sound == "c"
      assert Enum.at(events, 1).sound == "g"
    end

    test "works with complex structures" do
      structure = parse("x ~ ~ x")
      pattern = parse("bd sd hh cp") |> Pattern.struct_fn(structure)
      events = Pattern.events(pattern)

      assert length(events) == 2
    end
  end

  describe "mask/2" do
    test "silences based on binary pattern" do
      mask_pattern = parse("1 0 1 0")
      pattern = parse("bd sd hh cp") |> Pattern.mask(mask_pattern)
      events = Pattern.events(pattern)

      assert length(events) == 2
      assert Enum.at(events, 0).sound == "bd"
      assert Enum.at(events, 1).sound == "hh"
    end

    test "filters out rests in mask" do
      mask_pattern = parse("1 ~ 1 1")
      pattern = parse("bd sd hh cp") |> Pattern.mask(mask_pattern)
      events = Pattern.events(pattern)

      assert length(events) == 3
    end

    test "filters out zeros" do
      mask_pattern = parse("1 1 0 0")
      pattern = parse("a b c d") |> Pattern.mask(mask_pattern)
      events = Pattern.events(pattern)

      assert length(events) == 2
      assert Enum.at(events, 0).sound == "a"
      assert Enum.at(events, 1).sound == "b"
    end

    test "mask with all ones keeps all events" do
      mask = parse("1 1 1 1")
      pattern = parse("bd sd hh cp") |> Pattern.mask(mask)
      events = Pattern.query(pattern, 0)
      assert length(events) == 4
    end

    test "mask with all zeros removes all events" do
      mask = parse("0 0 0 0")
      pattern = parse("bd sd hh cp") |> Pattern.mask(mask)
      events = Pattern.query(pattern, 0)
      assert length(events) == 0
    end

    test "mask with mixed values" do
      mask = parse("1 0 ~ 1")
      pattern = parse("a b c d") |> Pattern.mask(mask)
      events = Pattern.query(pattern, 0)
      assert length(events) == 2
      assert Enum.map(events, & &1.sound) == ["a", "d"]
    end
  end

  describe "degrade_by/2" do
    test "removes approximately the expected percentage" do
      pattern = parse("bd sd hh cp bd sd hh cp")
      degraded = Pattern.degrade_by(pattern, 0.5)
      events = Pattern.events(degraded)

      assert length(events) >= 1
      assert length(events) <= 8
    end

    test "is deterministic per cycle" do
      pattern = parse("bd sd hh cp") |> Pattern.degrade_by(0.5)

      events_first = Pattern.query(pattern, 0)
      events_second = Pattern.query(pattern, 0)

      assert events_first == events_second
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
      events = Pattern.events(degraded)

      assert length(events) <= 4
    end
  end

  describe "jux/2" do
    test "doubles events with pan" do
      pattern = parse("bd sd") |> Pattern.jux(&Pattern.rev/1)
      events = Pattern.events(pattern)

      assert length(events) == 4
    end

    test "sets pan values" do
      pattern = parse("bd") |> Pattern.jux(&Pattern.rev/1)
      events = Pattern.events(pattern)

      pans = Enum.map(events, fn e -> e.params[:pan] end)
      assert -1.0 in pans
      assert 1.0 in pans
    end
  end

  describe "jux_by/3" do
    test "creates partial stereo effect" do
      pattern = parse("bd sd") |> Pattern.jux_by(0.5, &Pattern.rev/1)
      events = Pattern.events(pattern)

      assert length(events) == 4

      pans = Enum.map(events, fn e -> e.params[:pan] end)
      assert -0.5 in pans
      assert 0.5 in pans
    end

    test "jux_by with 0.0 creates centered effect" do
      pattern = parse("bd") |> Pattern.jux_by(0.0, &Pattern.rev/1)
      events = Pattern.events(pattern)

      pans = Enum.map(events, fn e -> e.params[:pan] end)
      assert Enum.all?(pans, fn p -> p == 0.0 or p == -0.0 end)
    end

    test "jux_by with 1.0 equals jux" do
      pattern = parse("bd") |> Pattern.jux_by(1.0, &Pattern.rev/1)
      events = Pattern.events(pattern)

      pans = Enum.map(events, fn e -> e.params[:pan] end)
      assert -1.0 in pans
      assert 1.0 in pans
    end
  end

  describe "superimpose/2" do
    test "stacks transformed version with original" do
      pattern = parse("bd sd") |> Pattern.superimpose(&Pattern.fast(&1, 2))
      events = Pattern.events(pattern)

      assert length(events) == 6
    end

    test "preserves original events" do
      pattern = parse("bd sd") |> Pattern.superimpose(&Pattern.rev/1)
      events = Pattern.events(pattern)

      assert length(events) == 4
    end

    test "superimpose with gain" do
      pattern =
        parse("bd sd")
        |> Pattern.superimpose(&Pattern.gain(&1, 0.5))

      events = Pattern.query(pattern, 0)

      assert length(events) == 4

      gains = Enum.map(events, fn e -> e.params[:gain] end)
      assert nil in gains
      assert 0.5 in gains
    end
  end

  describe "off/3" do
    test "creates delayed copy" do
      pattern = parse("bd sd") |> Pattern.off(0.125, &Pattern.rev/1)
      events = Pattern.events(pattern)

      assert length(events) == 4
    end

    test "wraps time correctly" do
      pattern = parse("bd") |> Pattern.off(0.9, fn p -> p end)
      events = Pattern.events(pattern)

      times = Enum.map(events, fn e -> e.time end)
      assert 0.0 in times
      assert Enum.any?(times, fn t -> abs(t - 0.9) < 0.001 end)
    end
  end

  describe "echo/4" do
    test "creates multiple delayed copies" do
      pattern = parse("bd sd") |> Pattern.echo(3, 0.125, 0.8)
      events = Pattern.events(pattern)

      assert length(events) == 8
    end

    test "decreases gain for each echo" do
      pattern = parse("bd") |> Pattern.echo(2, 0.125, 0.5)
      events = Pattern.events(pattern)

      gains = Enum.map(events, fn e -> Map.get(e.params, :gain, 1.0) end)

      assert 1.0 in gains
      assert Enum.any?(gains, fn g -> abs(g - 0.5) < 0.001 end)
      assert Enum.any?(gains, fn g -> abs(g - 0.25) < 0.001 end)
    end
  end

  describe "striate/2" do
    test "creates sliced events" do
      pattern = parse("bd sd") |> Pattern.striate(4)
      events = Pattern.events(pattern)

      assert length(events) == 8
    end

    test "reduces duration of each slice" do
      pattern = parse("bd") |> Pattern.striate(4)
      events = Pattern.events(pattern)

      assert length(events) == 4
      assert Enum.all?(events, fn e -> e.duration < 0.5 end)
    end
  end

  describe "chop/2" do
    test "chops events into pieces" do
      pattern = parse("bd sd") |> Pattern.chop(4)
      events = Pattern.events(pattern)

      assert length(events) == 8
    end

    test "maintains sound identity" do
      pattern = parse("bd sd") |> Pattern.chop(3)
      events = Pattern.events(pattern)

      bd_events = Enum.filter(events, fn e -> e.sound == "bd" end)
      sd_events = Enum.filter(events, fn e -> e.sound == "sd" end)

      assert length(bd_events) == 3
      assert length(sd_events) == 3
    end
  end
end
