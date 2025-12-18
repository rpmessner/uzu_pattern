defmodule UzuPattern.Pattern.Harmony do
  @moduledoc """
  Harmonic pattern transformations.

  This module provides functions for working with musical harmony in patterns:

  - `form/1` - Load a chord progression from RealBook as a pattern
  - `scale/1` - Map numbers to scale degrees (static scale)
  - `scale/0` - Map numbers using scale inferred from chord context
  - `transpose/2` - Transpose notes by semitones or interval
  - `scale_transpose/3` - Transpose notes by scale steps
  - `octave/2` - Shift notes by octaves
  - `voicing/1,2` - Apply chord voicings to chord patterns
  - `root_notes/2` - Extract root notes from chord patterns
  - `chord/2` - Set chord context on pattern haps

  ## Melody over changes

      # Numbers become scale degrees, scale follows the chord progression
      n("0 2 4 5 3 1") |> form("Autumn Leaves") |> scale()

  ## Static scale

      # Simple case - fixed scale
      n("0 2 4") |> scale("C:minor")

  ## Chord voicings

      # Voice chords with jazz left-hand voicings
      form("Autumn Leaves") |> voicing()

      # Extract bass line from chord progression
      form("Autumn Leaves") |> root_notes(2)

  All music theory computations (scale degrees → MIDI, chord → scale inference,
  voicing dictionaries) are delegated to the Harmony library.
  """

  alias UzuPattern.Pattern
  alias UzuPattern.Hap
  alias UzuPattern.TimeSpan

  # ============================================================
  # transpose/2 - Transpose notes by interval or semitones
  # ============================================================

  @doc """
  Transpose notes by an interval or number of semitones.

  The amount can be given as:
  - A number of semitones (e.g., 7 for perfect fifth)
  - An interval string using standard notation (e.g., "5P" for perfect fifth)

  Interval notation: `<number><quality>` where quality is:
  - P = perfect (for 1, 4, 5, 8)
  - M = major (for 2, 3, 6, 7)
  - m = minor
  - A = augmented
  - d = diminished

  Common intervals:
  - 1P = unison (0 semitones)
  - 2M = major second (2)
  - 3m = minor third (3)
  - 3M = major third (4)
  - 4P = perfect fourth (5)
  - 5P = perfect fifth (7)
  - 8P = octave (12)

  ## Examples

      # Transpose by semitones
      note("c4 e4 g4") |> transpose(7)
      # C4 → G4, E4 → B4, G4 → D5

      # Transpose by interval string
      note("c4 e4 g4") |> transpose("5P")
      # Same result with proper enharmonic spelling

      # Pattern the transposition
      note("c4") |> transpose("<0 7 12>")
      # Cycles through unison, fifth, octave

      # Works with MIDI note numbers
      n("0 4 7") |> scale("C:major") |> transpose(5)
  """
  def transpose(pattern, amount) when is_number(amount) do
    Pattern.from_cycles(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.map(&transpose_hap(&1, amount))
    end)
  end

  def transpose(pattern, amount) when is_binary(amount) do
    # Check if it's a pattern string or an interval
    if pattern_string?(amount) do
      # It's a pattern - parse and apply per-event
      amount_pattern = UzuParser.Grammar.parse(amount) |> UzuPattern.Interpreter.interpret()

      Pattern.from_cycles(fn cycle ->
        pattern_haps = Pattern.query(pattern, cycle)
        amount_haps = Pattern.query(amount_pattern, cycle)

        Enum.map(pattern_haps, fn hap ->
          # Find the amount value at this hap's time
          semitones =
            Enum.find_value(amount_haps, 0, fn amt_hap ->
              if TimeSpan.intersection(hap.part, amt_hap.part) do
                parse_transpose_amount(amt_hap.value)
              end
            end)

          transpose_hap(hap, semitones)
        end)
      end)
    else
      # It's an interval string like "5P" or "3M"
      semitones = Harmony.Interval.semitones(amount) || 0
      transpose(pattern, semitones)
    end
  end

  defp pattern_string?(str) do
    # Check if string looks like a pattern (has spaces, <>, etc.) vs interval
    String.contains?(str, [" ", "<", ">", "[", "]", "{", "}"]) or
      Regex.match?(~r/^\d+$/, str)
  end

  defp parse_transpose_amount(%{s: s}) when is_binary(s), do: parse_transpose_value(s)
  defp parse_transpose_amount(%{value: v}) when is_number(v), do: v
  defp parse_transpose_amount(v) when is_number(v), do: v
  defp parse_transpose_amount(_), do: 0

  defp parse_transpose_value(str) do
    case Integer.parse(str) do
      {n, ""} -> n
      _ -> Harmony.Interval.semitones(str) || 0
    end
  end

  defp transpose_hap(hap, semitones) when is_number(semitones) do
    note = Map.get(hap.value, :note)

    cond do
      is_number(note) ->
        # MIDI note number - just add semitones
        %{hap | value: Map.put(hap.value, :note, note + semitones)}

      is_binary(note) and note != "" ->
        # Note string - use Harmony.Transpose for proper enharmonics
        transposed = Harmony.Transpose.transpose(note, Harmony.Interval.from_semitones(semitones))
        %{hap | value: Map.put(hap.value, :note, transposed)}

      true ->
        hap
    end
  end

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

    Pattern.from_cycles(fn cycle ->
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
    Pattern.from_cycles(fn cycle ->
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

    Pattern.from_cycles(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.map(&shift_note_octave(&1, shift))
    end)
  end

  def octave(pattern, octave_pattern) when is_binary(octave_pattern) do
    # Parse octave pattern as mini-notation
    octave_pat = UzuParser.Grammar.parse(octave_pattern) |> UzuPattern.Interpreter.interpret()

    Pattern.from_cycles(fn cycle ->
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
    # For Haps, numeric value (degree) could be in (Strudel-compatible order):
    # - hap.value.note (from note() function - checked first like Strudel)
    # - hap.value.n (from n() function)
    # - hap.value.value (signal patterns)
    # - hap.value.s parsed as number (explicit degree notation)
    note_val = Map.get(hap.value, :note)
    n_val = Map.get(hap.value, :n)
    sound = Map.get(hap.value, :s, "")
    value = Map.get(hap.value, :value)

    degree =
      cond do
        is_binary(note_val) -> parse_number(note_val)
        is_number(note_val) -> note_val
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

  # ============================================================
  # scale_transpose/2 - Transpose notes by scale steps
  # ============================================================

  @doc """
  Transpose notes by scale steps rather than semitones.

  Unlike `transpose/2` which moves by chromatic steps, `scale_transpose/2` moves
  by diatonic scale degrees. The scale must be specified, and the note must be
  in that scale.

  ## Examples

      # Move up 2 scale steps in C major
      note("c4") |> scale_transpose("C:major", 2)
      # C4 → E4

      # Move down 1 scale step
      note("c4") |> scale_transpose("C:major", -1)
      # C4 → B3

      # Pattern the offset
      note("c4") |> scale_transpose("C:major", "<0 2 4>")
      # Cycles through C4, E4, G4

      # Works with form context
      n("0 2 4") |> form("Autumn Leaves") |> scale() |> scale_transpose(2)
  """
  def scale_transpose(pattern, scale_name, offset) when is_binary(scale_name) and is_number(offset) do
    {harmony_scale_name, _octave} = parse_scale_name(scale_name)

    Pattern.from_cycles(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.map(&scale_transpose_hap(&1, harmony_scale_name, offset))
    end)
  end

  def scale_transpose(pattern, scale_name, offset_pattern) when is_binary(scale_name) and is_binary(offset_pattern) do
    {harmony_scale_name, _octave} = parse_scale_name(scale_name)
    offset_pat = UzuParser.Grammar.parse(offset_pattern) |> UzuPattern.Interpreter.interpret()

    Pattern.from_cycles(fn cycle ->
      pattern_haps = Pattern.query(pattern, cycle)
      offset_haps = Pattern.query(offset_pat, cycle)

      Enum.map(pattern_haps, fn hap ->
        offset =
          Enum.find_value(offset_haps, 0, fn off_hap ->
            if TimeSpan.intersection(hap.part, off_hap.part) do
              parse_offset_value(off_hap.value)
            end
          end)

        scale_transpose_hap(hap, harmony_scale_name, offset)
      end)
    end)
  end

  defp parse_offset_value(%{s: s}) when is_binary(s), do: parse_number(s) || 0
  defp parse_offset_value(%{n: n}) when is_number(n), do: n
  defp parse_offset_value(%{value: v}) when is_number(v), do: v
  defp parse_offset_value(v) when is_number(v), do: v
  defp parse_offset_value(_), do: 0

  defp scale_transpose_hap(hap, scale_name, offset) do
    note = Map.get(hap.value, :note)

    cond do
      is_binary(note) and note != "" ->
        # Note string - use Harmony.Scale.scale_transpose
        case Harmony.Scale.scale_transpose(scale_name, offset, note) do
          nil -> hap
          transposed -> %{hap | value: Map.put(hap.value, :note, transposed)}
        end

      true ->
        # Can't scale transpose MIDI numbers without knowing what note they represent
        hap
    end
  end

  # ============================================================
  # root_notes/2 - Extract root notes from chord pattern
  # ============================================================

  @doc """
  Extract root notes from a chord pattern at a given octave.

  Takes a pattern that yields chord symbols and converts them to their root
  notes at the specified octave.

  ## Examples

      # Get roots of a chord progression
      form("Autumn Leaves") |> root_notes(3)
      # Cm7 → C3, F7 → F3, etc.

      # Use with a simple chord pattern
      s("Cm7 F7 Bbmaj7 Ebmaj7") |> root_notes(4)
      # Yields C4, F4, Bb4, Eb4
  """
  def root_notes(pattern, octave \\ 4) when is_number(octave) do
    Pattern.from_cycles(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.map(&extract_root_note_hap(&1, octave))
    end)
  end

  defp extract_root_note_hap(hap, octave) do
    chord_symbol = Map.get(hap.value, :s, "")

    case Harmony.Chord.root_note(chord_symbol) do
      nil ->
        hap

      root ->
        note_with_octave = "#{root}#{octave}"
        midi = Harmony.Note.midi(note_with_octave)
        %{hap | value: Map.put(hap.value, :note, midi)}
    end
  end

  # ============================================================
  # voicing/1, voicing/2 - Apply chord voicings
  # ============================================================

  @doc """
  Apply chord voicings to a pattern of chord symbols.

  Takes a pattern yielding chord symbols and expands each chord into its
  voiced notes using the specified voicing dictionary.

  ## Options

  - `:dictionary` - Which voicing dictionary to use (default: `:lefthand`)
  - `:inversion` - Which inversion to use, 0-indexed (default: 0)

  ## Examples

      # Voice a chord progression with lefthand voicings
      form("Autumn Leaves") |> voicing()

      # Use guidetone voicings (3rd and 7th only)
      form("Autumn Leaves") |> voicing(dictionary: :guidetones)

      # Use triad voicings
      s("C Am F G") |> voicing(dictionary: :triads)
  """
  def voicing(pattern, opts \\ []) do
    dictionary = Keyword.get(opts, :dictionary, :lefthand)
    inversion = Keyword.get(opts, :inversion, 0)
    base_octave = Keyword.get(opts, :octave, 4)

    Pattern.from_cycles(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.flat_map(&voice_chord_hap(&1, dictionary, inversion, base_octave))
    end)
  end

  defp voice_chord_hap(hap, dictionary, inversion, base_octave) do
    chord_symbol = Map.get(hap.value, :s, "")

    case Harmony.Voicing.voice(chord_symbol, dictionary: dictionary, inversion: inversion) do
      nil ->
        [hap]

      notes ->
        # Create a hap for each voiced note, stacking them
        notes
        |> Enum.map(fn note_pc ->
          # Add octave to the pitch class
          note_with_octave = "#{note_pc}#{base_octave}"
          midi = Harmony.Note.midi(note_with_octave)

          %{hap | value: Map.put(hap.value, :note, midi)}
        end)
    end
  end

  # ============================================================
  # chord/2 - Set chord context on pattern
  # ============================================================

  @doc """
  Set chord context on a pattern's haps.

  This stores the chord symbol in each hap's context, which can be used by
  other functions like `scale/0` to infer the appropriate scale.

  ## Examples

      # Set a static chord context
      n("0 2 4") |> chord("Cm7") |> scale()

      # Pattern the chord
      n("0 2 4") |> chord("<Cm7 F7 Bbmaj7>") |> scale()
  """
  def chord(pattern, chord_symbol) when is_binary(chord_symbol) do
    if pattern_string?(chord_symbol) do
      # It's a pattern - parse and apply per-event
      chord_pattern = UzuParser.Grammar.parse(chord_symbol) |> UzuPattern.Interpreter.interpret()

      Pattern.from_cycles(fn cycle ->
        pattern_haps = Pattern.query(pattern, cycle)
        chord_haps = Pattern.query(chord_pattern, cycle)

        Enum.map(pattern_haps, fn hap ->
          chord_sym =
            Enum.find_value(chord_haps, "", fn chord_hap ->
              if TimeSpan.intersection(hap.part, chord_hap.part) do
                extract_chord_symbol(chord_hap.value)
              end
            end)

          set_chord_context(hap, chord_sym)
        end)
      end)
    else
      # Static chord symbol
      Pattern.from_cycles(fn cycle ->
        pattern
        |> Pattern.query(cycle)
        |> Enum.map(&set_chord_context(&1, chord_symbol))
      end)
    end
  end

  defp extract_chord_symbol(%{s: s}) when is_binary(s), do: s
  defp extract_chord_symbol(_), do: ""

  defp set_chord_context(hap, chord_symbol) do
    context = Map.get(hap, :context, %{})
    new_context = Map.put(context, :chord, chord_symbol)
    %{hap | context: new_context}
  end
end
