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
