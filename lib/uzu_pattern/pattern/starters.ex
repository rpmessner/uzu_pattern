defmodule UzuPattern.Pattern.Starters do
  @moduledoc """
  Pattern starter functions for creating patterns from mini-notation.

  These are the entry points for creating patterns:
  - `s/1` - Sound/sample patterns
  - `n/1` - Sample index patterns
  - `note/1` - Note/pitch patterns

  ## Examples

      s("bd sd hh cp")
      n("0 1 2 3") |> s("bd")  # plays bd:0 bd:1 bd:2 bd:3
      note("c3 e3 g3")
  """

  alias UzuPattern.Interpreter
  alias UzuPattern.Pattern

  @doc """
  Create a sound pattern from mini-notation.

  ## Examples

      s("bd sd hh cp")
      s("bd:1 sd:2")
      s("<bd sd> hh")
  """
  def s(mini_notation) when is_binary(mini_notation) do
    parse_to_pattern(mini_notation)
  end

  @doc "Alias for s/1."
  def sound(mini_notation), do: s(mini_notation)

  @doc """
  Create a sample index pattern from mini-notation.

  Numbers become the `:n` parameter (sample index).
  Use with s/2 to select sample variants:

      n("0 1 2 3") |> s("bd")  # plays bd:0, bd:1, bd:2, bd:3

  ## Examples

      n("0 1 2 3")
      n("<0 1> 2 3")
  """
  def n(mini_notation) when is_binary(mini_notation) do
    # Parse mini-notation then convert numeric strings to sample indices
    # Numbers become :n (sample index), non-numbers stay as :s
    parse_to_pattern(mini_notation)
    |> Pattern.fmap(fn value ->
      case Map.pop(value, :s) do
        {nil, value} ->
          value

        {sound_val, rest} ->
          # Convert numeric strings to numbers for sample indices
          converted = maybe_convert_to_number(sound_val)

          if is_number(converted) do
            Map.put(rest, :n, converted)
          else
            Map.put(rest, :s, sound_val)
          end
      end
    end)
  end

  @doc """
  Create a note/pitch pattern from mini-notation.

  Maps parsed values to the `note` key for pitch/frequency handling.
  Numeric strings are converted to numbers (MIDI note numbers).

  ## Examples

      note("c3 e3 g3")
      note("60 64 67")  # MIDI notes
  """
  def note(mini_notation) when is_binary(mini_notation) do
    # Parse mini-notation (creates pattern with :s key)
    # Then map :s to :note for pitch patterns
    # Convert numeric strings to numbers for MIDI note handling
    parse_to_pattern(mini_notation)
    |> Pattern.fmap(fn value ->
      case Map.pop(value, :s) do
        {nil, value} ->
          value

        {note_val, rest} ->
          # Convert numeric strings to numbers for MIDI notes
          Map.put(rest, :note, maybe_convert_to_number(note_val))
      end
    end)
  end

  @doc """
  Set sound parameter on an existing pattern.

  Used to combine with n() for sample selection:

      n("0 1 2 3") |> s("bd")

  ## Examples

      n("0 1 2") |> s("bd")
      note("c3 e3") |> s("piano")
  """
  def s(pattern, sound_name) when is_binary(sound_name) do
    Pattern.set_param(pattern, :s, sound_name)
  end

  def sound(pattern, sound_name), do: s(pattern, sound_name)

  # Parse mini-notation to Pattern
  defp parse_to_pattern(mini_notation) do
    ast = UzuParser.Grammar.parse(mini_notation)
    Interpreter.interpret(ast)
  end

  # Convert numeric strings to numbers (Strudel convention)
  # Only used in note() and n() where numeric values have semantic meaning
  # s() keeps all values as strings since they are sample names
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
end
