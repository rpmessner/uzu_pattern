defmodule UzuPattern.Pattern.EffectsTest do
  @moduledoc """
  Tests for effect parameter functions.

  Functions: set_param, gain, pan, speed, cut, room, delay, lpf, hpf
  """

  use ExUnit.Case, async: true

  alias UzuPattern.Hap
  alias UzuPattern.Pattern

  defp parse(str), do: UzuPattern.parse(str)

  describe "set_param/3" do
    test "sets a custom parameter" do
      pattern = parse("bd sd") |> Pattern.set_param(:custom, 42)
      haps = Pattern.events(pattern)

      assert Enum.all?(haps, fn h -> h.value[:custom] == 42 end)
    end
  end

  describe "gain/2" do
    test "sets gain parameter on all events" do
      pattern = parse("bd sd hh") |> Pattern.gain(0.5)
      haps = Pattern.events(pattern)

      assert length(haps) == 3
      assert Enum.all?(haps, fn h -> h.value[:gain] == 0.5 end)
    end

    test "preserves other parameters" do
      pattern = parse("bd") |> Pattern.pan(0.5) |> Pattern.gain(0.8)
      haps = Pattern.events(pattern)

      hap = hd(haps)
      assert hap.value[:gain] == 0.8
      assert hap.value[:pan] == 0.5
    end

    test "gain of 0.0 is valid" do
      pattern = parse("bd") |> Pattern.gain(0.0)
      [hap] = Pattern.query(pattern, 0)
      assert hap.value[:gain] == 0.0
    end

    test "later gain overwrites earlier" do
      pattern =
        parse("bd")
        |> Pattern.gain(0.5)
        |> Pattern.gain(0.8)

      [hap] = Pattern.query(pattern, 0)
      assert hap.value[:gain] == 0.8
    end
  end

  describe "pan/2" do
    test "sets pan parameter within valid range" do
      pattern = parse("bd sd") |> Pattern.pan(0.75)
      haps = Pattern.events(pattern)

      assert Enum.all?(haps, fn h -> h.value[:pan] == 0.75 end)
    end

    test "accepts -1.0 (left)" do
      pattern = parse("bd") |> Pattern.pan(-1.0)
      haps = Pattern.events(pattern)

      assert hd(haps).value[:pan] == -1.0
    end

    test "accepts 0.0 (center)" do
      pattern = parse("bd") |> Pattern.pan(0.0)
      haps = Pattern.events(pattern)

      assert hd(haps).value[:pan] == 0.0
    end

    test "accepts 1.0 (right)" do
      pattern = parse("bd") |> Pattern.pan(1.0)
      haps = Pattern.events(pattern)

      assert hd(haps).value[:pan] == 1.0
    end
  end

  describe "speed/2" do
    test "sets speed parameter" do
      pattern = parse("bd sd") |> Pattern.speed(2.0)
      haps = Pattern.events(pattern)

      assert Enum.all?(haps, fn h -> h.value[:speed] == 2.0 end)
    end

    test "accepts fractional speeds" do
      pattern = parse("bd") |> Pattern.speed(0.5)
      haps = Pattern.events(pattern)

      assert hd(haps).value[:speed] == 0.5
    end
  end

  describe "cut/2" do
    test "sets cut group parameter" do
      pattern = parse("bd sd hh") |> Pattern.cut(1)
      haps = Pattern.events(pattern)

      assert Enum.all?(haps, fn h -> h.value[:cut] == 1 end)
    end

    test "accepts different cut groups" do
      pattern = parse("bd") |> Pattern.cut(5)
      haps = Pattern.events(pattern)

      assert hd(haps).value[:cut] == 5
    end
  end

  describe "room/2" do
    test "sets room (reverb) parameter" do
      pattern = parse("bd sd") |> Pattern.room(0.5)
      haps = Pattern.events(pattern)

      assert Enum.all?(haps, fn h -> h.value[:room] == 0.5 end)
    end

    test "accepts 0.0 (dry)" do
      pattern = parse("bd") |> Pattern.room(0.0)
      haps = Pattern.events(pattern)

      assert hd(haps).value[:room] == 0.0
    end

    test "accepts 1.0 (wet)" do
      pattern = parse("bd") |> Pattern.room(1.0)
      haps = Pattern.events(pattern)

      assert hd(haps).value[:room] == 1.0
    end
  end

  describe "delay/2" do
    test "sets delay parameter" do
      pattern = parse("bd sd") |> Pattern.delay(0.25)
      haps = Pattern.events(pattern)

      assert Enum.all?(haps, fn h -> h.value[:delay] == 0.25 end)
    end
  end

  describe "lpf/2" do
    test "sets low-pass filter frequency" do
      pattern = parse("bd sd") |> Pattern.lpf(1000)
      haps = Pattern.events(pattern)

      assert Enum.all?(haps, fn h -> h.value[:lpf] == 1000 end)
    end

    test "accepts full frequency range" do
      pattern = parse("bd") |> Pattern.lpf(20_000)
      haps = Pattern.events(pattern)

      assert hd(haps).value[:lpf] == 20_000
    end
  end

  describe "hpf/2" do
    test "sets high-pass filter frequency" do
      pattern = parse("bd sd") |> Pattern.hpf(500)
      haps = Pattern.events(pattern)

      assert Enum.all?(haps, fn h -> h.value[:hpf] == 500 end)
    end

    test "accepts full frequency range" do
      pattern = parse("bd") |> Pattern.hpf(20_000)
      haps = Pattern.events(pattern)

      assert hd(haps).value[:hpf] == 20_000
    end
  end

  describe "parameter chaining" do
    test "chains multiple effects" do
      pattern =
        "bd sd hh"
        |> Pattern.new()
        |> Pattern.gain(0.8)
        |> Pattern.pan(0.5)
        |> Pattern.lpf(2000)
        |> Pattern.room(0.3)

      haps = Pattern.events(pattern)

      hap = hd(haps)
      assert hap.value[:gain] == 0.8
      assert hap.value[:pan] == 0.5
      assert hap.value[:lpf] == 2000
      assert hap.value[:room] == 0.3
    end

    test "multiple parameters stack correctly" do
      pattern =
        parse("bd")
        |> Pattern.gain(0.8)
        |> Pattern.pan(0.5)
        |> Pattern.speed(2.0)
        |> Pattern.lpf(2000)

      [hap] = Pattern.query(pattern, 0)

      assert hap.value[:gain] == 0.8
      assert hap.value[:pan] == 0.5
      assert hap.value[:speed] == 2.0
      assert hap.value[:lpf] == 2000
    end
  end

  describe "signal modulation" do
    alias UzuPattern.Pattern.Signal

    test "lpf accepts signal pattern for modulation" do
      # Create a 4-event pattern
      pattern = parse("bd sd hh cp")
      # Modulate filter with sine wave: 200-2000 Hz
      modulated = pattern |> Pattern.lpf(Signal.sine() |> Signal.range(200, 2000))

      haps = Pattern.query(modulated, 0)

      # Events at times 0, 0.25, 0.5, 0.75
      # Sine at t=0: 0.5 -> 1100 Hz
      # Sine at t=0.25: 1.0 -> 2000 Hz
      # Sine at t=0.5: 0.5 -> 1100 Hz
      # Sine at t=0.75: 0.0 -> 200 Hz
      assert length(haps) == 4

      lpf_values = Enum.map(haps, & &1.value[:lpf])
      assert_in_delta Enum.at(lpf_values, 0), 1100.0, 1.0
      assert_in_delta Enum.at(lpf_values, 1), 2000.0, 1.0
      assert_in_delta Enum.at(lpf_values, 2), 1100.0, 1.0
      assert_in_delta Enum.at(lpf_values, 3), 200.0, 1.0
    end

    test "gain accepts signal pattern for modulation" do
      # Create a 2-event pattern
      pattern = parse("bd sd")
      # Modulate gain with saw wave: 0.2-1.0
      modulated = pattern |> Pattern.gain(Signal.saw() |> Signal.range(0.2, 1.0))

      haps = Pattern.query(modulated, 0)

      # Events at times 0, 0.5
      # Saw at t=0: 0.0 -> 0.2
      # Saw at t=0.5: 0.5 -> 0.6
      gain_values = Enum.map(haps, & &1.value[:gain])
      assert_in_delta Enum.at(gain_values, 0), 0.2, 0.01
      assert_in_delta Enum.at(gain_values, 1), 0.6, 0.01
    end

    test "pan accepts signal pattern for modulation" do
      pattern = parse("bd sd hh cp")
      # Modulate pan with triangle wave: -1 to 1 (full stereo sweep)
      modulated = pattern |> Pattern.pan(Signal.tri() |> Signal.range(-1, 1))

      haps = Pattern.query(modulated, 0)

      # Events at times 0, 0.25, 0.5, 0.75
      # Tri at t=0: 0.0 -> -1.0 (left)
      # Tri at t=0.25: 0.5 -> 0.0 (center)
      # Tri at t=0.5: 1.0 -> 1.0 (right)
      # Tri at t=0.75: 0.5 -> 0.0 (center)
      pan_values = Enum.map(haps, & &1.value[:pan])
      assert_in_delta Enum.at(pan_values, 0), -1.0, 0.01
      assert_in_delta Enum.at(pan_values, 1), 0.0, 0.01
      assert_in_delta Enum.at(pan_values, 2), 1.0, 0.01
      assert_in_delta Enum.at(pan_values, 3), 0.0, 0.01
    end

    test "signal modulation works across multiple cycles" do
      pattern = parse("bd")
      modulated = pattern |> Pattern.lpf(Signal.saw() |> Signal.range(100, 1000))

      # Query multiple cycles - saw resets each cycle
      haps_c0 = Pattern.query(modulated, 0)
      haps_c1 = Pattern.query(modulated, 1)

      # Saw at t=0: 0.0 -> 100 Hz (resets each cycle)
      assert_in_delta hd(haps_c0).value[:lpf], 100.0, 1.0
      assert_in_delta hd(haps_c1).value[:lpf], 100.0, 1.0
    end

    test "can mix static and signal parameters" do
      pattern =
        parse("bd sd")
        # Static
        |> Pattern.gain(0.8)
        # Signal
        |> Pattern.lpf(Signal.sine() |> Signal.range(200, 2000))

      haps = Pattern.query(pattern, 0)

      # Both events have static gain 0.8
      assert Enum.all?(haps, &(&1.value[:gain] == 0.8))

      # But modulated lpf values
      lpf_values = Enum.map(haps, & &1.value[:lpf])
      # at t=0
      assert_in_delta Enum.at(lpf_values, 0), 1100.0, 1.0
      # at t=0.5 (sine back to 0.5)
      assert_in_delta Enum.at(lpf_values, 1), 1100.0, 1.0
    end
  end
end
