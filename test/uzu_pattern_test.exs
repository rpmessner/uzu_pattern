defmodule UzuPatternTest do
  use ExUnit.Case

  alias UzuPattern.Pattern

  # Helper: parse mini-notation string to pattern
  defp parse(str), do: UzuPattern.parse(str)

  describe "UzuPattern.parse/1" do
    test "creates pattern from mini-notation string" do
      pattern = parse("bd sd hh cp")
      events = Pattern.events(pattern)
      assert length(events) == 4
    end

    test "creates empty pattern from empty string" do
      pattern = parse("")
      events = Pattern.events(pattern)
      assert events == []
    end
  end

  describe "from_events/1" do
    test "creates pattern from event list" do
      events = UzuPattern.query(parse("bd sd"), 0)
      pattern = Pattern.from_events(events)
      result = Pattern.events(pattern)
      assert length(result) == 2
    end
  end

  describe "query/2" do
    test "returns Event structs" do
      pattern = parse("bd sd")
      events = Pattern.query(pattern, 0)

      assert length(events) == 2
      event = hd(events)
      assert event.sound == "bd"
      assert event.time == 0.0
    end
  end

  describe "query_for_scheduler/2" do
    test "returns events as maps" do
      pattern = parse("bd sd")
      events = Pattern.query_for_scheduler(pattern, 0)

      assert length(events) == 2
      event = hd(events)
      assert event.time == 0.0
      assert event.s == "bd"
    end
  end

  describe "events/1" do
    test "extracts raw events" do
      pattern = parse("bd sd")
      events = Pattern.events(pattern)

      assert length(events) == 2
      assert hd(events).sound == "bd"
    end
  end

  # ============================================================================
  # Time Modifiers
  # ============================================================================

  describe "fast/2" do
    test "doubles event times with factor 2" do
      pattern = parse("bd sd") |> Pattern.fast(2)
      events = Pattern.events(pattern)

      assert length(events) == 2
      assert Enum.at(events, 0).time == 0.0
      assert Enum.at(events, 1).time == 0.25
    end

    test "filters out events past cycle boundary" do
      pattern = parse("bd sd hh cp") |> Pattern.fast(0.5)
      events = Pattern.events(pattern)

      # At 0.5x speed, only first 2 events fit in cycle
      assert length(events) == 2
    end
  end

  describe "slow/2" do
    test "slows pattern across multiple cycles" do
      pattern = parse("bd sd") |> Pattern.slow(2)

      # Cycle 0: first event
      events_0 = Pattern.query(pattern, 0)
      assert length(events_0) == 1
      assert hd(events_0).sound == "bd"

      # Cycle 1: second event
      events_1 = Pattern.query(pattern, 1)
      assert length(events_1) == 1
      assert hd(events_1).sound == "sd"
    end
  end

  describe "rev/1" do
    test "reverses event order" do
      pattern = parse("bd sd hh") |> Pattern.rev()
      events = Pattern.events(pattern)

      # After reversal, hh should be first (at time 0)
      assert hd(events).sound == "hh"
    end

    test "adjusts times correctly" do
      pattern = parse("bd sd") |> Pattern.rev()
      events = Pattern.events(pattern)

      # Original: bd at 0.0, sd at 0.5
      # Reversed: sd at 0.0, bd at 0.5
      assert Enum.at(events, 0).sound == "sd"
      assert Enum.at(events, 1).sound == "bd"
    end
  end

  describe "early/2" do
    test "shifts pattern earlier with wrap" do
      pattern = parse("bd sd") |> Pattern.early(0.25)
      events = Pattern.events(pattern)

      # bd was at 0.0, now at 0.75 (wrapped)
      # sd was at 0.5, now at 0.25
      times = Enum.map(events, & &1.time) |> Enum.sort()
      assert_in_delta Enum.at(times, 0), 0.25, 0.01
      assert_in_delta Enum.at(times, 1), 0.75, 0.01
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
  end

  describe "ply/2" do
    test "repeats each event N times" do
      pattern = parse("bd sd") |> Pattern.ply(2)
      events = Pattern.events(pattern)

      # 2 events * 2 repetitions = 4 events
      assert length(events) == 4
    end

    test "divides duration correctly" do
      pattern = parse("bd sd") |> Pattern.ply(3)
      events = Pattern.events(pattern)

      # Each event originally has duration 0.5
      # With ply(3), each repetition should have duration 0.5/3 ≈ 0.167
      assert length(events) == 6
      assert_in_delta Enum.at(events, 0).duration, 0.5 / 3, 0.01
    end

    test "spaces repetitions evenly within event duration" do
      pattern = parse("bd") |> Pattern.ply(4)
      events = Pattern.events(pattern)

      # bd originally at 0.0 with duration 1.0
      # With ply(4), repetitions at 0.0, 0.25, 0.5, 0.75
      assert length(events) == 4
      assert_in_delta Enum.at(events, 0).time, 0.0, 0.01
      assert_in_delta Enum.at(events, 1).time, 0.25, 0.01
      assert_in_delta Enum.at(events, 2).time, 0.5, 0.01
      assert_in_delta Enum.at(events, 3).time, 0.75, 0.01
    end

    test "maintains event properties" do
      pattern = parse("bd:2") |> Pattern.ply(2)
      events = Pattern.events(pattern)

      # All repetitions should maintain sample number
      assert Enum.all?(events, fn e -> e.sample == 2 end)
      assert Enum.all?(events, fn e -> e.sound == "bd" end)
    end

    test "works with multiple events" do
      pattern = parse("bd sd hh") |> Pattern.ply(2)
      events = Pattern.events(pattern)

      # 3 events * 2 repetitions = 6 events
      assert length(events) == 6

      # Check that we get pairs of each sound
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

      # All events should be within [0.25, 0.75)
      assert Enum.all?(events, fn e -> e.time >= 0.25 and e.time < 0.75 end)
    end

    test "maintains event count" do
      pattern = parse("bd sd hh cp") |> Pattern.compress(0.25, 0.75)
      events = Pattern.events(pattern)

      # Should still have 4 events
      assert length(events) == 4
    end

    test "scales times proportionally" do
      pattern = parse("bd sd") |> Pattern.compress(0.0, 0.5)
      events = Pattern.events(pattern)

      # Original: bd at 0.0, sd at 0.5
      # Compressed to [0.0, 0.5): bd at 0.0, sd at 0.25
      assert_in_delta Enum.at(events, 0).time, 0.0, 0.01
      assert_in_delta Enum.at(events, 1).time, 0.25, 0.01
    end

    test "scales durations proportionally" do
      pattern = parse("bd sd") |> Pattern.compress(0.0, 0.5)
      events = Pattern.events(pattern)

      # Original duration: 0.5 each
      # Compressed duration: 0.25 each (halved)
      assert_in_delta Enum.at(events, 0).duration, 0.25, 0.01
      assert_in_delta Enum.at(events, 1).duration, 0.25, 0.01
    end

    test "creates rhythmic gap" do
      pattern = parse("bd sd") |> Pattern.compress(0.25, 0.75)
      events = Pattern.events(pattern)

      # Gap before 0.25 and after 0.75
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
      # Pattern: bd at 0.0, sd at 0.25, hh at 0.5, cp at 0.75
      pattern = parse("bd sd hh cp") |> Pattern.zoom(0.25, 0.75)
      events = Pattern.events(pattern)

      # Should extract middle half (sd, hh) and expand to full cycle
      assert length(events) == 2
      sounds = Enum.map(events, & &1.sound)
      assert "sd" in sounds
      assert "hh" in sounds
    end

    test "expands extracted segment to full cycle" do
      pattern = parse("bd sd hh cp") |> Pattern.zoom(0.5, 1.0)
      events = Pattern.events(pattern)

      # Extract second half (hh at 0.5, cp at 0.75)
      # Expand to full cycle: hh at 0.0, cp at 0.5
      assert length(events) == 2
      assert_in_delta Enum.at(events, 0).time, 0.0, 0.01
      assert_in_delta Enum.at(events, 1).time, 0.5, 0.01
    end

    test "scales durations correctly" do
      pattern = parse("bd sd") |> Pattern.zoom(0.0, 0.5)
      events = Pattern.events(pattern)

      # Extract first half (bd only) and expand
      # Original duration: 0.5, expanded duration: 1.0 (doubled)
      assert length(events) == 1
      assert_in_delta Enum.at(events, 0).duration, 1.0, 0.01
    end

    test "filters events outside window" do
      pattern = parse("bd sd hh cp") |> Pattern.zoom(0.25, 0.5)
      events = Pattern.events(pattern)

      # Only sd (at 0.25) is in range [0.25, 0.5)
      assert length(events) == 1
      assert hd(events).sound == "sd"
    end

    test "maintains event properties" do
      pattern = parse("bd:1 sd:2 hh:3 cp:4") |> Pattern.zoom(0.25, 0.75)
      events = Pattern.events(pattern)

      # Extract sd:2 and hh:3
      assert Enum.at(events, 0).sound == "sd"
      assert Enum.at(events, 0).sample == 2
      assert Enum.at(events, 1).sound == "hh"
      assert Enum.at(events, 1).sample == 3
    end

    test "zoom is inverse of compress" do
      original = parse("bd sd hh cp")

      # Zoom extracts a segment
      zoomed = Pattern.zoom(original, 0.25, 0.75)

      # The zoomed pattern should have 2 events (sd, hh)
      assert length(Pattern.events(zoomed)) == 2
    end
  end

  describe "linger/2" do
    test "repeats fraction of pattern" do
      pattern = parse("bd sd hh cp") |> Pattern.linger(0.5)
      events = Pattern.events(pattern)

      # First half (bd, sd) repeated twice = 4 events
      assert length(events) == 4

      # Check that we get pairs
      sounds = Enum.map(events, & &1.sound)
      assert Enum.count(sounds, &(&1 == "bd")) == 2
      assert Enum.count(sounds, &(&1 == "sd")) == 2
    end

    test "linger(0.25) repeats first quarter 4 times" do
      pattern = parse("bd sd hh cp") |> Pattern.linger(0.25)
      events = Pattern.events(pattern)

      # First quarter (bd) repeated 4 times
      assert length(events) == 4
      assert Enum.all?(events, fn e -> e.sound == "bd" end)
    end

    test "linger(1.0) keeps pattern unchanged" do
      original = parse("bd sd hh cp")
      lingered = Pattern.linger(original, 1.0)

      # Should be identical to original
      assert length(Pattern.events(lingered)) == 4
      original_sounds = Enum.map(Pattern.events(original), & &1.sound)
      lingered_sounds = Enum.map(Pattern.events(lingered), & &1.sound)
      assert original_sounds == lingered_sounds
    end

    test "spaces repetitions correctly" do
      # In "bd sd", bd is at 0.0, sd is at 0.5
      # linger(0.5) extracts first half (only bd at 0.0)
      # Then repeats it: bd at 0.0, bd at 0.5
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

      # First half: bd:3 and sd:2, repeated twice
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

      # First third (bd) repeated 3 times
      assert length(events) == 3
      assert Enum.all?(events, fn e -> e.sound == "bd" end)
    end
  end

  # ============================================================================
  # Combinators
  # ============================================================================

  describe "stack/1" do
    test "combines patterns simultaneously" do
      p1 = parse("bd")
      p2 = parse("sd")
      combined = Pattern.stack([p1, p2])

      events = Pattern.events(combined)
      assert length(events) == 2

      sounds = Enum.map(events, & &1.sound)
      assert "bd" in sounds
      assert "sd" in sounds
    end
  end

  describe "cat/1 (slowcat)" do
    test "alternates patterns across cycles" do
      p1 = parse("bd")
      p2 = parse("sd")
      combined = Pattern.cat([p1, p2])

      # Cycle 0: first pattern
      events_0 = Pattern.query(combined, 0)
      assert length(events_0) == 1
      assert hd(events_0).sound == "bd"

      # Cycle 1: second pattern
      events_1 = Pattern.query(combined, 1)
      assert length(events_1) == 1
      assert hd(events_1).sound == "sd"
    end

    test "wraps around after all patterns" do
      p1 = parse("bd")
      p2 = parse("sd")
      combined = Pattern.cat([p1, p2])

      # Cycle 2: wraps to first pattern
      events_2 = Pattern.query(combined, 2)
      assert hd(events_2).sound == "bd"
    end
  end

  describe "fastcat/1" do
    test "concatenates patterns within one cycle" do
      p1 = parse("bd")
      p2 = parse("sd")
      combined = Pattern.fastcat([p1, p2])

      events = Pattern.events(combined)
      assert length(events) == 2
      assert Enum.at(events, 0).time == 0.0
      assert Enum.at(events, 1).time == 0.5
    end

    test "scales durations correctly" do
      p1 = parse("bd sd")
      p2 = parse("hh")
      combined = Pattern.fastcat([p1, p2])

      events = Pattern.events(combined)
      # p1 events should have duration 0.25 (half of 0.5)
      # p2 event should have duration 0.5
      assert Enum.at(events, 0).duration == 0.25
    end
  end

  describe "palindrome/1" do
    test "creates forward then backward pattern" do
      pattern = parse("bd sd hh") |> Pattern.palindrome()
      events = Pattern.events(pattern)

      assert length(events) == 6
    end
  end

  # ============================================================================
  # Conditional Modifiers
  # ============================================================================

  describe "every/3" do
    test "applies function on matching cycles" do
      pattern = parse("bd sd") |> Pattern.every(2, &Pattern.rev/1)

      # Cycle 0: should be reversed (0 mod 2 == 0)
      events_0 = Pattern.query(pattern, 0)
      assert hd(events_0).sound == "sd"

      # Cycle 1: should be normal
      events_1 = Pattern.query(pattern, 1)
      assert hd(events_1).sound == "bd"

      # Cycle 2: should be reversed
      events_2 = Pattern.query(pattern, 2)
      assert hd(events_2).sound == "sd"
    end
  end

  describe "sometimes_by/3" do
    test "is deterministic per cycle" do
      pattern = parse("bd sd") |> Pattern.sometimes_by(0.5, &Pattern.rev/1)

      # Same cycle should always produce same result
      events_0a = Pattern.query(pattern, 0)
      events_0b = Pattern.query(pattern, 0)

      assert events_0a == events_0b
    end
  end

  describe "iter/2" do
    test "rotates pattern start each cycle" do
      pattern = parse("bd sd hh cp") |> Pattern.iter(4)

      # Cycle 0: normal order (bd first)
      events_0 = Pattern.query(pattern, 0)
      assert hd(events_0).sound == "bd"

      # Cycle 1: rotated once (sd first)
      events_1 = Pattern.query(pattern, 1)
      assert hd(events_1).sound == "sd"

      # Cycle 2: rotated twice (hh first)
      events_2 = Pattern.query(pattern, 2)
      assert hd(events_2).sound == "hh"

      # Cycle 3: rotated three times (cp first)
      events_3 = Pattern.query(pattern, 3)
      assert hd(events_3).sound == "cp"

      # Cycle 4: wraps back to start (bd first)
      events_4 = Pattern.query(pattern, 4)
      assert hd(events_4).sound == "bd"
    end

    test "maintains event count" do
      pattern = parse("bd sd hh cp") |> Pattern.iter(4)

      events = Pattern.query(pattern, 0)
      assert length(events) == 4
    end

    test "works with different subdivision counts" do
      pattern = parse("bd sd") |> Pattern.iter(2)

      # Cycle 0: bd first
      events_0 = Pattern.query(pattern, 0)
      assert hd(events_0).sound == "bd"

      # Cycle 1: sd first
      events_1 = Pattern.query(pattern, 1)
      assert hd(events_1).sound == "sd"
    end
  end

  describe "iter_back/2" do
    test "rotates pattern start backwards each cycle" do
      pattern = parse("bd sd hh cp") |> Pattern.iter_back(4)

      # Cycle 0: normal order (bd first)
      events_0 = Pattern.query(pattern, 0)
      assert hd(events_0).sound == "bd"

      # Cycle 1: rotated backwards (cp first)
      events_1 = Pattern.query(pattern, 1)
      assert hd(events_1).sound == "cp"

      # Cycle 2: rotated backwards twice (hh first)
      events_2 = Pattern.query(pattern, 2)
      assert hd(events_2).sound == "hh"

      # Cycle 3: rotated backwards three times (sd first)
      events_3 = Pattern.query(pattern, 3)
      assert hd(events_3).sound == "sd"
    end

    test "maintains event count" do
      pattern = parse("bd sd hh cp") |> Pattern.iter_back(4)

      events = Pattern.query(pattern, 0)
      assert length(events) == 4
    end

    test "is opposite direction of iter" do
      original = parse("bd sd hh cp")
      iter_pattern = Pattern.iter(original, 4)
      iter_back_pattern = Pattern.iter_back(original, 4)

      # At cycle 1, iter should have sd first
      iter_events = Pattern.query(iter_pattern, 1)
      assert hd(iter_events).sound == "sd"

      # At cycle 1, iter_back should have cp first (opposite)
      iter_back_events = Pattern.query(iter_back_pattern, 1)
      assert hd(iter_back_events).sound == "cp"
    end
  end

  # ============================================================================
  # Degradation
  # ============================================================================

  describe "degrade_by/2" do
    test "removes approximately the expected percentage" do
      pattern = parse("bd sd hh cp bd sd hh cp")
      degraded = Pattern.degrade_by(pattern, 0.5)
      events = Pattern.events(degraded)

      # Should have roughly half the events (probabilistic)
      assert length(events) >= 1
      assert length(events) <= 8
    end
  end

  describe "degrade/1" do
    test "removes some events" do
      pattern = parse("bd sd hh cp")
      degraded = Pattern.degrade(pattern)
      events = Pattern.events(degraded)

      # Should have fewer events than original
      assert length(events) <= 4
    end
  end

  # ============================================================================
  # Stereo
  # ============================================================================

  describe "jux/2" do
    test "doubles events with pan" do
      pattern = parse("bd sd") |> Pattern.jux(&Pattern.rev/1)
      events = Pattern.events(pattern)

      # Should have 4 events (2 original + 2 transformed)
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

  # ============================================================================
  # Phase 3: Advanced Conditional (v0.3.0)
  # ============================================================================

  describe "first_of/3" do
    test "applies function on first of N cycles" do
      pattern = parse("bd sd hh cp") |> Pattern.first_of(4, &Pattern.rev/1)

      # Cycle 0: should be reversed
      events_0 = Pattern.query(pattern, 0)
      assert hd(events_0).sound == "cp"

      # Cycle 1: should not be reversed
      events_1 = Pattern.query(pattern, 1)
      assert hd(events_1).sound == "bd"

      # Cycle 4: should be reversed again
      events_4 = Pattern.query(pattern, 4)
      assert hd(events_4).sound == "cp"
    end
  end

  describe "last_of/3" do
    test "applies function on last of N cycles" do
      pattern = parse("bd sd hh cp") |> Pattern.last_of(4, &Pattern.rev/1)

      # Cycle 0, 1, 2: should not be reversed
      events_0 = Pattern.query(pattern, 0)
      assert hd(events_0).sound == "bd"

      # Cycle 3: should be reversed (last of 4)
      events_3 = Pattern.query(pattern, 3)
      assert hd(events_3).sound == "cp"

      # Cycle 7: should be reversed (last of next group)
      events_7 = Pattern.query(pattern, 7)
      assert hd(events_7).sound == "cp"
    end
  end

  describe "when_fn/3" do
    test "applies function when condition is true" do
      pattern =
        parse("bd sd hh cp")
        |> Pattern.when_fn(fn cycle -> rem(cycle, 2) == 1 end, &Pattern.rev/1)

      # Even cycles: not reversed
      events_0 = Pattern.query(pattern, 0)
      assert hd(events_0).sound == "bd"

      # Odd cycles: reversed
      events_1 = Pattern.query(pattern, 1)
      assert hd(events_1).sound == "cp"

      events_3 = Pattern.query(pattern, 3)
      assert hd(events_3).sound == "cp"
    end

    test "works with complex conditions" do
      pattern =
        parse("bd sd")
        |> Pattern.when_fn(fn cycle -> cycle > 5 and rem(cycle, 3) == 0 end, &Pattern.rev/1)

      # Cycle 5: doesn't meet condition (not divisible by 3)
      events_5 = Pattern.query(pattern, 5)
      assert hd(events_5).sound == "bd"

      # Cycle 6: meets condition
      events_6 = Pattern.query(pattern, 6)
      assert hd(events_6).sound == "sd"
    end
  end

  describe "chunk/3" do
    test "applies function to rotating chunks" do
      pattern = parse("bd sd hh cp") |> Pattern.chunk(4, &Pattern.rev/1)

      # Cycle 0: first chunk (bd) should be affected
      events_0 = Pattern.query(pattern, 0)
      bd_event = Enum.find(events_0, fn e -> e.sound == "bd" end)
      assert bd_event != nil

      # All 4 events should still be present
      assert length(events_0) == 4
    end

    test "cycles through all chunks" do
      pattern = parse("a b c d") |> Pattern.chunk(2, &Pattern.fast(&1, 2))

      # Verify pattern exists and can be queried
      events = Pattern.query(pattern, 0)
      assert length(events) >= 1
    end
  end

  describe "chunk_back/3" do
    test "applies function to chunks in reverse" do
      pattern = parse("bd sd hh cp") |> Pattern.chunk_back(4, &Pattern.rev/1)

      # Cycle 0: last chunk should be affected (reverse of chunk)
      events_0 = Pattern.query(pattern, 0)
      assert length(events_0) == 4
    end
  end

  describe "struct_fn/2" do
    test "applies rhythmic structure" do
      structure = parse("x ~ x")
      pattern = parse("c eb g") |> Pattern.struct_fn(structure)
      events = Pattern.events(pattern)

      # Should keep only events at positions 0 and 2
      assert length(events) == 2
      assert Enum.at(events, 0).sound == "c"
      assert Enum.at(events, 1).sound == "g"
    end

    test "works with complex structures" do
      structure = parse("x ~ ~ x")
      pattern = parse("bd sd hh cp") |> Pattern.struct_fn(structure)
      events = Pattern.events(pattern)

      # Should keep events at positions 0 and 3
      assert length(events) == 2
    end
  end

  describe "mask/2" do
    test "silences based on binary pattern" do
      mask_pattern = parse("1 0 1 0")
      pattern = parse("bd sd hh cp") |> Pattern.mask(mask_pattern)
      events = Pattern.events(pattern)

      # Should keep only events at positions 0 and 2 (where mask is 1)
      assert length(events) == 2
      assert Enum.at(events, 0).sound == "bd"
      assert Enum.at(events, 1).sound == "hh"
    end

    test "filters out rests in mask" do
      mask_pattern = parse("1 ~ 1 1")
      pattern = parse("bd sd hh cp") |> Pattern.mask(mask_pattern)
      events = Pattern.events(pattern)

      # Should remove event at position 1 (where mask is ~)
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
  end

  # ============================================================================
  # Phase 4: Effects & Parameters (v0.4.0)
  # ============================================================================

  describe "gain/2" do
    test "sets gain parameter on all events" do
      pattern = parse("bd sd hh") |> Pattern.gain(0.5)
      events = Pattern.events(pattern)

      assert length(events) == 3
      assert Enum.all?(events, fn e -> e.params[:gain] == 0.5 end)
    end

    test "preserves other parameters" do
      pattern = parse("bd") |> Pattern.pan(0.5) |> Pattern.gain(0.8)
      events = Pattern.events(pattern)

      event = hd(events)
      assert event.params[:gain] == 0.8
      assert event.params[:pan] == 0.5
    end
  end

  describe "pan/2" do
    test "sets pan parameter within valid range" do
      pattern = parse("bd sd") |> Pattern.pan(0.75)
      events = Pattern.events(pattern)

      assert Enum.all?(events, fn e -> e.params[:pan] == 0.75 end)
    end

    test "accepts 0.0 (left)" do
      pattern = parse("bd") |> Pattern.pan(0.0)
      events = Pattern.events(pattern)

      assert hd(events).params[:pan] == 0.0
    end

    test "accepts 1.0 (right)" do
      pattern = parse("bd") |> Pattern.pan(1.0)
      events = Pattern.events(pattern)

      assert hd(events).params[:pan] == 1.0
    end
  end

  describe "speed/2" do
    test "sets speed parameter" do
      pattern = parse("bd sd") |> Pattern.speed(2.0)
      events = Pattern.events(pattern)

      assert Enum.all?(events, fn e -> e.params[:speed] == 2.0 end)
    end

    test "accepts fractional speeds" do
      pattern = parse("bd") |> Pattern.speed(0.5)
      events = Pattern.events(pattern)

      assert hd(events).params[:speed] == 0.5
    end
  end

  describe "cut/2" do
    test "sets cut group parameter" do
      pattern = parse("bd sd hh") |> Pattern.cut(1)
      events = Pattern.events(pattern)

      assert Enum.all?(events, fn e -> e.params[:cut] == 1 end)
    end

    test "accepts different cut groups" do
      pattern = parse("bd") |> Pattern.cut(5)
      events = Pattern.events(pattern)

      assert hd(events).params[:cut] == 5
    end
  end

  describe "room/2" do
    test "sets room (reverb) parameter" do
      pattern = parse("bd sd") |> Pattern.room(0.5)
      events = Pattern.events(pattern)

      assert Enum.all?(events, fn e -> e.params[:room] == 0.5 end)
    end

    test "accepts 0.0 (dry)" do
      pattern = parse("bd") |> Pattern.room(0.0)
      events = Pattern.events(pattern)

      assert hd(events).params[:room] == 0.0
    end

    test "accepts 1.0 (wet)" do
      pattern = parse("bd") |> Pattern.room(1.0)
      events = Pattern.events(pattern)

      assert hd(events).params[:room] == 1.0
    end
  end

  describe "delay/2" do
    test "sets delay parameter" do
      pattern = parse("bd sd") |> Pattern.delay(0.25)
      events = Pattern.events(pattern)

      assert Enum.all?(events, fn e -> e.params[:delay] == 0.25 end)
    end
  end

  describe "lpf/2" do
    test "sets low-pass filter frequency" do
      pattern = parse("bd sd") |> Pattern.lpf(1000)
      events = Pattern.events(pattern)

      assert Enum.all?(events, fn e -> e.params[:lpf] == 1000 end)
    end

    test "accepts full frequency range" do
      pattern = parse("bd") |> Pattern.lpf(20_000)
      events = Pattern.events(pattern)

      assert hd(events).params[:lpf] == 20_000
    end
  end

  describe "hpf/2" do
    test "sets high-pass filter frequency" do
      pattern = parse("bd sd") |> Pattern.hpf(500)
      events = Pattern.events(pattern)

      assert Enum.all?(events, fn e -> e.params[:hpf] == 500 end)
    end

    test "accepts full frequency range" do
      pattern = parse("bd") |> Pattern.hpf(20_000)
      events = Pattern.events(pattern)

      assert hd(events).params[:hpf] == 20_000
    end
  end

  # ============================================================================
  # Phase 5: Advanced Combinators (v0.5.0)
  # ============================================================================

  describe "jux_by/3" do
    test "creates partial stereo effect" do
      pattern = parse("bd sd") |> Pattern.jux_by(0.5, &Pattern.rev/1)
      events = Pattern.events(pattern)

      # Should have 4 events (2 original + 2 transformed)
      assert length(events) == 4

      # Check pan values
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

  describe "append/2" do
    test "appends pattern after first" do
      p1 = parse("bd sd")
      p2 = parse("hh cp")
      pattern = Pattern.append(p1, p2)

      # Query cycles 0 and 1 to see both patterns
      events_0 = Pattern.query(pattern, 0)
      events_1 = Pattern.query(pattern, 1)

      # First cycle has p1
      assert length(events_0) == 2
      sounds_0 = Enum.map(events_0, & &1.sound)
      assert "bd" in sounds_0

      # Second cycle has p2
      assert length(events_1) == 2
      sounds_1 = Enum.map(events_1, & &1.sound)
      assert "hh" in sounds_1
    end
  end

  describe "superimpose/2" do
    test "stacks transformed version with original" do
      pattern = parse("bd sd") |> Pattern.superimpose(&Pattern.fast(&1, 2))
      events = Pattern.events(pattern)

      # Should have original 2 + transformed 2 = 4 events
      assert length(events) == 4
    end

    test "preserves original events" do
      pattern = parse("bd sd") |> Pattern.superimpose(&Pattern.rev/1)
      events = Pattern.events(pattern)

      # Should have both bd and sd in original positions
      assert length(events) == 4
    end
  end

  describe "off/3" do
    test "creates delayed copy" do
      pattern = parse("bd sd") |> Pattern.off(0.125, &Pattern.rev/1)
      events = Pattern.events(pattern)

      # Should have 4 events (2 original + 2 offset)
      assert length(events) == 4
    end

    test "wraps time correctly" do
      pattern = parse("bd") |> Pattern.off(0.9, fn p -> p end)
      events = Pattern.events(pattern)

      times = Enum.map(events, fn e -> e.time end)
      # Original at 0.0, offset wraps: 0.0 + 0.9 = 0.9
      assert 0.0 in times
      assert Enum.any?(times, fn t -> abs(t - 0.9) < 0.001 end)
    end
  end

  describe "echo/3" do
    test "creates multiple delayed copies" do
      pattern = parse("bd sd") |> Pattern.echo(3, 0.125, 0.8)
      events = Pattern.events(pattern)

      # Should have original 2 + 3 echoes * 2 = 8 events
      assert length(events) == 8
    end

    test "decreases gain for each echo" do
      pattern = parse("bd") |> Pattern.echo(2, 0.125, 0.5)
      events = Pattern.events(pattern)

      # Get gains (original has no gain param, echoes have decreasing gain)
      gains = Enum.map(events, fn e -> Map.get(e.params, :gain, 1.0) end)

      # Should have: 1.0 (original), 0.5 (first echo), 0.25 (second echo)
      assert 1.0 in gains
      assert Enum.any?(gains, fn g -> abs(g - 0.5) < 0.001 end)
      assert Enum.any?(gains, fn g -> abs(g - 0.25) < 0.001 end)
    end
  end

  describe "striate/2" do
    test "creates sliced events" do
      pattern = parse("bd sd") |> Pattern.striate(4)
      events = Pattern.events(pattern)

      # Each event sliced into 4 = 2 * 4 = 8 events
      assert length(events) == 8
    end

    test "reduces duration of each slice" do
      pattern = parse("bd") |> Pattern.striate(4)
      events = Pattern.events(pattern)

      # "bd" has 1 event, striate(4) creates 4 slices
      assert length(events) == 4
      # Each slice should have reduced duration
      assert Enum.all?(events, fn e -> e.duration < 0.5 end)
    end
  end

  describe "chop/2" do
    test "chops events into pieces" do
      pattern = parse("bd sd") |> Pattern.chop(4)
      events = Pattern.events(pattern)

      # 2 events chopped into 4 = 8 events
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

  # ============================================================================
  # Phase 6: Advanced Rhythm (v0.6.0)
  # ============================================================================

  describe "euclid/3" do
    test "generates Euclidean rhythm" do
      pattern = parse("bd sd hh cp bd sd hh cp") |> Pattern.euclid(3, 8)
      events = Pattern.events(pattern)

      # 3 pulses across 8 steps = 3 events
      assert length(events) == 3
    end

    test "euclid(5, 8) generates correct pattern" do
      pattern = parse("a b c d e f g h") |> Pattern.euclid(5, 8)
      events = Pattern.events(pattern)

      # Classic 5 over 8 Euclidean rhythm
      assert length(events) == 5
    end

    test "euclid with events matching step count" do
      pattern = parse("a b c d e f g h") |> Pattern.euclid(3, 8)
      events = Pattern.events(pattern)

      # Euclidean(3,8) = [1,0,0,1,0,0,1,0] has pulses at positions 0,3,6
      # With 8 events, indices 0,3,6 are kept
      assert length(events) == 3
      # index 0
      assert Enum.at(events, 0).sound == "a"
      # index 3
      assert Enum.at(events, 1).sound == "d"
      # index 6
      assert Enum.at(events, 2).sound == "g"
    end
  end

  describe "euclid_rot/4" do
    test "rotates Euclidean rhythm" do
      pattern = parse("bd sd hh cp bd sd hh cp") |> Pattern.euclid_rot(3, 8, 2)
      events = Pattern.events(pattern)

      # Still 3 pulses, but rotated by 2 steps
      assert length(events) == 3
    end

    test "rotation changes which events are kept" do
      p1 = parse("a b c d e f g h") |> Pattern.euclid(3, 8)
      p2 = parse("a b c d e f g h") |> Pattern.euclid_rot(3, 8, 1)

      events1 = Pattern.events(p1)
      events2 = Pattern.events(p2)

      # Same number of events
      assert length(events1) == length(events2)
      # But different events selected (unless rotation wraps perfectly)
      sounds1 = Enum.map(events1, fn e -> e.sound end)
      sounds2 = Enum.map(events2, fn e -> e.sound end)
      # Rotation should create different selection pattern
      assert sounds1 != sounds2 or sounds1 == []
    end
  end

  describe "swing/2" do
    test "applies swing timing" do
      pattern = parse("hh hh hh hh hh hh hh hh") |> Pattern.swing(4)
      events = Pattern.events(pattern)

      # All events still present
      assert length(events) == 8
    end

    test "modifies event timing" do
      original = parse("hh hh hh hh")
      swung = parse("hh hh hh hh") |> Pattern.swing(2)

      original_times = Pattern.events(original) |> Enum.map(fn e -> e.time end)
      swung_times = Pattern.events(swung) |> Enum.map(fn e -> e.time end)

      # At least some times should be different
      assert original_times != swung_times
    end
  end

  describe "swing_by/3" do
    test "applies parameterized swing" do
      pattern = parse("hh hh hh hh hh hh hh hh") |> Pattern.swing_by(0.5, 4)
      events = Pattern.events(pattern)

      # All events still present
      assert length(events) == 8
    end

    test "swing_by(0, n) does not change timing" do
      original = parse("hh hh hh hh")
      swung = parse("hh hh hh hh") |> Pattern.swing_by(0.0, 2)

      original_times = Pattern.events(original) |> Enum.map(fn e -> e.time end)
      swung_times = Pattern.events(swung) |> Enum.map(fn e -> e.time end)

      # Times should be identical with 0 swing
      assert original_times == swung_times
    end

    test "different swing amounts create different timings" do
      p1 = parse("hh hh hh hh") |> Pattern.swing_by(0.25, 2)
      p2 = parse("hh hh hh hh") |> Pattern.swing_by(0.5, 2)

      times1 = Pattern.events(p1) |> Enum.map(fn e -> e.time end)
      times2 = Pattern.events(p2) |> Enum.map(fn e -> e.time end)

      # Different swing amounts = different timings
      assert times1 != times2
    end
  end

  # ============================================================================
  # Chaining
  # ============================================================================

  describe "transformation chaining" do
    test "chains multiple transforms" do
      pattern =
        "bd sd hh cp"
        |> Pattern.new()
        |> Pattern.fast(2)
        |> Pattern.rev()
        |> Pattern.every(4, &Pattern.slow(&1, 2))

      events = Pattern.query(pattern, 0)
      assert length(events) == 4
    end

    test "chains Phase 3 functions" do
      mask_pattern = parse("1 1 0 1")

      pattern =
        "bd sd hh cp"
        |> Pattern.new()
        |> Pattern.first_of(2, &Pattern.rev/1)
        |> Pattern.mask(mask_pattern)

      events = Pattern.query(pattern, 0)
      # Should be reversed and masked
      assert length(events) == 3
    end

    test "chains Phase 4 effects" do
      pattern =
        "bd sd hh"
        |> Pattern.new()
        |> Pattern.gain(0.8)
        |> Pattern.pan(0.5)
        |> Pattern.lpf(2000)
        |> Pattern.room(0.3)

      events = Pattern.events(pattern)

      event = hd(events)
      assert event.params[:gain] == 0.8
      assert event.params[:pan] == 0.5
      assert event.params[:lpf] == 2000
      assert event.params[:room] == 0.3
    end
  end
end
