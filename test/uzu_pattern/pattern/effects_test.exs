defmodule UzuPattern.Pattern.EffectsTest do
  @moduledoc """
  Tests for effect parameter functions.

  Functions: set_param, gain, pan, speed, cut, room, delay, lpf, hpf
  """

  use ExUnit.Case, async: true

  alias UzuPattern.Pattern

  defp parse(str), do: UzuPattern.parse(str)

  describe "set_param/3" do
    test "sets a custom parameter" do
      pattern = parse("bd sd") |> Pattern.set_param(:custom, 42)
      events = Pattern.events(pattern)

      assert Enum.all?(events, fn e -> e.params[:custom] == 42 end)
    end
  end

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

    test "gain of 0.0 is valid" do
      pattern = parse("bd") |> Pattern.gain(0.0)
      [event] = Pattern.query(pattern, 0)
      assert event.params[:gain] == 0.0
    end

    test "later gain overwrites earlier" do
      pattern =
        parse("bd")
        |> Pattern.gain(0.5)
        |> Pattern.gain(0.8)

      [event] = Pattern.query(pattern, 0)
      assert event.params[:gain] == 0.8
    end
  end

  describe "pan/2" do
    test "sets pan parameter within valid range" do
      pattern = parse("bd sd") |> Pattern.pan(0.75)
      events = Pattern.events(pattern)

      assert Enum.all?(events, fn e -> e.params[:pan] == 0.75 end)
    end

    test "accepts -1.0 (left)" do
      pattern = parse("bd") |> Pattern.pan(-1.0)
      events = Pattern.events(pattern)

      assert hd(events).params[:pan] == -1.0
    end

    test "accepts 0.0 (center)" do
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

  describe "parameter chaining" do
    test "chains multiple effects" do
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

    test "multiple parameters stack correctly" do
      pattern =
        parse("bd")
        |> Pattern.gain(0.8)
        |> Pattern.pan(0.5)
        |> Pattern.speed(2.0)
        |> Pattern.lpf(2000)

      [event] = Pattern.query(pattern, 0)

      assert event.params[:gain] == 0.8
      assert event.params[:pan] == 0.5
      assert event.params[:speed] == 2.0
      assert event.params[:lpf] == 2000
    end
  end

  describe "signal modulation" do
    alias UzuPattern.Pattern.Signal

    test "lpf accepts signal pattern for modulation" do
      # Create a 4-event pattern
      pattern = parse("bd sd hh cp")
      # Modulate filter with sine wave: 200-2000 Hz
      modulated = pattern |> Pattern.lpf(Signal.sine() |> Signal.range(200, 2000))

      events = Pattern.query(modulated, 0)

      # Events at times 0, 0.25, 0.5, 0.75
      # Sine at t=0: 0.5 -> 1100 Hz
      # Sine at t=0.25: 1.0 -> 2000 Hz
      # Sine at t=0.5: 0.5 -> 1100 Hz
      # Sine at t=0.75: 0.0 -> 200 Hz
      assert length(events) == 4

      lpf_values = Enum.map(events, & &1.params[:lpf])
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

      events = Pattern.query(modulated, 0)

      # Events at times 0, 0.5
      # Saw at t=0: 0.0 -> 0.2
      # Saw at t=0.5: 0.5 -> 0.6
      gain_values = Enum.map(events, & &1.params[:gain])
      assert_in_delta Enum.at(gain_values, 0), 0.2, 0.01
      assert_in_delta Enum.at(gain_values, 1), 0.6, 0.01
    end

    test "pan accepts signal pattern for modulation" do
      pattern = parse("bd sd hh cp")
      # Modulate pan with triangle wave: -1 to 1 (full stereo sweep)
      modulated = pattern |> Pattern.pan(Signal.tri() |> Signal.range(-1, 1))

      events = Pattern.query(modulated, 0)

      # Events at times 0, 0.25, 0.5, 0.75
      # Tri at t=0: 0.0 -> -1.0 (left)
      # Tri at t=0.25: 0.5 -> 0.0 (center)
      # Tri at t=0.5: 1.0 -> 1.0 (right)
      # Tri at t=0.75: 0.5 -> 0.0 (center)
      pan_values = Enum.map(events, & &1.params[:pan])
      assert_in_delta Enum.at(pan_values, 0), -1.0, 0.01
      assert_in_delta Enum.at(pan_values, 1), 0.0, 0.01
      assert_in_delta Enum.at(pan_values, 2), 1.0, 0.01
      assert_in_delta Enum.at(pan_values, 3), 0.0, 0.01
    end

    test "signal modulation works across multiple cycles" do
      pattern = parse("bd")
      modulated = pattern |> Pattern.lpf(Signal.saw() |> Signal.range(100, 1000))

      # Query multiple cycles - saw resets each cycle
      events_c0 = Pattern.query(modulated, 0)
      events_c1 = Pattern.query(modulated, 1)

      # Saw at t=0: 0.0 -> 100 Hz (resets each cycle)
      assert_in_delta hd(events_c0).params[:lpf], 100.0, 1.0
      assert_in_delta hd(events_c1).params[:lpf], 100.0, 1.0
    end

    test "can mix static and signal parameters" do
      pattern =
        parse("bd sd")
        # Static
        |> Pattern.gain(0.8)
        # Signal
        |> Pattern.lpf(Signal.sine() |> Signal.range(200, 2000))

      events = Pattern.query(pattern, 0)

      # Both events have static gain 0.8
      assert Enum.all?(events, &(&1.params[:gain] == 0.8))

      # But modulated lpf values
      lpf_values = Enum.map(events, & &1.params[:lpf])
      # at t=0
      assert_in_delta Enum.at(lpf_values, 0), 1100.0, 1.0
      # at t=0.5 (sine back to 0.5)
      assert_in_delta Enum.at(lpf_values, 1), 1100.0, 1.0
    end
  end
end
