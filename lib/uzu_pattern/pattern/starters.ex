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

  alias UzuPattern.Pattern
  alias UzuPattern.Interpreter

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
    base_pattern = parse_to_pattern(mini_notation)

    # Transform: convert sound values to :n parameters when they're numbers
    Pattern.new(fn cycle ->
      base_pattern
      |> Pattern.query(cycle)
      |> Enum.map(fn hap ->
        case hap.value[:s] do
          nil ->
            hap

          sound_str ->
            case Integer.parse(to_string(sound_str)) do
              {n, ""} ->
                new_value = hap.value |> Map.delete(:s) |> Map.put(:n, n)
                %{hap | value: new_value}

              _ ->
                hap
            end
        end
      end)
    end)
  end

  @doc """
  Create a note/pitch pattern from mini-notation.

  ## Examples

      note("c3 e3 g3")
      note("60 64 67")  # MIDI notes
  """
  def note(mini_notation) when is_binary(mini_notation) do
    parse_to_pattern(mini_notation)
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
end
