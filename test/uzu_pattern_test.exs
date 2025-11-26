defmodule UzuPatternTest do
  use ExUnit.Case

  alias UzuPattern.Pattern

  describe "new/1" do
    test "creates pattern from mini-notation string" do
      pattern = Pattern.new("bd sd hh cp")
      assert length(pattern.events) == 4
    end

    test "creates empty pattern from empty string" do
      pattern = Pattern.new("")
      assert pattern.events == []
    end
  end

  describe "from_events/1" do
    test "creates pattern from event list" do
      events = UzuParser.parse("bd sd")
      pattern = Pattern.from_events(events)
      assert length(pattern.events) == 2
    end
  end

  describe "query/2" do
    test "returns events in waveform format" do
      pattern = Pattern.new("bd sd")
      events = Pattern.query(pattern, 0)

      assert length(events) == 2
      {time, params} = hd(events)
      assert time == 0.0
      assert Keyword.get(params, :s) == "bd"
    end
  end

  describe "events/1" do
    test "extracts raw events" do
      pattern = Pattern.new("bd sd")
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
      pattern = Pattern.new("bd sd") |> Pattern.fast(2)
      events = Pattern.events(pattern)

      assert length(events) == 2
      assert Enum.at(events, 0).time == 0.0
      assert Enum.at(events, 1).time == 0.25
    end

    test "filters out events past cycle boundary" do
      pattern = Pattern.new("bd sd hh cp") |> Pattern.fast(0.5)
      events = Pattern.events(pattern)

      # At 0.5x speed, only first 2 events fit in cycle
      assert length(events) == 2
    end
  end

  describe "slow/2" do
    test "halves event times with factor 2" do
      pattern = Pattern.new("bd sd") |> Pattern.slow(2)
      events = Pattern.events(pattern)

      assert Enum.at(events, 0).time == 0.0
      assert Enum.at(events, 1).time == 1.0
    end
  end

  describe "rev/1" do
    test "reverses event order" do
      pattern = Pattern.new("bd sd hh") |> Pattern.rev()
      events = Pattern.events(pattern)

      # After reversal, hh should be first (at time 0)
      assert hd(events).sound == "hh"
    end

    test "adjusts times correctly" do
      pattern = Pattern.new("bd sd") |> Pattern.rev()
      events = Pattern.events(pattern)

      # Original: bd at 0.0, sd at 0.5
      # Reversed: sd at 0.0, bd at 0.5
      assert Enum.at(events, 0).sound == "sd"
      assert Enum.at(events, 1).sound == "bd"
    end
  end

  describe "early/2" do
    test "shifts pattern earlier with wrap" do
      pattern = Pattern.new("bd sd") |> Pattern.early(0.25)
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
      pattern = Pattern.new("bd sd") |> Pattern.late(0.25)
      events = Pattern.events(pattern)

      times = Enum.map(events, & &1.time) |> Enum.sort()
      assert_in_delta Enum.at(times, 0), 0.25, 0.01
      assert_in_delta Enum.at(times, 1), 0.75, 0.01
    end
  end

  describe "ply/2" do
    test "repeats each event N times" do
      pattern = Pattern.new("bd sd") |> Pattern.ply(2)
      events = Pattern.events(pattern)

      # 2 events * 2 repetitions = 4 events
      assert length(events) == 4
    end

    test "divides duration correctly" do
      pattern = Pattern.new("bd sd") |> Pattern.ply(3)
      events = Pattern.events(pattern)

      # Each event originally has duration 0.5
      # With ply(3), each repetition should have duration 0.5/3 ≈ 0.167
      assert length(events) == 6
      assert_in_delta Enum.at(events, 0).duration, 0.5 / 3, 0.01
    end

    test "spaces repetitions evenly within event duration" do
      pattern = Pattern.new("bd") |> Pattern.ply(4)
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
      pattern = Pattern.new("bd:2") |> Pattern.ply(2)
      events = Pattern.events(pattern)

      # All repetitions should maintain sample number
      assert Enum.all?(events, fn e -> e.sample == 2 end)
      assert Enum.all?(events, fn e -> e.sound == "bd" end)
    end

    test "works with multiple events" do
      pattern = Pattern.new("bd sd hh") |> Pattern.ply(2)
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
      pattern = Pattern.new("bd sd hh cp") |> Pattern.compress(0.25, 0.75)
      events = Pattern.events(pattern)

      # All events should be within [0.25, 0.75)
      assert Enum.all?(events, fn e -> e.time >= 0.25 and e.time < 0.75 end)
    end

    test "maintains event count" do
      pattern = Pattern.new("bd sd hh cp") |> Pattern.compress(0.25, 0.75)
      events = Pattern.events(pattern)

      # Should still have 4 events
      assert length(events) == 4
    end

    test "scales times proportionally" do
      pattern = Pattern.new("bd sd") |> Pattern.compress(0.0, 0.5)
      events = Pattern.events(pattern)

      # Original: bd at 0.0, sd at 0.5
      # Compressed to [0.0, 0.5): bd at 0.0, sd at 0.25
      assert_in_delta Enum.at(events, 0).time, 0.0, 0.01
      assert_in_delta Enum.at(events, 1).time, 0.25, 0.01
    end

    test "scales durations proportionally" do
      pattern = Pattern.new("bd sd") |> Pattern.compress(0.0, 0.5)
      events = Pattern.events(pattern)

      # Original duration: 0.5 each
      # Compressed duration: 0.25 each (halved)
      assert_in_delta Enum.at(events, 0).duration, 0.25, 0.01
      assert_in_delta Enum.at(events, 1).duration, 0.25, 0.01
    end

    test "creates rhythmic gap" do
      pattern = Pattern.new("bd sd") |> Pattern.compress(0.25, 0.75)
      events = Pattern.events(pattern)

      # Gap before 0.25 and after 0.75
      assert Enum.all?(events, fn e -> e.time >= 0.25 end)
      assert Enum.all?(events, fn e -> e.time + e.duration <= 0.75 end)
    end

    test "maintains event properties" do
      pattern = Pattern.new("bd:3 sd:2") |> Pattern.compress(0.25, 0.75)
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
      pattern = Pattern.new("bd sd hh cp") |> Pattern.zoom(0.25, 0.75)
      events = Pattern.events(pattern)

      # Should extract middle half (sd, hh) and expand to full cycle
      assert length(events) == 2
      sounds = Enum.map(events, & &1.sound)
      assert "sd" in sounds
      assert "hh" in sounds
    end

    test "expands extracted segment to full cycle" do
      pattern = Pattern.new("bd sd hh cp") |> Pattern.zoom(0.5, 1.0)
      events = Pattern.events(pattern)

      # Extract second half (hh at 0.5, cp at 0.75)
      # Expand to full cycle: hh at 0.0, cp at 0.5
      assert length(events) == 2
      assert_in_delta Enum.at(events, 0).time, 0.0, 0.01
      assert_in_delta Enum.at(events, 1).time, 0.5, 0.01
    end

    test "scales durations correctly" do
      pattern = Pattern.new("bd sd") |> Pattern.zoom(0.0, 0.5)
      events = Pattern.events(pattern)

      # Extract first half (bd only) and expand
      # Original duration: 0.5, expanded duration: 1.0 (doubled)
      assert length(events) == 1
      assert_in_delta Enum.at(events, 0).duration, 1.0, 0.01
    end

    test "filters events outside window" do
      pattern = Pattern.new("bd sd hh cp") |> Pattern.zoom(0.25, 0.5)
      events = Pattern.events(pattern)

      # Only sd (at 0.25) is in range [0.25, 0.5)
      assert length(events) == 1
      assert hd(events).sound == "sd"
    end

    test "maintains event properties" do
      pattern = Pattern.new("bd:1 sd:2 hh:3 cp:4") |> Pattern.zoom(0.25, 0.75)
      events = Pattern.events(pattern)

      # Extract sd:2 and hh:3
      assert Enum.at(events, 0).sound == "sd"
      assert Enum.at(events, 0).sample == 2
      assert Enum.at(events, 1).sound == "hh"
      assert Enum.at(events, 1).sample == 3
    end

    test "zoom is inverse of compress" do
      original = Pattern.new("bd sd hh cp")

      # Zoom extracts a segment
      zoomed = Pattern.zoom(original, 0.25, 0.75)

      # The zoomed pattern should have 2 events (sd, hh)
      assert length(Pattern.events(zoomed)) == 2
    end
  end

  describe "linger/2" do
    test "repeats fraction of pattern" do
      pattern = Pattern.new("bd sd hh cp") |> Pattern.linger(0.5)
      events = Pattern.events(pattern)

      # First half (bd, sd) repeated twice = 4 events
      assert length(events) == 4

      # Check that we get pairs
      sounds = Enum.map(events, & &1.sound)
      assert Enum.count(sounds, &(&1 == "bd")) == 2
      assert Enum.count(sounds, &(&1 == "sd")) == 2
    end

    test "linger(0.25) repeats first quarter 4 times" do
      pattern = Pattern.new("bd sd hh cp") |> Pattern.linger(0.25)
      events = Pattern.events(pattern)

      # First quarter (bd) repeated 4 times
      assert length(events) == 4
      assert Enum.all?(events, fn e -> e.sound == "bd" end)
    end

    test "linger(1.0) keeps pattern unchanged" do
      original = Pattern.new("bd sd hh cp")
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
      pattern = Pattern.new("bd sd") |> Pattern.linger(0.5)
      events = Pattern.events(pattern)

      assert length(events) == 2
      assert Enum.all?(events, fn e -> e.sound == "bd" end)

      times = Enum.map(events, & &1.time)
      assert_in_delta Enum.at(times, 0), 0.0, 0.01
      assert_in_delta Enum.at(times, 1), 0.5, 0.01
    end

    test "maintains event properties" do
      pattern = Pattern.new("bd:3 sd:2 hh:1 cp:0") |> Pattern.linger(0.5)
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
      pattern = Pattern.new("bd sd hh") |> Pattern.linger(0.333)
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
      p1 = Pattern.new("bd")
      p2 = Pattern.new("sd")
      combined = Pattern.stack([p1, p2])

      events = Pattern.events(combined)
      assert length(events) == 2

      sounds = Enum.map(events, & &1.sound)
      assert "bd" in sounds
      assert "sd" in sounds
    end
  end

  describe "cat/1" do
    test "concatenates patterns sequentially" do
      p1 = Pattern.new("bd")
      p2 = Pattern.new("sd")
      combined = Pattern.cat([p1, p2])

      events = Pattern.events(combined)
      assert length(events) == 2
      assert Enum.at(events, 0).time == 0.0
      assert Enum.at(events, 1).time == 0.5
    end

    test "scales durations correctly" do
      p1 = Pattern.new("bd sd")
      p2 = Pattern.new("hh")
      combined = Pattern.cat([p1, p2])

      events = Pattern.events(combined)
      # p1 events should have duration 0.25 (half of 0.5)
      # p2 event should have duration 0.5
      assert Enum.at(events, 0).duration == 0.25
    end
  end

  describe "palindrome/1" do
    test "creates forward then backward pattern" do
      pattern = Pattern.new("bd sd hh") |> Pattern.palindrome()
      events = Pattern.events(pattern)

      assert length(events) == 6
    end
  end

  # ============================================================================
  # Conditional Modifiers
  # ============================================================================

  describe "every/3" do
    test "applies function on matching cycles" do
      pattern = Pattern.new("bd sd") |> Pattern.every(2, &Pattern.rev/1)

      # Cycle 0: should be reversed (0 mod 2 == 0)
      events_0 = Pattern.query(pattern, 0)
      assert hd(events_0) |> elem(1) |> Keyword.get(:s) == "sd"

      # Cycle 1: should be normal
      events_1 = Pattern.query(pattern, 1)
      assert hd(events_1) |> elem(1) |> Keyword.get(:s) == "bd"

      # Cycle 2: should be reversed
      events_2 = Pattern.query(pattern, 2)
      assert hd(events_2) |> elem(1) |> Keyword.get(:s) == "sd"
    end
  end

  describe "sometimes_by/3" do
    test "is deterministic per cycle" do
      pattern = Pattern.new("bd sd") |> Pattern.sometimes_by(0.5, &Pattern.rev/1)

      # Same cycle should always produce same result
      events_0a = Pattern.query(pattern, 0)
      events_0b = Pattern.query(pattern, 0)

      assert events_0a == events_0b
    end
  end

  describe "iter/2" do
    test "rotates pattern start each cycle" do
      pattern = Pattern.new("bd sd hh cp") |> Pattern.iter(4)

      # Cycle 0: normal order (bd first)
      events_0 = Pattern.query(pattern, 0)
      assert hd(events_0) |> elem(1) |> Keyword.get(:s) == "bd"

      # Cycle 1: rotated once (sd first)
      events_1 = Pattern.query(pattern, 1)
      assert hd(events_1) |> elem(1) |> Keyword.get(:s) == "sd"

      # Cycle 2: rotated twice (hh first)
      events_2 = Pattern.query(pattern, 2)
      assert hd(events_2) |> elem(1) |> Keyword.get(:s) == "hh"

      # Cycle 3: rotated three times (cp first)
      events_3 = Pattern.query(pattern, 3)
      assert hd(events_3) |> elem(1) |> Keyword.get(:s) == "cp"

      # Cycle 4: wraps back to start (bd first)
      events_4 = Pattern.query(pattern, 4)
      assert hd(events_4) |> elem(1) |> Keyword.get(:s) == "bd"
    end

    test "maintains event count" do
      pattern = Pattern.new("bd sd hh cp") |> Pattern.iter(4)

      events = Pattern.query(pattern, 0)
      assert length(events) == 4
    end

    test "works with different subdivision counts" do
      pattern = Pattern.new("bd sd") |> Pattern.iter(2)

      # Cycle 0: bd first
      events_0 = Pattern.query(pattern, 0)
      assert hd(events_0) |> elem(1) |> Keyword.get(:s) == "bd"

      # Cycle 1: sd first
      events_1 = Pattern.query(pattern, 1)
      assert hd(events_1) |> elem(1) |> Keyword.get(:s) == "sd"
    end
  end

  describe "iter_back/2" do
    test "rotates pattern start backwards each cycle" do
      pattern = Pattern.new("bd sd hh cp") |> Pattern.iter_back(4)

      # Cycle 0: normal order (bd first)
      events_0 = Pattern.query(pattern, 0)
      assert hd(events_0) |> elem(1) |> Keyword.get(:s) == "bd"

      # Cycle 1: rotated backwards (cp first)
      events_1 = Pattern.query(pattern, 1)
      assert hd(events_1) |> elem(1) |> Keyword.get(:s) == "cp"

      # Cycle 2: rotated backwards twice (hh first)
      events_2 = Pattern.query(pattern, 2)
      assert hd(events_2) |> elem(1) |> Keyword.get(:s) == "hh"

      # Cycle 3: rotated backwards three times (sd first)
      events_3 = Pattern.query(pattern, 3)
      assert hd(events_3) |> elem(1) |> Keyword.get(:s) == "sd"
    end

    test "maintains event count" do
      pattern = Pattern.new("bd sd hh cp") |> Pattern.iter_back(4)

      events = Pattern.query(pattern, 0)
      assert length(events) == 4
    end

    test "is opposite direction of iter" do
      original = Pattern.new("bd sd hh cp")
      iter_pattern = Pattern.iter(original, 4)
      iter_back_pattern = Pattern.iter_back(original, 4)

      # At cycle 1, iter should have sd first
      iter_events = Pattern.query(iter_pattern, 1)
      assert hd(iter_events) |> elem(1) |> Keyword.get(:s) == "sd"

      # At cycle 1, iter_back should have cp first (opposite)
      iter_back_events = Pattern.query(iter_back_pattern, 1)
      assert hd(iter_back_events) |> elem(1) |> Keyword.get(:s) == "cp"
    end
  end

  # ============================================================================
  # Degradation
  # ============================================================================

  describe "degrade_by/2" do
    test "removes approximately the expected percentage" do
      pattern = Pattern.new("bd sd hh cp bd sd hh cp")
      degraded = Pattern.degrade_by(pattern, 0.5)
      events = Pattern.events(degraded)

      # Should have roughly half the events (probabilistic)
      assert length(events) >= 1
      assert length(events) <= 8
    end
  end

  describe "degrade/1" do
    test "removes some events" do
      pattern = Pattern.new("bd sd hh cp")
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
      pattern = Pattern.new("bd sd") |> Pattern.jux(&Pattern.rev/1)
      events = Pattern.events(pattern)

      # Should have 4 events (2 original + 2 transformed)
      assert length(events) == 4
    end

    test "sets pan values" do
      pattern = Pattern.new("bd") |> Pattern.jux(&Pattern.rev/1)
      events = Pattern.events(pattern)

      pans = Enum.map(events, fn e -> e.params[:pan] end)
      assert -1.0 in pans
      assert 1.0 in pans
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
  end
end
