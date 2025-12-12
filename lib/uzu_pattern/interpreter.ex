defmodule UzuPattern.Interpreter do
  @moduledoc """
  Interprets parsed AST into Pattern compositions.

  The interpreter walks the AST and builds Pattern compositions that
  properly handle nested patterns like `<[a b]*2 [c d]*2>`.

  ## Architecture

  The interpreter walks the AST and builds Pattern compositions:
  - Sequences `[a b c]` → `Pattern.fastcat([...])`
  - Alternation `<a b c>` → `Pattern.slowcat([...])`
  - Polyphony `[a, b, c]` → `Pattern.stack([...])`
  - Repetition `a*4` → `Pattern.fast(pattern, 4)`
  - Atoms `bd:1` → `Pattern.pure("bd", sample: 1)`
  """

  alias UzuPattern.Pattern
  alias UzuPattern.Euclidean
  alias UzuPattern.Hap

  @doc """
  Interpret an AST into a Pattern.

  Takes the AST from UzuParser.Grammar.parse/1 and converts it to a
  composable Pattern that can be queried for any cycle.
  """
  def interpret({:ok, ast}) do
    interpret_node(ast)
  end

  def interpret(ast) do
    interpret_node(ast)
  end

  # ============================================================================
  # Node Interpretation
  # ============================================================================

  # Top-level sequence
  defp interpret_node({:sequence, items}) do
    interpret_sequence(items)
  end

  # Stack (polyphony)
  defp interpret_node({:stack, sequences}) do
    patterns = Enum.map(sequences, &interpret_sequence/1)
    Pattern.stack(patterns)
  end

  # Subdivision with children
  defp interpret_node(%{type: :subdivision, children: children} = node) do
    inner = extract_inner(children)
    base_pattern = interpret_node(inner)

    # Apply modifiers
    case node do
      %{repeat: n} when is_integer(n) and n > 1 ->
        Pattern.fast(base_pattern, n)

      %{division: div} when is_number(div) ->
        Pattern.slow(base_pattern, div)

      _ ->
        base_pattern
    end
  end

  # Alternation (slowcat)
  defp interpret_node(%{type: :alternation, children: children}) do
    items = extract_sequence_items(children)
    patterns = Enum.map(items, &interpret_item/1)
    Pattern.slowcat(patterns)
  end

  # Polymetric
  defp interpret_node(%{type: :polymetric, children: children} = node) do
    groups = extract_groups(children)

    case node do
      %{steps: steps} when is_integer(steps) ->
        interpret_polymetric_stepped(groups, steps)

      _ ->
        interpret_polymetric(groups)
    end
  end

  # Random choice
  defp interpret_node(%{type: :random_choice} = node) do
    children = Map.get(node, :children, [])
    patterns = Enum.map(children, &interpret_atom/1)

    # Random choice selects one pattern per cycle (using cycle as seed)
    Pattern.new(fn cycle ->
      :rand.seed(:exsss, {cycle, cycle * 7, cycle * 13})
      index = :rand.uniform(length(patterns)) - 1
      pattern = Enum.at(patterns, index)
      Pattern.query(pattern, cycle)
    end)
  end

  # Single atom
  defp interpret_node(%{type: :atom} = atom) do
    interpret_atom(atom)
  end

  # Rest
  defp interpret_node(%{type: :rest}) do
    Pattern.silence()
  end

  # Elongation (handled in sequence processing)
  defp interpret_node(%{type: :elongation}) do
    Pattern.silence()
  end

  # Fallback
  defp interpret_node(_) do
    Pattern.silence()
  end

  # ============================================================================
  # Sequence Interpretation
  # ============================================================================

  defp interpret_sequence(items) do
    # First, process elongations to adjust weights
    processed = process_elongations(items)

    # Calculate total weight
    total_weight =
      processed
      |> Enum.map(&get_weight/1)
      |> Enum.sum()

    if total_weight == 0 do
      Pattern.silence()
    else
      # Convert to patterns with their weight fractions
      weighted_patterns =
        processed
        |> Enum.map(fn item ->
          weight = get_weight(item)
          fraction = weight / total_weight
          pattern = interpret_item(item)
          {pattern, fraction}
        end)

      # Build a custom query that handles weighted timing
      Pattern.new(fn cycle ->
        {haps, _} =
          Enum.reduce(weighted_patterns, {[], 0.0}, fn {pattern, fraction}, {acc, offset} ->
            # Query the pattern and rescale its haps to this slot
            pattern_haps =
              pattern
              |> Pattern.query(cycle)
              |> Enum.map(fn hap ->
                # Transform whole and part timespans
                new_whole = scale_and_offset_timespan(hap.whole, fraction, offset)
                new_part = scale_and_offset_timespan(hap.part, fraction, offset)
                %{hap | whole: new_whole, part: new_part}
              end)

            {acc ++ pattern_haps, offset + fraction}
          end)

        haps
      end)
    end
  end

  # Process elongations to increase weight of previous items
  defp process_elongations(items) do
    {result, _} =
      Enum.reduce(items, {[], nil}, fn item, {acc, prev} ->
        case item do
          %{type: :elongation} ->
            case prev do
              nil ->
                {acc, nil}

              %{} = prev_item ->
                new_weight = (prev_item[:weight] || 1.0) + 1.0
                updated = Map.put(prev_item, :weight, new_weight)
                {List.replace_at(acc, -1, updated), updated}
            end

          _ ->
            {acc ++ [item], item}
        end
      end)

    result
  end

  defp get_weight(%{type: :rest}), do: 1.0
  defp get_weight(%{type: :elongation}), do: 0.0
  defp get_weight(%{weight: w}) when is_number(w), do: w
  defp get_weight(_), do: 1.0

  # ============================================================================
  # Item Interpretation
  # ============================================================================

  defp interpret_item(%{type: :rest}), do: Pattern.silence()

  defp interpret_item(%{type: :atom} = atom) do
    base_pattern = interpret_atom(atom)

    # Apply modifiers
    base_pattern
    |> maybe_apply_repeat(atom)
    |> maybe_apply_replicate(atom)
    |> maybe_apply_euclidean(atom)
  end

  defp interpret_item(%{type: :subdivision} = sub) do
    interpret_node(sub)
  end

  defp interpret_item(%{type: :alternation} = alt) do
    interpret_node(alt)
  end

  defp interpret_item(%{type: :polymetric} = poly) do
    interpret_node(poly)
  end

  defp interpret_item(%{type: :random_choice} = choice) do
    interpret_node(choice)
  end

  defp interpret_item({:sequence, items}) do
    interpret_sequence(items)
  end

  defp interpret_item({:stack, seqs}) do
    patterns = Enum.map(seqs, &interpret_sequence/1)
    Pattern.stack(patterns)
  end

  defp interpret_item(_), do: Pattern.silence()

  # ============================================================================
  # Atom Interpretation
  # ============================================================================

  defp interpret_atom(%{type: :atom} = atom) do
    base_params = atom[:params] || %{}

    # Add probability if present
    params =
      case atom[:probability] do
        nil -> base_params
        prob -> Map.put(base_params, :probability, prob)
      end

    # Add division if present
    params =
      case atom[:division] do
        nil -> params
        div -> Map.put(params, :division, div)
      end

    Pattern.pure(
      atom.value,
      sample: atom[:sample],
      params: params,
      start: atom[:source_start],
      end: atom[:source_end]
    )
  end

  defp interpret_atom(_), do: Pattern.silence()

  # ============================================================================
  # Modifier Application
  # ============================================================================

  defp maybe_apply_repeat(pattern, %{repeat: n}) when is_integer(n) and n > 1 do
    Pattern.fast(pattern, n)
  end

  defp maybe_apply_repeat(pattern, _), do: pattern

  defp maybe_apply_replicate(pattern, %{replicate: n}) when is_integer(n) and n > 1 do
    Pattern.fast(pattern, n)
  end

  defp maybe_apply_replicate(pattern, _), do: pattern

  defp maybe_apply_euclidean(pattern, %{euclidean: euclid}) when is_list(euclid) do
    {k, n, offset} =
      case euclid do
        [k, n] -> {k, n, 0}
        [k, n, offset] -> {k, n, offset}
      end

    # Generate euclidean rhythm
    rhythm = Euclidean.rhythm(k, n, offset)

    # Create a pattern that plays only on hits
    Pattern.new(fn cycle ->
      base_haps = Pattern.query(pattern, cycle)

      rhythm
      |> Enum.with_index()
      |> Enum.flat_map(fn {hit, i} ->
        if hit == 1 do
          step = 1.0 / n
          time = i * step

          Enum.map(base_haps, fn hap ->
            set_hap_timespan(hap, time, time + step)
          end)
        else
          []
        end
      end)
    end)
  end

  defp maybe_apply_euclidean(pattern, _), do: pattern

  # ============================================================================
  # Polymetric Interpretation
  # ============================================================================

  defp interpret_polymetric(groups) do
    patterns = Enum.map(groups, &interpret_group/1)
    Pattern.stack(patterns)
  end

  defp interpret_polymetric_stepped(groups, steps) do
    step_duration = 1.0 / steps

    patterns =
      Enum.map(groups, fn group ->
        items = extract_sequence_items(group)
        token_count = length(items)

        Pattern.new(fn cycle ->
          items
          |> Enum.with_index()
          |> Enum.flat_map(fn {item, idx} ->
            time_offset = idx / token_count
            pattern = interpret_item(item)

            pattern
            |> Pattern.query(cycle)
            |> Enum.map(fn hap ->
              set_hap_timespan(hap, time_offset, time_offset + step_duration)
            end)
          end)
        end)
      end)

    Pattern.stack(patterns)
  end

  defp interpret_group({:sequence, items}), do: interpret_sequence(items)
  defp interpret_group(sequence: items), do: interpret_sequence(items)
  defp interpret_group(items) when is_list(items), do: interpret_sequence(items)
  defp interpret_group(_), do: Pattern.silence()

  # ============================================================================
  # Helpers
  # ============================================================================

  defp extract_inner(sequence: items), do: {:sequence, items}
  defp extract_inner(stack: seqs), do: {:stack, seqs}
  defp extract_inner({:sequence, _} = seq), do: seq
  defp extract_inner({:stack, _} = stack), do: stack
  defp extract_inner(other), do: other

  defp extract_sequence_items(sequence: items), do: items
  defp extract_sequence_items({:sequence, items}), do: items
  defp extract_sequence_items(_), do: []

  defp extract_groups(groups: g), do: g
  defp extract_groups({:groups, g}), do: g
  defp extract_groups(_), do: []

  # ============================================================================
  # Hap Timespan Helpers
  # ============================================================================

  # Scale and offset a timespan (works for both whole and part)
  defp scale_and_offset_timespan(nil, _fraction, _offset), do: nil

  defp scale_and_offset_timespan(%{begin: b, end: e}, fraction, offset) do
    %{begin: offset + b * fraction, end: offset + (b + (e - b)) * fraction}
  end

  # Set a hap's timespan to specific begin/end values
  defp set_hap_timespan(%Hap{} = hap, begin_time, end_time) do
    timespan = %{begin: begin_time, end: end_time}
    %{hap | whole: timespan, part: timespan}
  end
end
