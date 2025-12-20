defmodule UzuPattern.Pattern.Visualization do
  @moduledoc """
  Visualization painter functions for patterns.

  Painters attach visualization configuration to patterns. When patterns are
  evaluated, the painters are extracted and routed to appropriate visualization
  backends (inline CodeMirror widgets, etc.).

  ## Naming Convention (matches Strudel)

  Leading underscore functions render as inline CodeMirror widgets:
  - `_pianoroll/2` - Timeline with note rectangles
  - `_spiral/2` - Circular pattern display
  - `_punchcard/2` - Vertically-stacked events
  - `_scope/2` - Oscilloscope waveform
  - `_spectrum/2` - Frequency spectrum analyzer

  Future: non-underscore variants for overlay visualizations.

  ## Examples

      # Inline pianoroll below the code
      n("0 2 4") |> _pianoroll(cycles: 4)

      # Multiple inline visualizations
      s("bd sd") |> _pianoroll() |> _scope()
  """

  alias UzuPattern.Pattern

  # Inline visualizations (CodeMirror widgets)

  @doc """
  Add inline pianoroll visualization - timeline with note rectangles.

  Renders as a CodeMirror widget below the pattern code.

  ## Options
  - `:cycles` - Number of cycles to display (default: 4)
  - `:playhead` - Playhead position 0.0-1.0 (default: 0.5)
  - `:width` - Widget width in pixels (default: 500)
  - `:height` - Widget height in pixels (default: 60)
  """
  def _pianoroll(%Pattern{} = pattern, opts \\ []) do
    add_painter(pattern, :pianoroll, opts)
  end

  @doc """
  Add inline spiral visualization - circular pattern display.

  Renders as a CodeMirror widget below the pattern code.

  ## Options
  - `:stretch` - Spiral stretch factor (default: 1)
  - `:size` - Size in pixels (default: 80)
  """
  def _spiral(%Pattern{} = pattern, opts \\ []) do
    add_painter(pattern, :spiral, opts)
  end

  @doc """
  Add inline punchcard visualization - vertically-stacked events.

  Renders as a CodeMirror widget below the pattern code.

  ## Options
  - `:vertical` - Vertical spacing (default: 1)
  - `:labels` - Show labels (default: true)
  """
  def _punchcard(%Pattern{} = pattern, opts \\ []) do
    add_painter(pattern, :punchcard, opts)
  end

  @doc """
  Add inline oscilloscope visualization.

  Renders as a CodeMirror widget below the pattern code.
  Requires browser with WebAudio AnalyserNode.

  ## Options
  - `:width` - Widget width in pixels (default: 500)
  - `:height` - Widget height in pixels (default: 60)
  """
  def _scope(%Pattern{} = pattern, opts \\ []) do
    add_painter(pattern, :scope, Keyword.put(opts, :audio_viz, true))
  end

  @doc """
  Add inline spectrum analyzer visualization.

  Renders as a CodeMirror widget below the pattern code.
  Requires browser with WebAudio AnalyserNode.

  ## Options
  - `:width` - Widget width in pixels (default: 500)
  - `:height` - Widget height in pixels (default: 60)
  """
  def _spectrum(%Pattern{} = pattern, opts \\ []) do
    add_painter(pattern, :spectrum, Keyword.put(opts, :audio_viz, true))
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
      target: :inline,
      audio_viz: Keyword.get(opts, :audio_viz, false),
      options: opts |> Keyword.drop([:audio_viz]) |> Map.new()
    }

    painters = Map.get(meta, :painters, [])
    %{pattern | metadata: Map.put(meta, :painters, painters ++ [painter])}
  end
end
