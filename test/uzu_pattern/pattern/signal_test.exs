defmodule UzuPattern.Pattern.SignalTest do
  use ExUnit.Case, async: true

  alias UzuPattern.Hap
  alias UzuPattern.Pattern
  alias UzuPattern.Pattern.Signal

  describe "signal/1" do
    test "creates a pattern from a time function" do
      sig = Signal.signal(fn t -> t * 2 end)
      [hap] = Pattern.query(sig, 0)

      assert hap.value.value == 0.0
      assert Hap.continuous?(hap)
      assert hap.part.begin == 0.0
      assert hap.part.end - hap.part.begin == 1.0
    end

    test "samples at cycle time via sample_at" do
      sig = Signal.signal(fn t -> t end)

      # sample_at allows fractional times
      assert_in_delta Signal.sample_at(sig, 0), 0.0, 0.001
      assert_in_delta Signal.sample_at(sig, 1), 1.0, 0.001
      assert_in_delta Signal.sample_at(sig, 2), 2.0, 0.001
      assert_in_delta Signal.sample_at(sig, 0.5), 0.5, 0.001
    end

    test "Pattern.query returns value at integer cycle" do
      sig = Signal.signal(fn t -> t end)

      [e0] = Pattern.query(sig, 0)
      [e1] = Pattern.query(sig, 1)
      [e2] = Pattern.query(sig, 2)

      assert e0.value.value == 0.0
      assert e1.value.value == 1.0
      assert e2.value.value == 2.0
    end
  end

  describe "sine/0" do
    test "oscillates between 0 and 1" do
      sig = Signal.sine()

      # At t=0, sin(0) = 0, scaled to 0.5
      assert_in_delta Signal.sample_at(sig, 0), 0.5, 0.001

      # At t=0.25, sin(π/2) = 1, scaled to 1.0
      assert_in_delta Signal.sample_at(sig, 0.25), 1.0, 0.001

      # At t=0.5, sin(π) = 0, scaled to 0.5
      assert_in_delta Signal.sample_at(sig, 0.5), 0.5, 0.001

      # At t=0.75, sin(3π/2) = -1, scaled to 0.0
      assert_in_delta Signal.sample_at(sig, 0.75), 0.0, 0.001
    end
  end

  describe "saw/0" do
    test "ramps from 0 to 1 each cycle" do
      sig = Signal.saw()

      assert_in_delta Signal.sample_at(sig, 0), 0.0, 0.001
      assert_in_delta Signal.sample_at(sig, 0.5), 0.5, 0.001
      assert_in_delta Signal.sample_at(sig, 0.99), 0.99, 0.001

      # Wraps back to 0 at integer cycles
      assert_in_delta Signal.sample_at(sig, 1), 0.0, 0.001
    end
  end

  describe "tri/0" do
    test "ramps up then down" do
      sig = Signal.tri()

      assert_in_delta Signal.sample_at(sig, 0), 0.0, 0.001
      assert_in_delta Signal.sample_at(sig, 0.25), 0.5, 0.001
      assert_in_delta Signal.sample_at(sig, 0.5), 1.0, 0.001
      assert_in_delta Signal.sample_at(sig, 0.75), 0.5, 0.001
    end
  end

  describe "square/0" do
    test "alternates between 0 and 1" do
      sig = Signal.square()

      assert Signal.sample_at(sig, 0) == 0.0
      assert Signal.sample_at(sig, 0.25) == 0.0
      assert Signal.sample_at(sig, 0.5) == 1.0
      assert Signal.sample_at(sig, 0.75) == 1.0
    end
  end

  describe "rand/0" do
    test "produces values between 0 and 1" do
      sig = Signal.rand()

      for cycle <- 0..10 do
        [hap] = Pattern.query(sig, cycle)
        assert hap.value.value >= 0.0
        assert hap.value.value <= 1.0
      end
    end

    test "is deterministic by cycle" do
      sig = Signal.rand()

      [e1] = Pattern.query(sig, 5)
      [e2] = Pattern.query(sig, 5)

      assert e1.value.value == e2.value.value
    end
  end

  describe "irand/1" do
    test "produces integers from 0 to n-1" do
      sig = Signal.irand(4)

      for cycle <- 0..20 do
        [hap] = Pattern.query(sig, cycle)
        assert hap.value.value in [0, 1, 2, 3]
      end
    end
  end

  describe "range/3" do
    test "scales values from [0,1] to [min,max]" do
      sig = Signal.sine() |> Signal.range(200, 2000)

      # At t=0, sine is 0.5, scaled: 0.5 * 1800 + 200 = 1100
      assert_in_delta Signal.sample_at(sig, 0), 1100.0, 1.0

      # At t=0.25, sine is 1.0, scaled: 1.0 * 1800 + 200 = 2000
      assert_in_delta Signal.sample_at(sig, 0.25), 2000.0, 1.0

      # At t=0.75, sine is 0.0, scaled: 0.0 * 1800 + 200 = 200
      assert_in_delta Signal.sample_at(sig, 0.75), 200.0, 1.0
    end
  end

  describe "segment/2" do
    test "discretizes signal into n events per cycle" do
      sig = Signal.saw() |> Signal.segment(4)

      haps = Pattern.query(sig, 0)

      assert length(haps) == 4

      times = Enum.map(haps, & &1.part.begin)
      assert times == [0.0, 0.25, 0.5, 0.75]

      values = Enum.map(haps, & &1.value.value)
      assert_in_delta Enum.at(values, 0), 0.0, 0.001
      assert_in_delta Enum.at(values, 1), 0.25, 0.001
      assert_in_delta Enum.at(values, 2), 0.5, 0.001
      assert_in_delta Enum.at(values, 3), 0.75, 0.001
    end

    test "creates discrete (non-continuous) events" do
      sig = Signal.sine() |> Signal.segment(8)
      haps = Pattern.query(sig, 0)

      for hap <- haps do
        assert Hap.discrete?(hap)
      end
    end
  end

  describe "sample_at/2" do
    test "samples signal at specific time" do
      sig = Signal.saw()

      assert_in_delta Signal.sample_at(sig, 0.0), 0.0, 0.001
      assert_in_delta Signal.sample_at(sig, 0.5), 0.5, 0.001
      assert_in_delta Signal.sample_at(sig, 1.0), 0.0, 0.001
      assert_in_delta Signal.sample_at(sig, 1.5), 0.5, 0.001
    end
  end

  describe "composition with Pattern.fast/slow" do
    test "fast speeds up signal - more events per cycle" do
      # For now, fast/slow work on the query function, not the time function
      # When we use segment, we can see the effect
      sig = Signal.saw() |> Pattern.fast(2) |> Signal.segment(4)

      # fast(2) then segment(4) means the saw cycles twice in 4 samples
      haps = Pattern.query(sig, 0)
      assert length(haps) == 4
    end

    test "slow slows down signal - fewer events per cycle" do
      sig = Signal.saw() |> Pattern.slow(2) |> Signal.segment(4)

      haps = Pattern.query(sig, 0)
      assert length(haps) == 4

      # At cycle 0 (slow 2), pattern queries cycle 0
      # At cycle 1 (slow 2), pattern queries cycle 0 still (since 1/2 = 0)
      # The saw values should be stretched
    end
  end

  describe "signal as effect parameter (future integration)" do
    test "sample_at works for effect parameter sampling" do
      # When effects like lpf take a signal, they sample at each event onset
      sig = Signal.sine() |> Signal.range(200, 2000)

      # Simulating what effects would do: sample signal at event onset times
      event_times = [0.0, 0.25, 0.5, 0.75]

      values =
        Enum.map(event_times, fn t ->
          Signal.sample_at(sig, t)
        end)

      # Values should follow sine wave scaled to 200-2000
      # sine(0) = 0.5 -> 1100
      assert_in_delta Enum.at(values, 0), 1100.0, 1.0
      # sine(0.25) = 1.0 -> 2000
      assert_in_delta Enum.at(values, 1), 2000.0, 1.0
      # sine(0.5) = 0.5 -> 1100
      assert_in_delta Enum.at(values, 2), 1100.0, 1.0
      # sine(0.75) = 0.0 -> 200
      assert_in_delta Enum.at(values, 3), 200.0, 1.0
    end
  end
end
