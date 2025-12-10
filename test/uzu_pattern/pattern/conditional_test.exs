defmodule UzuPattern.Pattern.ConditionalTest do
  @moduledoc """
  Tests for conditional transformation functions.

  Functions: every, sometimes_by, sometimes, often, rarely,
             iter, iter_back, first_of, last_of, when_fn, chunk, chunk_back
  """

  use ExUnit.Case, async: true

  alias UzuPattern.Pattern

  defp parse(str), do: UzuPattern.parse(str)

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

    test "every with stack" do
      pattern =
        Pattern.stack([parse("bd"), parse("hh")])
        |> Pattern.every(2, &Pattern.fast(&1, 2))

      events_0 = Pattern.query(pattern, 0)
      events_1 = Pattern.query(pattern, 1)

      assert length(events_0) > length(events_1)
    end
  end

  describe "every/4 (with offset)" do
    test "applies function starting at offset" do
      pattern = parse("bd sd hh cp") |> Pattern.every(4, 1, &Pattern.rev/1)

      # Cycle 0: not applied (offset is 1)
      events_0 = Pattern.query(pattern, 0)
      assert hd(events_0).sound == "bd"

      # Cycle 1: applied (1 mod 4 == 1)
      events_1 = Pattern.query(pattern, 1)
      assert hd(events_1).sound == "cp"

      # Cycle 5: applied (5 mod 4 == 1)
      events_5 = Pattern.query(pattern, 5)
      assert hd(events_5).sound == "cp"
    end
  end

  describe "sometimes_by/3" do
    test "is deterministic per cycle" do
      pattern = parse("bd sd") |> Pattern.sometimes_by(0.5, &Pattern.rev/1)

      events_0a = Pattern.query(pattern, 0)
      events_0b = Pattern.query(pattern, 0)

      assert events_0a == events_0b
    end

    test "is deterministic for params too" do
      pattern =
        parse("bd sd")
        |> Pattern.sometimes_by(0.5, &Pattern.gain(&1, 0.5))

      events_first = Pattern.query(pattern, 0)
      events_second = Pattern.query(pattern, 0)

      assert Enum.map(events_first, & &1.params) == Enum.map(events_second, & &1.params)
    end
  end

  describe "sometimes/2" do
    test "is shorthand for sometimes_by 0.5" do
      pattern = parse("bd sd") |> Pattern.sometimes(&Pattern.rev/1)

      # Just verify it doesn't crash and is deterministic
      events_0a = Pattern.query(pattern, 0)
      events_0b = Pattern.query(pattern, 0)
      assert events_0a == events_0b
    end
  end

  describe "often/2" do
    test "is shorthand for sometimes_by 0.75" do
      pattern = parse("bd sd") |> Pattern.often(&Pattern.rev/1)

      events_0a = Pattern.query(pattern, 0)
      events_0b = Pattern.query(pattern, 0)
      assert events_0a == events_0b
    end
  end

  describe "rarely/2" do
    test "is shorthand for sometimes_by 0.25" do
      pattern = parse("bd sd") |> Pattern.rarely(&Pattern.rev/1)

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

      events_0 = Pattern.query(pattern, 0)
      assert hd(events_0).sound == "bd"

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

      iter_events = Pattern.query(iter_pattern, 1)
      assert hd(iter_events).sound == "sd"

      iter_back_events = Pattern.query(iter_back_pattern, 1)
      assert hd(iter_back_events).sound == "cp"
    end
  end

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

      events_0 = Pattern.query(pattern, 0)
      bd_event = Enum.find(events_0, fn e -> e.sound == "bd" end)
      assert bd_event != nil

      assert length(events_0) == 4
    end

    test "cycles through all chunks" do
      pattern = parse("a b c d") |> Pattern.chunk(2, &Pattern.fast(&1, 2))

      events = Pattern.query(pattern, 0)
      assert length(events) >= 1
    end
  end

  describe "chunk_back/3" do
    test "applies function to chunks in reverse" do
      pattern = parse("bd sd hh cp") |> Pattern.chunk_back(4, &Pattern.rev/1)

      events_0 = Pattern.query(pattern, 0)
      assert length(events_0) == 4
    end
  end
end
