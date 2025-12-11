defmodule UzuPattern.Hap do
  @moduledoc """
  A Hap (happening) represents a pattern event with precise timing semantics.

  This adopts Strudel's Hap format for compatibility and correct boundary handling.

  ## Fields

  - `whole` - The complete event timespan, or nil for continuous events
  - `part` - The portion intersecting the query window (always present)
  - `value` - Map of all parameters (s, n, note, gain, pan, etc.)
  - `context` - Metadata: source locations, tags

  ## Whole vs Part

  When querying a pattern, events may extend beyond the query window.

  Example: Query [0.0, 1.0), but event naturally spans [0.8, 1.2):

      %Hap{
        whole: %{begin: 0.8, end: 1.2},  # True extent
        part:  %{begin: 0.8, end: 1.0},  # Clipped to query
        value: %{s: "bd"}
      }

  The scheduler uses `whole.begin` to know when to trigger the sound,
  while `part` indicates what portion was requested.

  If the same pattern is queried for [1.0, 2.0), you'd get:

      %Hap{
        whole: %{begin: 0.8, end: 1.2},  # Same true extent
        part:  %{begin: 1.0, end: 1.2},  # Different clip
        value: %{s: "bd"}
      }

  Both haps represent the same event - the scheduler should only trigger
  the sound once, at whole.begin (0.8).

  ## Continuous Events

  For continuously varying values (signals), `whole` is nil:

      %Hap{
        whole: nil,                      # No discrete onset
        part:  %{begin: 0.5, end: 1.0},
        value: %{freq: 440.0}
      }

  The value was sampled at part.midpoint (0.75 in this case).

  ## Value Map

  All parameters live in value using short names (Strudel convention):

      %{
        s: "bd",           # sound/sample bank
        n: 0,              # sample number
        note: 60,          # MIDI note
        gain: 0.8,         # amplitude 0-1
        pan: 0.0,          # stereo -1 to 1
        speed: 1.0,        # playback rate
        begin: 0.0,        # sample slice start
        end: 1.0,          # sample slice end
      }

  ## Context

  Metadata accumulated through pattern operations:

      %{
        locations: [%{source_start: 0, source_end: 5}],
        tags: ["drums", "loop"]
      }
  """

  alias UzuPattern.TimeSpan

  @type timespan :: TimeSpan.t()

  @type t :: %__MODULE__{
          whole: timespan() | nil,
          part: timespan(),
          value: map(),
          context: map()
        }

  defstruct whole: nil,
            part: %{begin: 0.0, end: 1.0},
            value: %{},
            context: %{locations: [], tags: []}

  @doc """
  Create a new discrete Hap (has a definite onset).

  The whole and part start out the same - they diverge when the hap
  is clipped by a query boundary.
  """
  @spec new(timespan(), map(), map()) :: t()
  def new(timespan, value, context \\ %{}) do
    %__MODULE__{
      whole: timespan,
      part: timespan,
      value: value,
      context: Map.merge(%{locations: [], tags: []}, context)
    }
  end

  @doc """
  Create a continuous Hap (no discrete onset, value sampled from signal).

  Continuous haps have whole: nil to indicate there's no specific
  moment when the event "starts" - it's a sampled value from a
  continuously varying signal.
  """
  @spec continuous(timespan(), map(), map()) :: t()
  def continuous(part, value, context \\ %{}) do
    %__MODULE__{
      whole: nil,
      part: part,
      value: value,
      context: Map.merge(%{locations: [], tags: []}, context)
    }
  end

  @doc """
  Check if this hap has a discrete onset (whole is not nil).
  """
  @spec discrete?(t()) :: boolean()
  def discrete?(%__MODULE__{whole: nil}), do: false
  def discrete?(%__MODULE__{whole: _}), do: true

  @doc """
  Check if this hap is continuous (whole is nil).
  """
  @spec continuous?(t()) :: boolean()
  def continuous?(%__MODULE__{whole: nil}), do: true
  def continuous?(%__MODULE__{whole: _}), do: false

  @doc """
  Get the onset time (when to trigger the sound).

  For discrete events, this is whole.begin.
  For continuous events, returns nil (no specific onset).
  """
  @spec onset(t()) :: float() | nil
  def onset(%__MODULE__{whole: nil}), do: nil
  def onset(%__MODULE__{whole: %{begin: b}}), do: b

  @doc """
  Get the duration of the whole event.

  Returns nil for continuous events.
  """
  @spec duration(t()) :: float() | nil
  def duration(%__MODULE__{whole: nil}), do: nil
  def duration(%__MODULE__{whole: whole}), do: TimeSpan.duration(whole)

  @doc """
  Get a value from the hap's value map.
  """
  @spec get(t(), atom() | String.t(), any()) :: any()
  def get(%__MODULE__{value: value}, key, default \\ nil) do
    Map.get(value, key, default)
  end

  @doc """
  Put a value in the hap's value map.
  """
  @spec put(t(), atom() | String.t(), any()) :: t()
  def put(%__MODULE__{value: value} = hap, key, val) do
    %{hap | value: Map.put(value, key, val)}
  end

  @doc """
  Merge values into the hap's value map.
  """
  @spec merge(t(), map()) :: t()
  def merge(%__MODULE__{value: value} = hap, new_values) do
    %{hap | value: Map.merge(value, new_values)}
  end

  @doc """
  Add a source location to the context.

  Locations track where in the source code this hap originated,
  useful for editor highlighting.
  """
  @spec with_location(t(), map()) :: t()
  def with_location(%__MODULE__{context: context} = hap, location) do
    locations = Map.get(context, :locations, [])
    %{hap | context: Map.put(context, :locations, locations ++ [location])}
  end

  @doc """
  Add a tag to the context.

  Tags are used for filtering and identification.
  """
  @spec with_tag(t(), String.t() | atom()) :: t()
  def with_tag(%__MODULE__{context: context} = hap, tag) do
    tags = Map.get(context, :tags, [])
    tag_str = if is_atom(tag), do: Atom.to_string(tag), else: tag
    %{hap | context: Map.put(context, :tags, tags ++ [tag_str])}
  end

  @doc """
  Check if hap has a specific tag.
  """
  @spec has_tag?(t(), String.t() | atom()) :: boolean()
  def has_tag?(%__MODULE__{context: context}, tag) do
    tag_str = if is_atom(tag), do: Atom.to_string(tag), else: tag
    tag_str in Map.get(context, :tags, [])
  end

  @doc """
  Set the part timespan (typically from query clipping).

  Returns nil if the new part doesn't intersect with the current whole
  (for discrete events) or is invalid.
  """
  @spec with_part(t(), timespan()) :: t() | nil
  def with_part(%__MODULE__{whole: nil} = hap, new_part) do
    # Continuous event - just update part
    %{hap | part: new_part}
  end

  def with_part(%__MODULE__{whole: whole} = hap, new_part) do
    # Discrete event - new part should intersect with whole
    case TimeSpan.intersection(whole, new_part) do
      nil -> nil
      clipped_part -> %{hap | part: clipped_part}
    end
  end

  @doc """
  Shift both whole and part by an offset.
  """
  @spec shift(t(), number()) :: t()
  def shift(%__MODULE__{whole: nil, part: part} = hap, offset) do
    %{hap | part: TimeSpan.shift(part, offset)}
  end

  def shift(%__MODULE__{whole: whole, part: part} = hap, offset) do
    %{hap | whole: TimeSpan.shift(whole, offset), part: TimeSpan.shift(part, offset)}
  end

  @doc """
  Scale both whole and part by a factor.
  """
  @spec scale(t(), number()) :: t()
  def scale(%__MODULE__{whole: nil, part: part} = hap, factor) do
    %{hap | part: TimeSpan.scale(part, factor)}
  end

  def scale(%__MODULE__{whole: whole, part: part} = hap, factor) do
    %{hap | whole: TimeSpan.scale(whole, factor), part: TimeSpan.scale(part, factor)}
  end
end
