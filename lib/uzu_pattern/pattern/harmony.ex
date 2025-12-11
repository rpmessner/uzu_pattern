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
  alias UzuPattern.Event

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
        %Event{
          time: 0.0,
          duration: 1.0,
          sound: chord,
          value: chord,
          params: %{}
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

  Use "Root:type" format (colon separator):
  - "C:major"
  - "A:minor"
  - "Bb:dorian"

  ## Example

      n("0 2 4") |> scale("C:major")
      # 0 → 60 (C4), 2 → 64 (E4), 4 → 67 (G4)
  """
  def scale(pattern, scale_name) when is_binary(scale_name) do
    # Convert "C:major" to "C major" for Harmony
    harmony_scale_name = String.replace(scale_name, ":", " ")

    Pattern.new(fn cycle ->
      pattern
      |> Pattern.query(cycle)
      |> Enum.map(&apply_scale_to_event(&1, harmony_scale_name))
    end)
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
      |> Enum.map(&apply_scale_to_event(&1, scale_name))
    end)
  end

  # Fallback - no form context, pass through unchanged
  def scale(%Pattern{} = pattern), do: pattern

  # ============================================================
  # Private helpers
  # ============================================================

  defp apply_scale_to_event(event, scale_name) do
    degree =
      cond do
        is_number(event.value) -> event.value
        is_number(event.sound) -> event.sound
        true -> nil
      end

    if degree do
      midi = Harmony.Scale.degree_to_midi(scale_name, degree)
      %{event | params: Map.put(event.params, :note, midi)}
    else
      event
    end
  end
end
