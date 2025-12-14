defmodule UzuPattern.Pattern.Harmony do
  @moduledoc """
  Harmonic pattern transformations.

  This module provides functions for working with musical harmony in patterns:

  - `form/1` - Load a chord progression from RealBook as a pattern
  - `scale/1` - Map numbers to scale degrees (static scale)
  - `scale/0` - Map numbers using scale inferred from chord context

  ## Melody over changes

      # Numbers become scale degrees, scale follows the chord progression
      n("0 2 4 5 3 1") |> form("Autumn Leaves") |> scale()

  ## Static scale

      # Simple case - fixed scale
      n("0 2 4") |> scale("C:minor")

  All music theory computations (scale degrees → MIDI, chord → scale inference)
  are delegated to the Harmony library.
  """

  alias UzuPattern.Pattern
  alias UzuPattern.Hap
  alias UzuPattern.TimeSpan

  # ============================================================
  # form/1 - Load chord progression as a pattern
  # ============================================================

  @doc """
  Load a chord progression from RealBook as a pattern.

  Returns a pattern that yields the current chord symbol at any point in time.
  The pattern loops through the form structure (e.g., "A,A,B,A").

  The pattern also stores form metadata so `scale/0` can infer the appropriate
  scale at each point in time.

  ## Example

      form("Autumn Leaves")
      # At cycle 0: returns "Cm7"
      # At cycle 1: returns "F7"
      # etc.
  """
  def form(song_name) when is_binary(song_name) do
    case load_form_data(song_name) do
      {:ok, form_data} ->
        build_form_pattern(form_data)

      :error ->
        Pattern.silence()
    end
  end

  # Load and flatten form data from RealBook
  defp load_form_data(song_name) do
    case RealBook.get(song_name) do
      %RealBook.Song{title: ""} ->
        :error

      %RealBook.Song{} = song ->
        section_order = parse_form_string(song.form)
        {changes, length} = build_changes(song.sections, section_order)

        {:ok,
         %{
           song: song_name,
           key: get_primary_key(song.sections, section_order),
           changes: changes,
           length: length,
           beats_per_cycle: 4
         }}
    end
  end

  defp parse_form_string(form_string) when is_binary(form_string) do
    form_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp get_primary_key(sections, [first_section | _]) do
    case Map.get(sections, first_section) do
      %{key: key} when is_binary(key) and key != "" -> key
      _ -> "C"
    end
  end

  defp get_primary_key(_, _), do: "C"

  defp build_changes(sections, section_order) do
    {changes, final_beat} =
      Enum.reduce(section_order, {[], 0.0}, fn section_name, {acc, beat} ->
        case Map.get(sections, section_name) do
          nil ->
            {acc, beat}

          section ->
            {section_changes, new_beat} = process_section(section, beat)
            {acc ++ section_changes, new_beat}
        end
      end)

    {changes, trunc(final_beat)}
  end

  defp process_section(section, start_beat) do
    Enum.reduce(section.measures, {[], start_beat}, fn measure, {acc, beat} ->
      {measure_changes, new_beat} = process_measure(measure, beat)
      {acc ++ measure_changes, new_beat}
    end)
  end

  defp process_measure(measure, start_beat) do
    Enum.reduce(measure.chords, {[], start_beat}, fn chord_beat, {acc, beat} ->
      symbol = chord_beat.symbol || ""
      beats = chord_beat.beats || 4.0
      change = {trunc(beat), symbol}
      {acc ++ [change], beat + beats}
    end)
  end

  defp build_form_pattern(form_data) do
    %{changes: changes, length: length, beats_per_cycle: bpc} = form_data

    query_fn = fn cycle ->
      beat = rem(cycle * bpc, length)
      chord = find_chord_at_beat(changes, beat)

      [
        %Hap{
          whole: TimeSpan.new(cycle, cycle + 1),
          part: TimeSpan.new(cycle, cycle + 1),
          value: %{s: chord},
          context: %{locations: [], tags: []}
        }
      ]
    end

    pattern = Pattern.new(query_fn)
    %{pattern | metadata: Map.put(pattern.metadata, :form_data, form_data)}
  end

  defp find_chord_at_beat(changes, beat) do
    changes
    |> Enum.filter(fn {change_beat, _chord} -> change_beat <= beat end)
    |> Enum.max_by(fn {change_beat, _chord} -> change_beat end, fn -> {0, "C"} end)
    |> elem(1)
  end

  # ============================================================
  # scale/1 - Static scale mapping
  # ============================================================

  @doc """
  Map numeric values to scale degrees using a fixed scale.

  Takes a pattern with numeric values and converts them to MIDI note numbers.
  Uses `Harmony.Scale.degree_to_midi/3` for the conversion.

  ## Scale format

  Use "RootOctave:type" format (colon separator). Octave defaults to 3 if not specified:
  - "C:major" - C3 major (default octave 3)
  - "C4:major" - C4 major
  - "A3:minor" - A3 minor
  - "Bb4:dorian" - Bb4 dorian
  - "F#5:minor" - F#5 minor

  ## Examples

      n("0 2 4") |> scale("C:major")
      # 0 → 48 (C3), 2 → 52 (E3), 4 → 55 (G3)

      n("0 2 4") |> scale("C4:major")
      # 0 → 60 (C4), 2 → 64 (E4), 4 → 67 (G4)

      n("0 2 4") |> scale("C5:major")
      # 0 → 72 (C5), 2 → 76 (E5), 4 → 79 (G5)
  """
  def scale(pattern, scale_name) when is_binary(scale_name) do
    {harmony_scale_name, octave} = parse_scale_name(scale_name)

    Pattern.new(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.map(&apply_scale_to_hap(&1, harmony_scale_name, octave))
    end)
  end

  # Parse scale name like "C4:major" into {"C major", 4}
  # Supports: "C:major" (octave 3), "C4:major", "Bb3:dorian", "F#5:minor"
  defp parse_scale_name(scale_name) do
    # Split on colon to separate root from scale type
    case String.split(scale_name, ":", parts: 2) do
      [root_with_octave, scale_type] ->
        {root, octave} = parse_root_and_octave(root_with_octave)
        {"#{root} #{scale_type}", octave}

      [scale_name_no_colon] ->
        # No colon - might be "C major" format already
        {scale_name_no_colon, 3}
    end
  end

  # Parse root note with optional octave: "C" -> {"C", 3}, "C4" -> {"C", 4}, "Bb3" -> {"Bb", 3}
  defp parse_root_and_octave(root_str) do
    # Match: letter, optional accidental (b or #), optional octave number
    case Regex.run(~r/^([A-Ga-g][b#]?)(\d)?$/, root_str) do
      [_, root, octave_str] -> {root, String.to_integer(octave_str)}
      [_, root] -> {root, 3}
      nil -> {root_str, 3}
    end
  end

  @doc """
  Map numeric values using scale inferred from chord context.

  Uses the chord progression set by `form/1` to determine the scale at each
  point in time. Scale inference uses `Harmony.Chord.primary_scale/1`.

  ## Example

      n("0 2 4") |> form("Autumn Leaves") |> scale()
      # Cycle 0 (Cm7): C dorian scale
      # Cycle 1 (F7): F mixolydian scale
  """
  def scale(%Pattern{metadata: %{form_data: form_data}} = pattern) do
    Pattern.new(fn cycle ->
      # Get chord at this cycle
      beat = rem(cycle * form_data.beats_per_cycle, form_data.length)
      chord = find_chord_at_beat(form_data.changes, beat)

      # Infer scale from chord using Harmony
      scale_name =
        if chord != "" do
          Harmony.Chord.primary_scale(chord)
        else
          "#{form_data.key} major"
        end

      pattern
      |> Pattern.query(cycle)
      |> Enum.map(&apply_scale_to_hap(&1, scale_name))
    end)
  end

  # Fallback - no form context, pass through unchanged
  def scale(%Pattern{} = pattern), do: pattern

  # ============================================================
  # octave/2 - Octave shifting
  # ============================================================

  @doc """
  Shift notes by octaves.

  The octave parameter sets the target octave. Since scale() defaults to octave 3,
  this shifts notes by `(target_octave - 3) * 12` semitones.

  Can accept a single number or a pattern of octaves for patterned shifting.

  ## Examples

      # Play in octave 4 (one octave up from default)
      n("0 2 4") |> scale("C:major") |> octave(4)
      # Notes shift from C3,E3,G3 (48,52,55) to C4,E4,G4 (60,64,67)

      # Pattern the octave
      n("0 2 4") |> scale("C:major") |> octave("3 4 5")
      # Each note plays in a different octave

      # Octave pattern cycles
      n("0") |> scale("C:major") |> octave("<3 4 5>")
      # Cycles through octaves
  """
  def octave(pattern, octave_value) when is_number(octave_value) do
    shift = (octave_value - 3) * 12

    Pattern.new(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.map(&shift_note_octave(&1, shift))
    end)
  end

  def octave(pattern, octave_pattern) when is_binary(octave_pattern) do
    # Parse octave pattern as mini-notation
    octave_pat = UzuParser.Grammar.parse(octave_pattern) |> UzuPattern.Interpreter.interpret()

    Pattern.new(fn cycle ->
      pattern_haps = Pattern.query(pattern, cycle)
      octave_haps = Pattern.query(octave_pat, cycle)

      # For each pattern hap, find overlapping octave hap and apply shift
      Enum.map(pattern_haps, fn hap ->
        # Find octave value at the hap's time
        octave_val =
          Enum.find_value(octave_haps, 3, fn oct_hap ->
            if TimeSpan.intersection(hap.part, oct_hap.part) do
              parse_octave_value(oct_hap.value)
            end
          end)

        shift = (octave_val - 3) * 12
        shift_note_octave(hap, shift)
      end)
    end)
  end

  defp parse_octave_value(%{s: s}) when is_binary(s), do: parse_number(s) || 3
  defp parse_octave_value(%{value: v}) when is_number(v), do: v
  defp parse_octave_value(v) when is_number(v), do: v
  defp parse_octave_value(_), do: 3

  defp shift_note_octave(hap, shift) do
    case Map.get(hap.value, :note) do
      nil -> hap
      note when is_number(note) -> %{hap | value: Map.put(hap.value, :note, note + shift)}
      _ -> hap
    end
  end

  # ============================================================
  # Private helpers
  # ============================================================

  defp apply_scale_to_hap(hap, scale_name, octave \\ 3) do
    # For Haps, numeric value (degree) could be in:
    # - hap.value.n (from n() function)
    # - hap.value.value (signal patterns)
    # - hap.value.s parsed as number (explicit degree notation)
    n_val = Map.get(hap.value, :n)
    sound = Map.get(hap.value, :s, "")
    value = Map.get(hap.value, :value)

    degree =
      cond do
        is_number(n_val) -> n_val
        is_number(value) -> value
        is_binary(sound) -> parse_number(sound)
        is_number(sound) -> sound
        true -> nil
      end

    if degree do
      midi = Harmony.Scale.degree_to_midi(scale_name, degree, octave)
      %{hap | value: Map.put(hap.value, :note, midi)}
    else
      hap
    end
  end

  defp parse_number(str) do
    case Integer.parse(str) do
      {n, ""} -> n
      _ -> nil
    end
  end
end
