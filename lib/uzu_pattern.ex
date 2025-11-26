defmodule UzuPattern do
  @moduledoc """
  Pattern orchestration library for Strudel.js-style transformations.

  UzuPattern provides pattern manipulation functions that work with events
  from UzuParser. It enables Strudel.js-style live coding patterns with
  transformations like `fast`, `slow`, `rev`, `stack`, `cat`, `every`, and more.

  ## Architecture

  ```
  UzuParser (parsing) → UzuPattern (transformation) → Waveform (audio)
  ```

  - **UzuParser** parses mini-notation strings into `[%Event{}]`
  - **UzuPattern** transforms patterns with `fast`, `slow`, `rev`, etc.
  - **Waveform** schedules and plays the events via SuperDirt/MIDI

  ## Quick Start

  ```elixir
  alias UzuPattern.Pattern

  # Create a pattern from mini-notation
  pattern = Pattern.new("bd sd hh cp")

  # Apply transformations
  pattern
  |> Pattern.fast(2)
  |> Pattern.every(4, &Pattern.rev/1)
  |> Pattern.query(0)  # Get events for cycle 0
  ```

  ## Pattern Struct

  The `%Pattern{}` struct wraps events and transformations:

  ```elixir
  %Pattern{
    events: [%Event{}, ...],     # Base events
    transforms: [...]            # Pending cycle-aware transforms
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

  ### Combinators
  - `stack/1` - Play patterns simultaneously
  - `cat/1` - Play patterns sequentially
  - `palindrome/1` - Forward then backward

  ### Conditional (Cycle-Aware)
  - `every/3` - Apply function every N cycles
  - `sometimes/2` - Apply with 50% probability
  - `degrade/1` - Randomly remove events

  ### Stereo
  - `jux/2` - Apply function to right channel only

  See `UzuPattern.Pattern` for full documentation.
  """

  alias UzuPattern.Pattern

  @doc """
  Create a new pattern from a mini-notation string.

  Convenience function that delegates to `Pattern.new/1`.

  ## Examples

      iex> pattern = UzuPattern.new("bd sd hh cp")
      iex> length(pattern.events)
      4
  """
  defdelegate new(source), to: Pattern

  @doc """
  Query a pattern for events at a specific cycle.

  Convenience function that delegates to `Pattern.query/2`.

  ## Examples

      iex> pattern = UzuPattern.new("bd sd")
      iex> events = UzuPattern.query(pattern, 0)
      iex> length(events)
      2
  """
  defdelegate query(pattern, cycle), to: Pattern

  @doc """
  Extract events from a pattern.

  Convenience function that delegates to `Pattern.events/1`.

  ## Examples

      iex> pattern = UzuPattern.new("bd sd")
      iex> events = UzuPattern.events(pattern)
      iex> length(events)
      2
  """
  defdelegate events(pattern), to: Pattern
end
