defmodule UzuPattern.Pattern.Effects do
  @moduledoc """
  Effect parameter functions for patterns.

  All parameter names use superdough canonical names internally for direct
  compatibility with browser audio playback. DSL functions provide aliases
  matching Strudel/TidalCycles conventions.

  ## Categories

  - **Filters**: `lpf/2`, `hpf/2`, `bpf/2` and resonance controls
  - **Envelope**: `attack/2`, `decay/2`, `sustain/2`, `release/2`
  - **Effects**: `room/2`, `delay/2`, `distort/2`, `crush/2`
  - **Modulation**: `vib/2`, `tremolo/2`, `detune/2`
  - **Sample**: `begin/2`, `end/2`, `loop/2`, `clip/2`
  - **Basic**: `gain/2`, `pan/2`, `speed/2`, `cut/2`

  ## Signal Modulation

  Effect functions accept either static values or signal patterns:

      # Static filter cutoff
      s("bd sd") |> lpf(800)

      # Modulated cutoff (sampled at each event's onset)
      s("bd sd") |> lpf(sine() |> range(200, 2000))

  ## Canonical Names

  DSL functions store values using superdough's canonical parameter names:

  | DSL Function | Stored As    |
  |--------------|--------------|
  | `lpf`        | `:cutoff`    |
  | `lpq`        | `:resonance` |
  | `hpf`        | `:hcutoff`   |
  | `bpf`        | `:bandf`     |
  """

  alias UzuPattern.Hap
  alias UzuPattern.Pattern
  alias UzuPattern.Time

  # ===========================================================================
  # Core: set_param
  # ===========================================================================

  @doc """
  Set a parameter on all events in the pattern.

  Value can be:
  - A static number - applied to all events
  - A Pattern - sampled at each event's onset time
  - A string - parsed as mini-notation, then sampled at onset

  ## Examples

      # Static value
      s("bd sd") |> set_param(:cutoff, 800)

      # Signal pattern - sampled at each event onset
      s("bd sd") |> set_param(:cutoff, sine() |> range(200, 2000))

      # Mini-notation string - parsed and sampled
      s("bd sd") |> set_param(:cutoff, "<200 400 800 1600>")
  """
  def set_param(%Pattern{} = pattern, key, %Pattern{} = value_pattern) do
    # Value is a pattern - sample at each hap's onset time
    Pattern.from_cycles(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.map(fn hap ->
        # Sample the value pattern at this hap's absolute time
        onset = Hap.onset(hap) || hap.part.begin
        absolute_time = Time.add(cycle, onset)
        {value, locations} = sample_pattern_at(value_pattern, absolute_time)

        # Merge value and locations from the sampled pattern
        updated_value = Map.put(hap.value, key, value)
        updated_context = merge_locations(hap.context, locations)

        %{hap | value: updated_value, context: updated_context}
      end)
    end)
  end

  def set_param(%Pattern{} = pattern, key, mini_notation) when is_binary(mini_notation) do
    set_param(pattern, key, mini_notation, [])
  end

  def set_param(%Pattern{} = pattern, key, value) do
    # Value is static - apply to all haps
    Pattern.from_cycles(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.map(fn hap ->
        %{hap | value: Map.put(hap.value, key, value)}
      end)
    end)
  end

  def set_param(%Pattern{} = pattern, key, mini_notation, opts)
      when is_binary(mini_notation) and is_list(opts) do
    # Parse string as mini-notation pattern, extract numeric values, then treat as signal
    source_offset = Keyword.get(opts, :source_offset, 0)

    parsed_pattern =
      mini_notation
      |> UzuParser.Grammar.parse()
      |> UzuPattern.Interpreter.interpret()
      |> Pattern.fmap(fn value ->
        # Interpreter produces %{s: "500"} - extract and convert to number
        case Map.get(value, :s) do
          nil -> value
          str_val -> maybe_convert_to_number(str_val)
        end
      end)
      # Apply source offset so locations are global document positions
      |> Pattern.with_offset(source_offset)

    set_param(pattern, key, parsed_pattern)
  end

  # Sample a pattern at a specific time, returning {value, locations}
  # Handles both continuous signals and discrete event patterns
  defp sample_pattern_at(%Pattern{metadata: %{time_fn: time_fn}}, time) do
    # Continuous signal (sine, saw, etc.) - no source locations
    {time_fn.(Time.to_float(time)), []}
  end

  defp sample_pattern_at(%Pattern{} = pattern, time) do
    # Discrete event pattern - query at the cycle and extract value + locations
    cycle = Time.to_float(time) |> trunc()

    pattern
    |> Pattern.query(cycle)
    |> List.first()
    |> case do
      nil ->
        {0.0, []}

      %Hap{value: %{value: v}, context: ctx} when not is_nil(v) ->
        {v, Map.get(ctx, :locations, [])}

      %Hap{value: v, context: ctx} when is_number(v) ->
        {v, Map.get(ctx, :locations, [])}

      %Hap{value: v, context: ctx} when is_map(v) ->
        {Map.get(v, :value, 0.0), Map.get(ctx, :locations, [])}

      _ ->
        {0.0, []}
    end
  end

  # Merge locations from a sampled hap into existing context
  defp merge_locations(context, new_locations) when is_list(new_locations) do
    existing = Map.get(context, :locations, [])
    Map.put(context, :locations, existing ++ new_locations)
  end

  defp merge_locations(context, _), do: context

  # Convert string to number if possible, otherwise return as-is
  defp maybe_convert_to_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} ->
        int

      _ ->
        case Float.parse(value) do
          {float, ""} -> float
          _ -> value
        end
    end
  end

  defp maybe_convert_to_number(value), do: value

  # ===========================================================================
  # Basic Audio Parameters
  # ===========================================================================

  @doc "Set gain/volume (0.0 to 1.0+). Accepts static value or signal pattern."
  def gain(pattern, value), do: set_param(pattern, :gain, value)
  def gain(pattern, value, opts) when is_list(opts), do: set_param(pattern, :gain, value, opts)

  @doc "Set stereo pan (-1.0 left, 0.0 center, 1.0 right). Accepts static or signal."
  def pan(pattern, value), do: set_param(pattern, :pan, value)
  def pan(pattern, value, opts) when is_list(opts), do: set_param(pattern, :pan, value, opts)

  @doc "Set playback speed (1.0 = normal, 2.0 = double/octave up, -1 = reverse)."
  def speed(pattern, value), do: set_param(pattern, :speed, value)
  def speed(pattern, value, opts) when is_list(opts), do: set_param(pattern, :speed, value, opts)

  @doc "Set cut group - new events cut off previous ones in the same group."
  def cut(pattern, group), do: set_param(pattern, :cut, group)

  # ===========================================================================
  # Lowpass Filter
  # Canonical: :cutoff, :resonance
  # ===========================================================================

  @doc """
  Set lowpass filter cutoff frequency (Hz).

  Aliases: `lpf`, `lp`, `cutoff`
  Stores as: `:cutoff`
  """
  def lpf(pattern, freq), do: set_param(pattern, :cutoff, freq)
  def lpf(pattern, freq, opts) when is_list(opts), do: set_param(pattern, :cutoff, freq, opts)
  def lp(pattern, freq), do: set_param(pattern, :cutoff, freq)
  def lp(pattern, freq, opts) when is_list(opts), do: set_param(pattern, :cutoff, freq, opts)
  def cutoff(pattern, freq), do: set_param(pattern, :cutoff, freq)
  def cutoff(pattern, freq, opts) when is_list(opts), do: set_param(pattern, :cutoff, freq, opts)

  @doc """
  Set lowpass filter resonance/Q (0 to ~50).

  Aliases: `lpq`, `resonance`
  Stores as: `:resonance`
  """
  def lpq(pattern, q), do: set_param(pattern, :resonance, q)
  def lpq(pattern, q, opts) when is_list(opts), do: set_param(pattern, :resonance, q, opts)
  def resonance(pattern, q), do: set_param(pattern, :resonance, q)
  def resonance(pattern, q, opts) when is_list(opts), do: set_param(pattern, :resonance, q, opts)

  # ===========================================================================
  # Highpass Filter
  # Canonical: :hcutoff, :hresonance
  # ===========================================================================

  @doc """
  Set highpass filter cutoff frequency (Hz).

  Aliases: `hpf`, `hp`, `hcutoff`
  Stores as: `:hcutoff`
  """
  def hpf(pattern, freq), do: set_param(pattern, :hcutoff, freq)
  def hpf(pattern, freq, opts) when is_list(opts), do: set_param(pattern, :hcutoff, freq, opts)
  def hp(pattern, freq), do: set_param(pattern, :hcutoff, freq)
  def hp(pattern, freq, opts) when is_list(opts), do: set_param(pattern, :hcutoff, freq, opts)
  def hcutoff(pattern, freq), do: set_param(pattern, :hcutoff, freq)
  def hcutoff(pattern, freq, opts) when is_list(opts), do: set_param(pattern, :hcutoff, freq, opts)

  @doc """
  Set highpass filter resonance/Q (0 to ~50).

  Aliases: `hpq`, `hresonance`
  Stores as: `:hresonance`
  """
  def hpq(pattern, q), do: set_param(pattern, :hresonance, q)
  def hpq(pattern, q, opts) when is_list(opts), do: set_param(pattern, :hresonance, q, opts)
  def hresonance(pattern, q), do: set_param(pattern, :hresonance, q)
  def hresonance(pattern, q, opts) when is_list(opts), do: set_param(pattern, :hresonance, q, opts)

  # ===========================================================================
  # Bandpass Filter
  # Canonical: :bandf, :bandq
  # ===========================================================================

  @doc """
  Set bandpass filter center frequency (Hz).

  Aliases: `bpf`, `bp`, `bandf`
  Stores as: `:bandf`
  """
  def bpf(pattern, freq), do: set_param(pattern, :bandf, freq)
  def bpf(pattern, freq, opts) when is_list(opts), do: set_param(pattern, :bandf, freq, opts)
  def bp(pattern, freq), do: set_param(pattern, :bandf, freq)
  def bp(pattern, freq, opts) when is_list(opts), do: set_param(pattern, :bandf, freq, opts)
  def bandf(pattern, freq), do: set_param(pattern, :bandf, freq)
  def bandf(pattern, freq, opts) when is_list(opts), do: set_param(pattern, :bandf, freq, opts)

  @doc """
  Set bandpass filter Q/resonance (0 to ~50).

  Aliases: `bpq`, `bandq`
  Stores as: `:bandq`
  """
  def bpq(pattern, q), do: set_param(pattern, :bandq, q)
  def bpq(pattern, q, opts) when is_list(opts), do: set_param(pattern, :bandq, q, opts)
  def bandq(pattern, q), do: set_param(pattern, :bandq, q)
  def bandq(pattern, q, opts) when is_list(opts), do: set_param(pattern, :bandq, q, opts)

  # ===========================================================================
  # Amplitude Envelope (ADSR)
  # Canonical: :attack, :decay, :sustain, :release
  # ===========================================================================

  @doc "Set envelope attack time in seconds. Aliases: `attack`, `att`"
  def attack(pattern, time), do: set_param(pattern, :attack, time)
  def attack(pattern, time, opts) when is_list(opts), do: set_param(pattern, :attack, time, opts)
  def att(pattern, time), do: set_param(pattern, :attack, time)
  def att(pattern, time, opts) when is_list(opts), do: set_param(pattern, :attack, time, opts)

  @doc "Set envelope decay time in seconds. Aliases: `decay`, `dec`"
  def decay(pattern, time), do: set_param(pattern, :decay, time)
  def decay(pattern, time, opts) when is_list(opts), do: set_param(pattern, :decay, time, opts)
  def dec(pattern, time), do: set_param(pattern, :decay, time)
  def dec(pattern, time, opts) when is_list(opts), do: set_param(pattern, :decay, time, opts)

  @doc "Set envelope sustain level (0.0 to 1.0). Aliases: `sustain`, `sus`"
  def sustain(pattern, level), do: set_param(pattern, :sustain, level)
  def sustain(pattern, level, opts) when is_list(opts), do: set_param(pattern, :sustain, level, opts)
  def sus(pattern, level), do: set_param(pattern, :sustain, level)
  def sus(pattern, level, opts) when is_list(opts), do: set_param(pattern, :sustain, level, opts)

  @doc "Set envelope release time in seconds. Aliases: `release`, `rel`"
  def release(pattern, time), do: set_param(pattern, :release, time)
  def release(pattern, time, opts) when is_list(opts), do: set_param(pattern, :release, time, opts)
  def rel(pattern, time), do: set_param(pattern, :release, time)
  def rel(pattern, time, opts) when is_list(opts), do: set_param(pattern, :release, time, opts)

  # ===========================================================================
  # Delay Effect
  # Canonical: :delay, :delaytime, :delayfeedback
  # ===========================================================================

  @doc "Set delay send amount (0.0 dry to 1.0 wet)."
  def delay(pattern, amount), do: set_param(pattern, :delay, amount)
  def delay(pattern, amount, opts) when is_list(opts), do: set_param(pattern, :delay, amount, opts)

  @doc "Set delay time in seconds. Aliases: `delaytime`, `delayt`, `dt`"
  def delaytime(pattern, time), do: set_param(pattern, :delaytime, time)
  def delaytime(pattern, time, opts) when is_list(opts), do: set_param(pattern, :delaytime, time, opts)
  def delayt(pattern, time), do: set_param(pattern, :delaytime, time)
  def delayt(pattern, time, opts) when is_list(opts), do: set_param(pattern, :delaytime, time, opts)
  def dt(pattern, time), do: set_param(pattern, :delaytime, time)
  def dt(pattern, time, opts) when is_list(opts), do: set_param(pattern, :delaytime, time, opts)

  @doc "Set delay feedback (0.0 to <1.0). Aliases: `delayfeedback`, `delayfb`, `dfb`"
  def delayfeedback(pattern, fb), do: set_param(pattern, :delayfeedback, fb)
  def delayfeedback(pattern, fb, opts) when is_list(opts), do: set_param(pattern, :delayfeedback, fb, opts)
  def delayfb(pattern, fb), do: set_param(pattern, :delayfeedback, fb)
  def delayfb(pattern, fb, opts) when is_list(opts), do: set_param(pattern, :delayfeedback, fb, opts)
  def dfb(pattern, fb), do: set_param(pattern, :delayfeedback, fb)
  def dfb(pattern, fb, opts) when is_list(opts), do: set_param(pattern, :delayfeedback, fb, opts)

  # ===========================================================================
  # Reverb Effect
  # Canonical: :room, :roomsize
  # ===========================================================================

  @doc "Set reverb send amount (0.0 dry to 1.0 wet)."
  def room(pattern, amount), do: set_param(pattern, :room, amount)
  def room(pattern, amount, opts) when is_list(opts), do: set_param(pattern, :room, amount, opts)

  @doc "Set reverb room size. Aliases: `roomsize`, `size`, `sz`, `rsize`"
  def roomsize(pattern, size), do: set_param(pattern, :roomsize, size)
  def roomsize(pattern, size, opts) when is_list(opts), do: set_param(pattern, :roomsize, size, opts)
  def size(pattern, sz), do: set_param(pattern, :roomsize, sz)
  def size(pattern, sz, opts) when is_list(opts), do: set_param(pattern, :roomsize, sz, opts)
  def sz(pattern, sz), do: set_param(pattern, :roomsize, sz)
  def sz(pattern, sz, opts) when is_list(opts), do: set_param(pattern, :roomsize, sz, opts)
  def rsize(pattern, sz), do: set_param(pattern, :roomsize, sz)
  def rsize(pattern, sz, opts) when is_list(opts), do: set_param(pattern, :roomsize, sz, opts)

  # ===========================================================================
  # Distortion Effects
  # Canonical: :distort, :crush, :coarse
  # ===========================================================================

  @doc "Set distortion amount. Aliases: `distort`, `dist`"
  def distort(pattern, amount), do: set_param(pattern, :distort, amount)
  def distort(pattern, amount, opts) when is_list(opts), do: set_param(pattern, :distort, amount, opts)
  def dist(pattern, amount), do: set_param(pattern, :distort, amount)
  def dist(pattern, amount, opts) when is_list(opts), do: set_param(pattern, :distort, amount, opts)

  @doc "Set bit crusher depth (1 = heavy, 16 = subtle)."
  def crush(pattern, bits), do: set_param(pattern, :crush, bits)
  def crush(pattern, bits, opts) when is_list(opts), do: set_param(pattern, :crush, bits, opts)

  @doc "Set sample rate reduction (1 = original, 2 = half, etc)."
  def coarse(pattern, factor), do: set_param(pattern, :coarse, factor)
  def coarse(pattern, factor, opts) when is_list(opts), do: set_param(pattern, :coarse, factor, opts)

  # ===========================================================================
  # Modulation Effects
  # Canonical: :vib, :vibmod, :tremolo, :detune
  # ===========================================================================

  @doc "Set vibrato rate in Hz. Aliases: `vib`, `vibrato`, `v`"
  def vib(pattern, rate), do: set_param(pattern, :vib, rate)
  def vib(pattern, rate, opts) when is_list(opts), do: set_param(pattern, :vib, rate, opts)
  def vibrato(pattern, rate), do: set_param(pattern, :vib, rate)
  def vibrato(pattern, rate, opts) when is_list(opts), do: set_param(pattern, :vib, rate, opts)
  def v(pattern, rate), do: set_param(pattern, :vib, rate)
  def v(pattern, rate, opts) when is_list(opts), do: set_param(pattern, :vib, rate, opts)

  @doc "Set vibrato depth in semitones. Aliases: `vibmod`, `vmod`"
  def vibmod(pattern, depth), do: set_param(pattern, :vibmod, depth)
  def vibmod(pattern, depth, opts) when is_list(opts), do: set_param(pattern, :vibmod, depth, opts)
  def vmod(pattern, depth), do: set_param(pattern, :vibmod, depth)
  def vmod(pattern, depth, opts) when is_list(opts), do: set_param(pattern, :vibmod, depth, opts)

  @doc "Set tremolo rate in Hz. Aliases: `tremolo`, `trem`"
  def tremolo(pattern, rate), do: set_param(pattern, :tremolo, rate)
  def tremolo(pattern, rate, opts) when is_list(opts), do: set_param(pattern, :tremolo, rate, opts)
  def trem(pattern, rate), do: set_param(pattern, :tremolo, rate)
  def trem(pattern, rate, opts) when is_list(opts), do: set_param(pattern, :tremolo, rate, opts)

  @doc "Set detune for stacked voices. Aliases: `detune`, `det`"
  def detune(pattern, amount), do: set_param(pattern, :detune, amount)
  def detune(pattern, amount, opts) when is_list(opts), do: set_param(pattern, :detune, amount, opts)
  def det(pattern, amount), do: set_param(pattern, :detune, amount)
  def det(pattern, amount, opts) when is_list(opts), do: set_param(pattern, :detune, amount, opts)

  # ===========================================================================
  # Sample Control
  # Canonical: :begin, :end, :loop, :clip, :unit
  # ===========================================================================

  @doc "Set sample start point (0.0 to 1.0)."
  def begin_at(pattern, pos), do: set_param(pattern, :begin, pos)

  @doc "Set sample end point (0.0 to 1.0)."
  def end_at(pattern, pos), do: set_param(pattern, :end, pos)

  @doc "Enable sample looping (1 = on)."
  def loop(pattern, on), do: set_param(pattern, :loop, on)

  @doc "Set duration multiplier. Aliases: `clip`, `legato`"
  def clip(pattern, mult), do: set_param(pattern, :clip, mult)
  def legato(pattern, mult), do: set_param(pattern, :clip, mult)

  @doc ~s[Set speed unit: "r" (rate), "c" (cycles), "s" (seconds).]
  def unit(pattern, u), do: set_param(pattern, :unit, u)

  # ===========================================================================
  # Orbit (Global Effect Bus)
  # ===========================================================================

  @doc "Set effect orbit/bus number. Aliases: `orbit`, `o`"
  def orbit(pattern, num), do: set_param(pattern, :orbit, num)
  def o(pattern, num), do: set_param(pattern, :orbit, num)
end
