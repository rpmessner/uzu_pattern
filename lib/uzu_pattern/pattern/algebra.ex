defmodule UzuPattern.Pattern.Algebra do
  @moduledoc """
  Pattern algebra operations: functor, applicative, and monadic primitives.

  These enable patterns of values to be combined with patterns of functions,
  supporting pattern arguments in transformations like `fast("<2 4>", pattern)`.

  ## Functor Operations

  - `fmap/2` / `with_value/2` - Apply a function to each hap's value

  ## Applicative Operations

  - `app_both/2` - Apply pattern of functions to pattern of values (intersect wholes)
  - `app_left/2` - Structure comes from the function pattern (left)
  - `app_right/2` - Structure comes from the value pattern (right)

  ## Usage

  These primitives enable pattern arguments for transformations:

      # Pattern of speeds applied to a pattern
      speed_pattern = Pattern.slowcat([Pattern.pure("2"), Pattern.pure("4")])
      |> Algebra.fmap(fn %{s: s} -> String.to_integer(s) end)

      # Combine with target pattern using applicative
      Algebra.app_left(
        Algebra.fmap(speed_pattern, fn n -> &Pattern.fast(&1, n) end),
        target_pattern
      )
  """

  alias UzuPattern.Hap
  alias UzuPattern.Pattern
  alias UzuPattern.Time, as: T
  alias UzuPattern.TimeSpan

  # ============================================================================
  # Functor: fmap / with_value
  # ============================================================================

  @doc """
  Apply a function to the value of each hap in a pattern.

  This is the functor `fmap` operation. The function receives the hap's value
  map and should return a new value map.

  ## Examples

      iex> p = Pattern.pure("bd")
      iex> p = Algebra.fmap(p, fn value -> Map.put(value, :gain, 0.5) end)
      iex> [hap] = Pattern.query(p, 0)
      iex> hap.value.gain
      0.5

      iex> p = Pattern.pure("60")
      iex> p = Algebra.fmap(p, fn %{s: s} -> %{note: String.to_integer(s)} end)
      iex> [hap] = Pattern.query(p, 0)
      iex> hap.value.note
      60
  """
  @spec fmap(Pattern.t(), (map() -> map())) :: Pattern.t()
  def fmap(%Pattern{} = pattern, func) when is_function(func, 1) do
    Pattern.new(fn span ->
      pattern
      |> Pattern.query_span(span)
      |> Enum.map(fn hap -> %{hap | value: func.(hap.value)} end)
    end)
  end

  @doc """
  Alias for fmap - apply a function to each hap's value.
  """
  @spec with_value(Pattern.t(), (map() -> map())) :: Pattern.t()
  def with_value(pattern, func), do: fmap(pattern, func)

  # ============================================================================
  # Applicative: app variants
  # ============================================================================

  @doc """
  Applicative apply where structure comes from both patterns (intersection).

  For each pair of haps where the parts intersect:
  - The function from `pat_func` is applied to the value from `pat_val`
  - The new whole is the intersection of both wholes (or nil if either is nil)
  - The new part is the intersection of both parts

  This is the standard applicative `<*>` operation.

  ## Examples

      # Apply a pattern of functions to a pattern of values
      iex> funcs = Pattern.pure("double") |> Algebra.fmap(fn _ -> fn v -> Map.put(v, :n, 2) end end)
      iex> vals = Pattern.pure("bd")
      iex> result = Algebra.app_both(funcs, vals)
      iex> [hap] = Pattern.query(result, 0)
      iex> hap.value
      %{s: "bd", n: 2}
  """
  @spec app_both(Pattern.t(), Pattern.t()) :: Pattern.t()
  def app_both(%Pattern{} = pat_func, %Pattern{} = pat_val) do
    whole_func = fn
      nil, _ -> nil
      _, nil -> nil
      a, b -> TimeSpan.intersection(a, b)
    end

    app_with(pat_func, pat_val, whole_func)
  end

  @doc """
  Applicative apply where structure comes from the function pattern (left).

  The timing/structure of the function pattern drives the output.
  For each hap in `pat_func`, query `pat_val` within that hap's extent
  and apply the function.

  Use this when you want the left pattern to "drive" the timing.

  ## Examples

      # Speed pattern drives timing, target pattern provides values
      iex> speeds = Pattern.fastcat([Pattern.pure("2"), Pattern.pure("4")])
      iex> speeds = Algebra.fmap(speeds, fn %{s: s} -> fn v -> Map.put(v, :speed, String.to_integer(s)) end end)
      iex> target = Pattern.pure("bd")
      iex> result = Algebra.app_left(speeds, target)
      iex> haps = Pattern.query(result, 0)
      iex> length(haps)
      2
  """
  @spec app_left(Pattern.t(), Pattern.t()) :: Pattern.t()
  def app_left(%Pattern{} = pat_func, %Pattern{} = pat_val) do
    Pattern.new(fn span ->
      pat_func
      |> Pattern.query_span(span)
      |> Enum.flat_map(fn hap_func ->
        # Query value pattern within the function hap's extent
        query_span = whole_or_part(hap_func)

        pat_val
        |> Pattern.query_span(query_span)
        |> Enum.flat_map(fn hap_val ->
          # Parts must intersect
          case TimeSpan.intersection(hap_func.part, hap_val.part) do
            nil ->
              []

            new_part ->
              new_value = apply_func_value(hap_func.value, hap_val.value)
              new_context = combine_contexts(hap_func.context, hap_val.context)

              [
                %Hap{
                  whole: hap_func.whole,
                  part: new_part,
                  value: new_value,
                  context: new_context
                }
              ]
          end
        end)
      end)
    end)
  end

  @doc """
  Applicative apply where structure comes from the value pattern (right).

  The timing/structure of the value pattern drives the output.
  For each hap in `pat_val`, query `pat_func` within that hap's extent
  and apply the function.

  Use this when you want the right pattern to "drive" the timing.
  """
  @spec app_right(Pattern.t(), Pattern.t()) :: Pattern.t()
  def app_right(%Pattern{} = pat_func, %Pattern{} = pat_val) do
    Pattern.new(fn span ->
      pat_val
      |> Pattern.query_span(span)
      |> Enum.flat_map(fn hap_val ->
        # Query function pattern within the value hap's extent
        query_span = whole_or_part(hap_val)

        pat_func
        |> Pattern.query_span(query_span)
        |> Enum.flat_map(fn hap_func ->
          # Parts must intersect
          case TimeSpan.intersection(hap_func.part, hap_val.part) do
            nil ->
              []

            new_part ->
              new_value = apply_func_value(hap_func.value, hap_val.value)
              new_context = combine_contexts(hap_func.context, hap_val.context)

              [
                %Hap{
                  whole: hap_val.whole,
                  part: new_part,
                  value: new_value,
                  context: new_context
                }
              ]
          end
        end)
      end)
    end)
  end

  # ============================================================================
  # Monad: bind and join variants
  # ============================================================================

  @doc """
  Monadic bind with configurable whole-span strategy.

  For each hap in the outer pattern, applies `func` to get an inner pattern,
  then queries the inner pattern within the outer hap's part.

  The `choose_whole` function determines how to combine outer and inner wholes:
  - `fn outer, inner -> intersection(outer, inner) end` - standard bind
  - `fn outer, _inner -> outer end` - outer_bind
  - `fn _outer, inner -> inner end` - inner_bind
  """
  @spec bind_with(
          Pattern.t(),
          (map() -> Pattern.t()),
          (TimeSpan.t() | nil, TimeSpan.t() | nil -> TimeSpan.t() | nil)
        ) :: Pattern.t()
  def bind_with(%Pattern{} = pattern, func, choose_whole) when is_function(func, 1) and is_function(choose_whole, 2) do
    Pattern.new(fn span ->
      pattern
      |> Pattern.query_span(span)
      |> Enum.flat_map(fn outer_hap ->
        # Get inner pattern from function
        inner_pattern = func.(outer_hap.value)

        # Query inner pattern within the outer hap's part
        inner_pattern
        |> Pattern.query_span(outer_hap.part)
        |> Enum.map(fn inner_hap ->
          new_whole = choose_whole.(outer_hap.whole, inner_hap.whole)
          new_context = combine_contexts(outer_hap.context, inner_hap.context)

          %Hap{
            whole: new_whole,
            part: inner_hap.part,
            value: inner_hap.value,
            context: new_context
          }
        end)
      end)
    end)
  end

  @doc """
  Standard monadic bind - flattens a pattern of patterns.

  For each hap in the outer pattern, applies `func` to get an inner pattern,
  queries it within the outer hap's part, and combines wholes by intersection.

  This is the monad `>>=` operation.
  """
  @spec bind(Pattern.t(), (map() -> Pattern.t())) :: Pattern.t()
  def bind(%Pattern{} = pattern, func) when is_function(func, 1) do
    whole_func = fn
      nil, _ -> nil
      _, nil -> nil
      a, b -> TimeSpan.intersection(a, b)
    end

    bind_with(pattern, func, whole_func)
  end

  @doc """
  Flatten a pattern of patterns, intersecting wholes.

  Equivalent to `bind(pattern, fn p -> p end)` - the identity function.
  The values of the outer pattern must be patterns themselves.
  """
  @spec join(Pattern.t()) :: Pattern.t()
  def join(%Pattern{} = pat_of_pats) do
    bind(pat_of_pats, fn inner -> inner end)
  end

  @doc """
  Monadic bind where wholes come from the outer pattern.

  Use this when you want the outer pattern's structure to drive timing.
  """
  @spec outer_bind(Pattern.t(), (map() -> Pattern.t())) :: Pattern.t()
  def outer_bind(%Pattern{} = pattern, func) when is_function(func, 1) do
    bind_with(pattern, func, fn outer, _inner -> outer end)
  end

  @doc """
  Flatten a pattern of patterns, keeping outer wholes.
  """
  @spec outer_join(Pattern.t()) :: Pattern.t()
  def outer_join(%Pattern{} = pat_of_pats) do
    outer_bind(pat_of_pats, fn inner -> inner end)
  end

  @doc """
  Monadic bind where wholes come from the inner pattern.

  Use this when you want the inner pattern's structure to drive timing.
  This is the default for patternified functions in Strudel.
  """
  @spec inner_bind(Pattern.t(), (map() -> Pattern.t())) :: Pattern.t()
  def inner_bind(%Pattern{} = pattern, func) when is_function(func, 1) do
    bind_with(pattern, func, fn _outer, inner -> inner end)
  end

  @doc """
  Flatten a pattern of patterns, keeping inner wholes.
  """
  @spec inner_join(Pattern.t()) :: Pattern.t()
  def inner_join(%Pattern{} = pat_of_pats) do
    inner_bind(pat_of_pats, fn inner -> inner end)
  end

  @doc """
  Squeeze-join: flatten by focusing inner patterns into outer haps.

  This is the critical operation for pattern arguments. For each discrete
  outer hap, the inner pattern (which is the hap's value) is "focused" so
  that its entire cycle 0 fits within the outer hap's whole/part duration.

  This enables patterns like `fast("<2 4>", pat)` - for each cycle, the
  speed alternates between 2 and 4, with each inner pattern squeezed to
  fit within its controlling hap.

  Only processes discrete haps (with whole != nil) from the outer pattern.
  """
  @spec squeeze_join(Pattern.t()) :: Pattern.t()
  def squeeze_join(%Pattern{} = pat_of_pats) do
    Pattern.new(fn span ->
      # Get discrete haps from outer pattern
      pat_of_pats
      |> Pattern.query_span(span)
      |> Enum.filter(fn hap -> hap.whole != nil end)
      |> Enum.flat_map(fn outer_hap ->
        # The inner pattern is the outer hap's value
        inner_pattern = outer_hap.value

        # Focus the inner pattern so its cycle fits within the outer hap's extent
        focus_extent = Hap.whole_or_part(outer_hap)
        focused_pattern = focus_span(inner_pattern, focus_extent)

        # Query the focused pattern within the outer hap's part
        focused_pattern
        |> Pattern.query_span(outer_hap.part)
        |> Enum.flat_map(fn inner_hap ->
          # Combine wholes by intersection (if both present)
          new_whole =
            case {inner_hap.whole, outer_hap.whole} do
              {nil, _} ->
                nil

              {_, nil} ->
                nil

              {iw, ow} ->
                case TimeSpan.intersection(iw, ow) do
                  nil -> nil
                  intersected -> intersected
                end
            end

          # Combine parts by intersection
          case TimeSpan.intersection(inner_hap.part, outer_hap.part) do
            nil ->
              []

            new_part ->
              new_context = combine_contexts(outer_hap.context, inner_hap.context)

              [
                %Hap{
                  whole: new_whole,
                  part: new_part,
                  value: inner_hap.value,
                  context: new_context
                }
              ]
          end
        end)
      end)
    end)
  end

  @doc """
  Squeeze-bind: map to patterns then squeeze-join.

  Equivalent to `fmap(pattern, func) |> squeeze_join()`.
  """
  @spec squeeze_bind(Pattern.t(), (map() -> Pattern.t())) :: Pattern.t()
  def squeeze_bind(%Pattern{} = pattern, func) when is_function(func, 1) do
    pattern
    |> fmap(func)
    |> squeeze_join()
  end

  @doc """
  Focus a pattern so its cycle 0 fits within the given timespan.

  This transforms the pattern so that:
  - The pattern is shifted so cycle 0 aligns with span.begin
  - The pattern is scaled so one cycle fits within span duration
  - Queries outside the span still work but map to different cycles

  This is the key operation that enables squeeze_join to work.
  """
  @spec focus_span(Pattern.t(), TimeSpan.t()) :: Pattern.t()
  def focus_span(%Pattern{} = pattern, %{begin: b, end: e}) do
    duration = T.sub(e, b)

    # Create a new pattern that transforms queries
    # When queried at [qb, qe), we need to:
    # 1. Map the query span back to the original pattern's time
    # 2. Query the original pattern
    # 3. Map the results forward to the focused time
    Pattern.new(fn query_span ->
      # Map query span from focused time back to original pattern time
      # focused time t maps to original time: (t - b) / duration
      orig_begin = T.divide(T.sub(query_span.begin, b), duration)
      orig_end = T.divide(T.sub(query_span.end, b), duration)
      orig_span = %{begin: orig_begin, end: orig_end}

      # Query the original pattern
      pattern
      |> Pattern.query_span(orig_span)
      |> Enum.map(fn hap ->
        # Map hap times from original time to focused time
        # original time t maps to focused time: b + t * duration
        new_whole = map_timespan_to_focus(hap.whole, b, duration)
        new_part = map_timespan_to_focus(hap.part, b, duration)
        %{hap | whole: new_whole, part: new_part}
      end)
    end)
  end

  defp map_timespan_to_focus(nil, _b, _duration), do: nil

  defp map_timespan_to_focus(%{begin: tb, end: te}, b, duration) do
    # b + tb * duration, b + te * duration
    %{begin: T.add(b, T.mult(tb, duration)), end: T.add(b, T.mult(te, duration))}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  # Generic applicative with configurable whole-span strategy
  defp app_with(%Pattern{} = pat_func, %Pattern{} = pat_val, whole_func) do
    Pattern.new(fn span ->
      hap_funcs = Pattern.query_span(pat_func, span)
      hap_vals = Pattern.query_span(pat_val, span)

      for hap_func <- hap_funcs,
          hap_val <- hap_vals,
          # Parts must intersect
          new_part = TimeSpan.intersection(hap_func.part, hap_val.part),
          new_part != nil do
        new_whole = whole_func.(hap_func.whole, hap_val.whole)
        new_value = apply_func_value(hap_func.value, hap_val.value)
        new_context = combine_contexts(hap_func.context, hap_val.context)

        %Hap{whole: new_whole, part: new_part, value: new_value, context: new_context}
      end
    end)
  end

  # Apply a function value to a data value
  # The function pattern's value should be a function
  defp apply_func_value(func_value, data_value) when is_function(func_value, 1) do
    func_value.(data_value)
  end

  defp apply_func_value(%{func: func}, data_value) when is_function(func, 1) do
    func.(data_value)
  end

  defp apply_func_value(func_value, data_value) when is_map(func_value) do
    # If func_value is a map, look for a :func key, otherwise merge
    case Map.get(func_value, :func) do
      nil -> Map.merge(data_value, func_value)
      func when is_function(func, 1) -> func.(data_value)
    end
  end

  # Get whole if present, otherwise part (delegate to Hap)
  defp whole_or_part(%Hap{} = hap), do: Hap.whole_or_part(hap)

  # Combine contexts from two haps
  defp combine_contexts(ctx1, ctx2) do
    locations = (ctx1[:locations] || []) ++ (ctx2[:locations] || [])
    tags = (ctx1[:tags] || []) ++ (ctx2[:tags] || [])
    %{locations: locations, tags: tags}
  end
end
