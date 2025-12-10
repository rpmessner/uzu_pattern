defmodule UzuPattern.PatternTest do
  @moduledoc """
  Tests for core Pattern functionality.

  Covers: constructors, combinators, query functions, transport serialization
  """

  use ExUnit.Case, async: true

  alias UzuPattern.Pattern

  defp parse(str), do: UzuPattern.parse(str)

  # ============================================================================
  # Constructors
  # ============================================================================

  describe "new/1 with query function" do
    test "creates pattern from query function" do
      pattern = Pattern.new(fn _cycle -> [%UzuPattern.Event{sound: "bd", time: 0.0, duration: 1.0}] end)
      events = Pattern.events(pattern)

      assert length(events) == 1
      assert hd(events).sound == "bd"
    end
  end

  describe "new/1 with string" do
    test "creates pattern from mini-notation string" do
      pattern = Pattern.new("bd sd hh cp")
      events = Pattern.events(pattern)

      assert length(events) == 4
    end

    test "creates empty pattern from empty string" do
      pattern = parse("")
      events = Pattern.events(pattern)

      assert events == []
    end
  end

  describe "pure/1" do
    test "creates single event pattern" do
      pattern = Pattern.pure("bd")
      events = Pattern.events(pattern)

      assert length(events) == 1
      assert hd(events).sound == "bd"
      assert hd(events).time == 0.0
      assert hd(events).duration == 1.0
    end

    test "accepts sample option" do
      pattern = Pattern.pure("bd", sample: 2)
      events = Pattern.events(pattern)

      assert hd(events).sample == 2
    end

    test "accepts params option" do
      pattern = Pattern.pure("bd", params: %{gain: 0.5})
      events = Pattern.events(pattern)

      assert hd(events).params[:gain] == 0.5
    end
  end

  describe "silence/0" do
    test "creates empty pattern" do
      pattern = Pattern.silence()

      assert Pattern.query(pattern, 0) == []
      assert Pattern.query(pattern, 100) == []
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

  # ============================================================================
  # Pattern Combinators
  # ============================================================================

  describe "slowcat/1" do
    test "alternates patterns across cycles" do
      p1 = parse("bd")
      p2 = parse("sd")
      combined = Pattern.slowcat([p1, p2])

      events_0 = Pattern.query(combined, 0)
      assert length(events_0) == 1
      assert hd(events_0).sound == "bd"

      events_1 = Pattern.query(combined, 1)
      assert length(events_1) == 1
      assert hd(events_1).sound == "sd"
    end

    test "wraps around after all patterns" do
      p1 = parse("bd")
      p2 = parse("sd")
      combined = Pattern.cat([p1, p2])

      events_2 = Pattern.query(combined, 2)
      assert hd(events_2).sound == "bd"
    end

    test "cycles correctly at high numbers" do
      pattern =
        Pattern.slowcat([
          Pattern.pure("a"),
          Pattern.pure("b"),
          Pattern.pure("c")
        ])

      assert hd(Pattern.query(pattern, 0)).sound == "a"
      assert hd(Pattern.query(pattern, 1)).sound == "b"
      assert hd(Pattern.query(pattern, 2)).sound == "c"
      assert hd(Pattern.query(pattern, 3)).sound == "a"
      assert hd(Pattern.query(pattern, 99)).sound == "a"
      assert hd(Pattern.query(pattern, 100)).sound == "b"
      assert hd(Pattern.query(pattern, 101)).sound == "c"
    end

    test "slowcat with single pattern" do
      pattern = Pattern.slowcat([Pattern.pure("bd")])
      events = Pattern.query(pattern, 0)
      assert length(events) == 1
    end

    test "deeply nested slowcat" do
      inner = Pattern.slowcat([Pattern.pure("a"), Pattern.pure("b")])
      middle = Pattern.slowcat([inner, Pattern.pure("c")])
      outer = Pattern.slowcat([middle, Pattern.pure("d")])

      assert hd(Pattern.query(outer, 0)).sound == "a"
      assert hd(Pattern.query(outer, 1)).sound == "d"
    end
  end

  describe "cat/1" do
    test "is alias for slowcat" do
      p1 = parse("bd")
      p2 = parse("sd")
      combined = Pattern.cat([p1, p2])

      events_0 = Pattern.query(combined, 0)
      events_1 = Pattern.query(combined, 1)

      assert hd(events_0).sound == "bd"
      assert hd(events_1).sound == "sd"
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
      assert Enum.at(events, 0).duration == 0.25
    end

    test "fastcat with single pattern" do
      pattern = Pattern.fastcat([Pattern.pure("bd")])
      events = Pattern.query(pattern, 0)
      assert length(events) == 1
    end
  end

  describe "sequence/1" do
    test "is alias for fastcat" do
      p1 = parse("bd")
      p2 = parse("sd")
      combined = Pattern.sequence([p1, p2])

      events = Pattern.events(combined)
      assert length(events) == 2
    end
  end

  describe "append/2" do
    test "appends pattern after first" do
      p1 = parse("bd sd")
      p2 = parse("hh cp")
      pattern = Pattern.append(p1, p2)

      events_0 = Pattern.query(pattern, 0)
      events_1 = Pattern.query(pattern, 1)

      assert length(events_0) == 2
      sounds_0 = Enum.map(events_0, & &1.sound)
      assert "bd" in sounds_0

      assert length(events_1) == 2
      sounds_1 = Enum.map(events_1, & &1.sound)
      assert "hh" in sounds_1
    end
  end

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

    test "stack of empty patterns" do
      pattern = Pattern.stack([Pattern.silence(), Pattern.silence()])
      assert Pattern.query(pattern, 0) == []
    end

    test "stack of stacks" do
      inner1 = Pattern.stack([Pattern.pure("a"), Pattern.pure("b")])
      inner2 = Pattern.stack([Pattern.pure("c"), Pattern.pure("d")])
      outer = Pattern.stack([inner1, inner2])

      events = Pattern.query(outer, 0)
      sounds = Enum.map(events, & &1.sound) |> Enum.sort()
      assert sounds == ["a", "b", "c", "d"]
    end
  end

  # ============================================================================
  # Query Functions
  # ============================================================================

  describe "query/2" do
    test "returns Event structs" do
      pattern = parse("bd sd")
      events = Pattern.query(pattern, 0)

      assert length(events) == 2
      event = hd(events)
      assert event.sound == "bd"
      assert event.time == 0.0
    end

    test "returns empty for nil pattern" do
      assert Pattern.query(nil, 0) == []
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
    test "extracts raw events for cycle 0" do
      pattern = parse("bd sd")
      events = Pattern.events(pattern)

      assert length(events) == 2
      assert hd(events).sound == "bd"
    end
  end

  # ============================================================================
  # Transport Serialization
  # ============================================================================

  describe "expand_for_transport/2" do
    test "expands pattern for specified cycles" do
      p = Pattern.slowcat([Pattern.pure("bd"), Pattern.pure("sd")])
      expanded = Pattern.expand_for_transport(p, num_cycles: 4)

      assert Map.keys(expanded.cycles) == [0, 1, 2, 3]
      assert hd(expanded.cycles[0]).s == "bd"
      assert hd(expanded.cycles[1]).s == "sd"
    end

    test "defaults to 16 cycles" do
      p = Pattern.pure("bd")
      expanded = Pattern.expand_for_transport(p)

      assert expanded.num_cycles == 16
      assert length(Map.keys(expanded.cycles)) == 16
    end
  end

  describe "detect_period/2" do
    test "detects period of alternating pattern" do
      p = Pattern.slowcat([Pattern.pure("bd"), Pattern.pure("sd")])
      assert Pattern.detect_period(p) == 2
    end

    test "detects period of constant pattern" do
      p = Pattern.pure("bd")
      assert Pattern.detect_period(p) == 1
    end

    test "detects period of three-element alternation" do
      p = Pattern.slowcat([Pattern.pure("a"), Pattern.pure("b"), Pattern.pure("c")])
      assert Pattern.detect_period(p) == 3
    end
  end

  describe "expand_for_transport_auto/2" do
    test "auto-detects period" do
      p = Pattern.slowcat([Pattern.pure("bd"), Pattern.pure("sd")])
      expanded = Pattern.expand_for_transport_auto(p)

      assert expanded.num_cycles == 2
      assert expanded.period == 2
    end
  end

  # ============================================================================
  # Cross-Cycle Behavior
  # ============================================================================

  describe "large cycle numbers" do
    test "pattern remains consistent at high cycle numbers" do
      pattern = parse("bd sd hh cp")

      for cycle <- [0, 1, 8, 9, 10, 100, 1000] do
        events = Pattern.query(pattern, cycle)
        assert length(events) == 4, "Failed at cycle #{cycle}"
      end
    end
  end

  # ============================================================================
  # Transformation Chaining
  # ============================================================================

  describe "transformation chaining" do
    test "chains multiple transforms" do
      pattern =
        "bd sd hh cp"
        |> Pattern.new()
        |> Pattern.fast(2)
        |> Pattern.rev()
        |> Pattern.every(2, &Pattern.gain(&1, 0.5))

      events = Pattern.query(pattern, 0)
      assert length(events) == 8
      assert Enum.all?(events, fn e -> e.params[:gain] == 0.5 end)

      events_1 = Pattern.query(pattern, 1)
      assert length(events_1) == 8
      assert Enum.all?(events_1, fn e -> e.params[:gain] == nil end)
    end
  end
end
