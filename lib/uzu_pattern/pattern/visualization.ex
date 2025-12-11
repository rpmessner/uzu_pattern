defmodule UzuPattern.Pattern.Visualization do
  @moduledoc """
  Visualization painter functions for patterns.

  Painters attach visualization configuration to patterns. When patterns are
  evaluated, the painters are extracted and routed to appropriate visualization
  backends (browser overlay, inline widgets, native visualizers, etc.).

  ## Two Categories

  **Pattern visualizations** (server-coordinated):
  - `pianoroll/2` - Timeline with note rectangles
  - `spiral/2` - Circular pattern display
  - `punchcard/2` - Vertically-stacked events

  **Audio visualizations** (browser-only, require AnalyserNode):
  - `spectrum/2` - Frequency spectrum analyzer
  - `scope/2` - Oscilloscope waveform

  ## Targets

  - `:overlay` - Full-screen overlay canvas (default)
  - `:inline` - CodeMirror inline widget
  - `:all` - Both overlay and inline

  ## Examples

      # Add pianoroll to pattern
      n("0 2 4") |> pianoroll(cycles: 4)

      # Multiple visualizations
      s("bd sd") |> pianoroll() |> scope(target: :inline)

      # Inline only
      n("0 2 4") |> spiral(target: :inline)
  """

  alias UzuPattern.Pattern

  # Pattern visualizations (server-coordinated)

  @doc """
  Add pianoroll visualization - timeline with note rectangles.

  ## Options
  - `:cycles` - Number of cycles to display (default: 4)
  - `:playhead` - Playhead position 0.0-1.0 (default: 0.5)
  - `:target` - Where to render: `:overlay`, `:inline`, or `:all` (default: `:overlay`)
  """
  def pianoroll(%Pattern{} = pattern, opts \\ []) do
    add_painter(pattern, :pianoroll, opts)
  end

  @doc """
  Add spiral visualization - circular pattern display.

  ## Options
  - `:stretch` - Spiral stretch factor (default: 1)
  - `:size` - Size in pixels (default: 80)
  - `:target` - Where to render (default: `:overlay`)
  """
  def spiral(%Pattern{} = pattern, opts \\ []) do
    add_painter(pattern, :spiral, opts)
  end

  @doc """
  Add punchcard visualization - vertically-stacked events.

  ## Options
  - `:vertical` - Vertical spacing (default: 1)
  - `:labels` - Show labels (default: true)
  - `:target` - Where to render (default: `:overlay`)
  """
  def punchcard(%Pattern{} = pattern, opts \\ []) do
    add_painter(pattern, :punchcard, opts)
  end

  # Audio visualizations (browser-only, need AnalyserNode)

  @doc """
  Add spectrum analyzer visualization.

  Requires browser with WebAudio AnalyserNode - won't render on native clients.

  ## Options
  - `:target` - Where to render (default: `:overlay`)
  """
  def spectrum(%Pattern{} = pattern, opts \\ []) do
    add_painter(pattern, :spectrum, Keyword.put(opts, :audio_viz, true))
  end

  @doc """
  Add oscilloscope visualization.

  Requires browser with WebAudio AnalyserNode - won't render on native clients.

  ## Options
  - `:target` - Where to render (default: `:overlay`)
  """
  def scope(%Pattern{} = pattern, opts \\ []) do
    add_painter(pattern, :scope, Keyword.put(opts, :audio_viz, true))
  end

  # Query functions

  @doc """
  Get all painters attached to a pattern.
  """
  def get_painters(%Pattern{metadata: meta}) do
    Map.get(meta, :painters, [])
  end

  @doc """
  Check if pattern has any painters attached.
  """
  def has_painters?(%Pattern{} = pattern) do
    get_painters(pattern) != []
  end

  # Private

  defp add_painter(%Pattern{metadata: meta} = pattern, type, opts) do
    painter = %{
      type: type,
      target: Keyword.get(opts, :target, :overlay),
      audio_viz: Keyword.get(opts, :audio_viz, false),
      options: opts |> Keyword.drop([:target, :audio_viz]) |> Map.new()
    }

    painters = Map.get(meta, :painters, [])
    %{pattern | metadata: Map.put(meta, :painters, painters ++ [painter])}
  end
end
