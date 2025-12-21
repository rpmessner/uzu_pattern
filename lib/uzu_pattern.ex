defmodule UzuPattern do
  @moduledoc """
  Pattern orchestration library for Strudel.js-style transformations.

  UzuPattern provides pattern manipulation functions that work with events
  from UzuParser. It enables Strudel.js-style live coding patterns with
  transformations like `fast`, `slow`, `rev`, `stack`, `cat`, `every`, and more.

  ## Architecture

  ```
  UzuParser (parsing) → UzuPattern.Interpreter → UzuPattern.Pattern → Waveform (audio)
  ```

  - **UzuParser** parses mini-notation strings into AST
  - **UzuPattern.Interpreter** converts AST into composable Patterns
  - **UzuPattern.Pattern** provides query-based pattern composition
  - **Waveform** schedules and plays the events via Web Audio / SuperCollider

  ## Quick Start

  ```elixir
  alias UzuPattern.{Interpreter, Pattern}

  # Parse and interpret mini-notation
  pattern = "bd sd hh cp"
            |> UzuParser.Grammar.parse()
            |> Interpreter.interpret()

  # Apply transformations
  pattern
  |> Pattern.fast(2)
  |> Pattern.every(4, &Pattern.rev/1)
  |> Pattern.query(0)  # Get events for cycle 0
  ```

  ## Pattern Struct

  The `%Pattern{}` struct wraps a query function:

  ```elixir
  %Pattern{
    query: fn cycle -> [%Hap{}, ...] end,
    metadata: %{}
  }
  ```

  ## Query Function for Waveform

  UzuPattern provides a `query/2` function that Waveform can call each cycle:

  ```elixir
  # In Waveform's PatternScheduler:
  query_fn = fn cycle -> UzuPattern.Pattern.query(pattern, cycle) end
  PatternScheduler.schedule_pattern(:drums, query_fn)
  ```

  This allows cycle-aware transformations like `every(4, rev)` to work correctly.

  ## Transformation Categories

  ### Time Modifiers
  - `fast/2` - Speed up pattern
  - `slow/2` - Slow down pattern
  - `rev/1` - Reverse pattern
  - `early/2` - Shift earlier
  - `late/2` - Shift later
  - `ply/2` - Repeat each event N times
  - `compress/3` - Squeeze pattern into time window
  - `zoom/3` - Extract and expand time window
  - `linger/2` - Loop first portion of pattern

  ### Combinators
  - `stack/1` - Play patterns simultaneously
  - `fastcat/1` - Sequence patterns within cycle
  - `slowcat/1` - Alternate patterns across cycles
  - `palindrome/1` - Forward then backward
  - `superimpose/2` - Layer with transformed copy
  - `echo/4` - Create fading echoes

  ### Conditional (Cycle-Aware)
  - `every/3` - Apply function every N cycles
  - `sometimes/2` - Apply with 50% probability
  - `iter/2` - Rotate pattern each cycle
  - `degrade/1` - Randomly remove events

  ### Stereo
  - `jux/2` - Apply function to right channel only

  ### Rhythm
  - `euclid/3` - Euclidean rhythm distribution
  - `swing/2` - Add swing timing

  See `UzuPattern.Pattern` for full documentation.
  """

  alias UzuPattern.{Interpreter, Pattern}

  @doc """
  Parse and interpret a mini-notation string into a Pattern.

  ## Examples

      iex> pattern = UzuPattern.parse("bd sd hh cp")
      iex> events = UzuPattern.Pattern.query(pattern, 0)
      iex> length(events)
      4
  """
  def parse(source) when is_binary(source) do
    source
    |> UzuParser.Grammar.parse()
    |> Interpreter.interpret()
  end

  @doc """
  Query a pattern for events at a specific cycle.

  Convenience function that delegates to `Pattern.query/2`.
  """
  defdelegate query(pattern, cycle), to: Pattern
end
