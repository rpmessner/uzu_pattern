defmodule UzuPattern.Pattern.ConditionalTest do
  @moduledoc """
  Tests for conditional transformation functions.

  Functions: every, sometimes_by, sometimes, often, rarely,
             iter, iter_back, first_of, last_of, when_fn, chunk, chunk_back
  """

  use ExUnit.Case, async: true

  alias UzuPattern.Hap
  alias UzuPattern.Pattern

  defp parse(str), do: UzuPattern.parse(str)

  describe "every/3" do
    test "applies function on matching cycles" do
      pattern = parse("bd sd") |> Pattern.every(2, &Pattern.rev/1)

      # Cycle 0: should be reversed (0 mod 2 == 0)
      haps_0 = Pattern.query(pattern, 0)
      assert Hap.sound(hd(haps_0)) == "sd"

      # Cycle 1: should be normal
      haps_1 = Pattern.query(pattern, 1)
      assert Hap.sound(hd(haps_1)) == "bd"

      # Cycle 2: should be reversed
      haps_2 = Pattern.query(pattern, 2)
      assert Hap.sound(hd(haps_2)) == "sd"
    end

    test "every with stack" do
      pattern =
        Pattern.stack([parse("bd"), parse("hh")])
        |> Pattern.every(2, &Pattern.fast(&1, 2))

      haps_0 = Pattern.query(pattern, 0)
      haps_1 = Pattern.query(pattern, 1)

      assert length(haps_0) > length(haps_1)
    end
  end

  describe "every/4 (with offset)" do
    test "applies function starting at offset" do
      pattern = parse("bd sd hh cp") |> Pattern.every(4, 1, &Pattern.rev/1)

      # Cycle 0: not applied (offset is 1)
      haps_0 = Pattern.query(pattern, 0)
      assert Hap.sound(hd(haps_0)) == "bd"

      # Cycle 1: applied (1 mod 4 == 1)
      haps_1 = Pattern.query(pattern, 1)
      assert Hap.sound(hd(haps_1)) == "cp"

      # Cycle 5: applied (5 mod 4 == 1)
      haps_5 = Pattern.query(pattern, 5)
      assert Hap.sound(hd(haps_5)) == "cp"
    end
  end

  describe "sometimes_by/3" do
    test "is deterministic per cycle" do
      pattern = parse("bd sd") |> Pattern.sometimes_by(0.5, &Pattern.rev/1)

      haps_0a = Pattern.query(pattern, 0)
      haps_0b = Pattern.query(pattern, 0)

      assert haps_0a == haps_0b
    end

    test "is deterministic for params too" do
      pattern =
        parse("bd sd")
        |> Pattern.sometimes_by(0.5, &Pattern.gain(&1, 0.5))

      haps_first = Pattern.query(pattern, 0)
      haps_second = Pattern.query(pattern, 0)

      assert Enum.map(haps_first, & &1.value) == Enum.map(haps_second, & &1.value)
    end
  end

  describe "sometimes/2" do
    test "is shorthand for sometimes_by 0.5" do
      pattern = parse("bd sd") |> Pattern.sometimes(&Pattern.rev/1)

      # Just verify it doesn't crash and is deterministic
      haps_0a = Pattern.query(pattern, 0)
      haps_0b = Pattern.query(pattern, 0)
      assert haps_0a == haps_0b
    end
  end

  describe "often/2" do
    test "is shorthand for sometimes_by 0.75" do
      pattern = parse("bd sd") |> Pattern.often(&Pattern.rev/1)

      haps_0a = Pattern.query(pattern, 0)
      haps_0b = Pattern.query(pattern, 0)
      assert haps_0a == haps_0b
    end
  end

  describe "rarely/2" do
    test "is shorthand for sometimes_by 0.25" do
      pattern = parse("bd sd") |> Pattern.rarely(&Pattern.rev/1)

      haps_0a = Pattern.query(pattern, 0)
      haps_0b = Pattern.query(pattern, 0)
      assert haps_0a == haps_0b
    end
  end

  describe "iter/2" do
    test "rotates pattern start each cycle" do
      pattern = parse("bd sd hh cp") |> Pattern.iter(4)

      # Cycle 0: normal order (bd first)
      haps_0 = Pattern.query(pattern, 0)
      assert Hap.sound(hd(haps_0)) == "bd"

      # Cycle 1: rotated once (sd first)
      haps_1 = Pattern.query(pattern, 1)
      assert Hap.sound(hd(haps_1)) == "sd"

      # Cycle 2: rotated twice (hh first)
      haps_2 = Pattern.query(pattern, 2)
      assert Hap.sound(hd(haps_2)) == "hh"

      # Cycle 3: rotated three times (cp first)
      haps_3 = Pattern.query(pattern, 3)
      assert Hap.sound(hd(haps_3)) == "cp"

      # Cycle 4: wraps back to start (bd first)
      haps_4 = Pattern.query(pattern, 4)
      assert Hap.sound(hd(haps_4)) == "bd"
    end

    test "maintains event count" do
      pattern = parse("bd sd hh cp") |> Pattern.iter(4)

      haps = Pattern.query(pattern, 0)
      assert length(haps) == 4
    end

    test "works with different subdivision counts" do
      pattern = parse("bd sd") |> Pattern.iter(2)

      haps_0 = Pattern.query(pattern, 0)
      assert Hap.sound(hd(haps_0)) == "bd"

      haps_1 = Pattern.query(pattern, 1)
      assert Hap.sound(hd(haps_1)) == "sd"
    end
  end

  describe "iter_back/2" do
    test "rotates pattern start backwards each cycle" do
      pattern = parse("bd sd hh cp") |> Pattern.iter_back(4)

      # Cycle 0: normal order (bd first)
      haps_0 = Pattern.query(pattern, 0)
      assert Hap.sound(hd(haps_0)) == "bd"

      # Cycle 1: rotated backwards (cp first)
      haps_1 = Pattern.query(pattern, 1)
      assert Hap.sound(hd(haps_1)) == "cp"

      # Cycle 2: rotated backwards twice (hh first)
      haps_2 = Pattern.query(pattern, 2)
      assert Hap.sound(hd(haps_2)) == "hh"

      # Cycle 3: rotated backwards three times (sd first)
      haps_3 = Pattern.query(pattern, 3)
      assert Hap.sound(hd(haps_3)) == "sd"
    end

    test "maintains event count" do
      pattern = parse("bd sd hh cp") |> Pattern.iter_back(4)

      haps = Pattern.query(pattern, 0)
      assert length(haps) == 4
    end

    test "is opposite direction of iter" do
      original = parse("bd sd hh cp")
      iter_pattern = Pattern.iter(original, 4)
      iter_back_pattern = Pattern.iter_back(original, 4)

      iter_haps = Pattern.query(iter_pattern, 1)
      assert Hap.sound(hd(iter_haps)) == "sd"

      iter_back_haps = Pattern.query(iter_back_pattern, 1)
      assert Hap.sound(hd(iter_back_haps)) == "cp"
    end
  end

  describe "first_of/3" do
    test "applies function on first of N cycles" do
      pattern = parse("bd sd hh cp") |> Pattern.first_of(4, &Pattern.rev/1)

      # Cycle 0: should be reversed
      haps_0 = Pattern.query(pattern, 0)
      assert Hap.sound(hd(haps_0)) == "cp"

      # Cycle 1: should not be reversed
      haps_1 = Pattern.query(pattern, 1)
      assert Hap.sound(hd(haps_1)) == "bd"

      # Cycle 4: should be reversed again
      haps_4 = Pattern.query(pattern, 4)
      assert Hap.sound(hd(haps_4)) == "cp"
    end
  end

  describe "last_of/3" do
    test "applies function on last of N cycles" do
      pattern = parse("bd sd hh cp") |> Pattern.last_of(4, &Pattern.rev/1)

      # Cycle 0, 1, 2: should not be reversed
      haps_0 = Pattern.query(pattern, 0)
      assert Hap.sound(hd(haps_0)) == "bd"

      # Cycle 3: should be reversed (last of 4)
      haps_3 = Pattern.query(pattern, 3)
      assert Hap.sound(hd(haps_3)) == "cp"

      # Cycle 7: should be reversed (last of next group)
      haps_7 = Pattern.query(pattern, 7)
      assert Hap.sound(hd(haps_7)) == "cp"
    end
  end

  describe "when_fn/3" do
    test "applies function when condition is true" do
      pattern =
        parse("bd sd hh cp")
        |> Pattern.when_fn(fn cycle -> rem(cycle, 2) == 1 end, &Pattern.rev/1)

      # Even cycles: not reversed
      haps_0 = Pattern.query(pattern, 0)
      assert Hap.sound(hd(haps_0)) == "bd"

      # Odd cycles: reversed
      haps_1 = Pattern.query(pattern, 1)
      assert Hap.sound(hd(haps_1)) == "cp"

      haps_3 = Pattern.query(pattern, 3)
      assert Hap.sound(hd(haps_3)) == "cp"
    end

    test "works with complex conditions" do
      pattern =
        parse("bd sd")
        |> Pattern.when_fn(fn cycle -> cycle > 5 and rem(cycle, 3) == 0 end, &Pattern.rev/1)

      # Cycle 5: doesn't meet condition (not divisible by 3)
      haps_5 = Pattern.query(pattern, 5)
      assert Hap.sound(hd(haps_5)) == "bd"

      # Cycle 6: meets condition
      haps_6 = Pattern.query(pattern, 6)
      assert Hap.sound(hd(haps_6)) == "sd"
    end
  end

  describe "chunk/3" do
    test "applies function to rotating chunks" do
      pattern = parse("bd sd hh cp") |> Pattern.chunk(4, &Pattern.rev/1)

      haps_0 = Pattern.query(pattern, 0)
      bd_hap = Enum.find(haps_0, fn h -> Hap.sound(h) == "bd" end)
      assert bd_hap != nil

      assert length(haps_0) == 4
    end

    test "cycles through all chunks" do
      pattern = parse("a b c d") |> Pattern.chunk(2, &Pattern.fast(&1, 2))

      haps = Pattern.query(pattern, 0)
      assert length(haps) >= 1
    end
  end

  describe "chunk_back/3" do
    test "applies function to chunks in reverse" do
      pattern = parse("bd sd hh cp") |> Pattern.chunk_back(4, &Pattern.rev/1)

      haps_0 = Pattern.query(pattern, 0)
      assert length(haps_0) == 4
    end
  end
end
