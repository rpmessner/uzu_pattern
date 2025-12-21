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

  alias UzuPattern.Euclidean
  alias UzuPattern.Hap
  alias UzuPattern.Pattern
  alias UzuPattern.Time, as: T
  alias UzuPattern.TimeSpan

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

    # Apply modifiers (in order: speed changes first, then probability)
    pattern =
      cond do
        is_integer(node[:repeat]) and node[:repeat] > 1 ->
          Pattern.fast(base_pattern, node[:repeat])

        is_integer(node[:replicate]) and node[:replicate] > 1 ->
          Pattern.fast(base_pattern, node[:replicate])

        is_number(node[:division]) ->
          Pattern.slow(base_pattern, node[:division])

        true ->
          base_pattern
      end

    # Apply probability if present
    apply_probability(pattern, node[:probability])
  end

  # Alternation (slowcat) with optional modifiers
  defp interpret_node(%{type: :alternation, children: children} = node) do
    items = extract_sequence_items(children)
    patterns = Enum.map(items, &interpret_item/1)
    base_pattern = Pattern.slowcat(patterns)

    # Apply modifiers (in order: speed changes first, then probability)
    pattern =
      cond do
        is_integer(node[:repeat]) and node[:repeat] > 1 ->
          Pattern.fast(base_pattern, node[:repeat])

        is_integer(node[:replicate]) and node[:replicate] > 1 ->
          Pattern.fast(base_pattern, node[:replicate])

        is_number(node[:division]) ->
          Pattern.slow(base_pattern, node[:division])

        true ->
          base_pattern
      end

    # Apply probability if present
    apply_probability(pattern, node[:probability])
  end

  # Polymetric
  defp interpret_node(%{type: :polymetric, children: children} = node) do
    groups = extract_groups(children)

    # First build the base polymetric pattern
    base_pattern =
      case node do
        %{steps: steps} when is_integer(steps) ->
          interpret_polymetric_stepped(groups, steps)

        _ ->
          interpret_polymetric(groups)
      end

    # Apply speed modifiers
    pattern =
      cond do
        is_integer(node[:repeat]) and node[:repeat] > 1 ->
          Pattern.fast(base_pattern, node[:repeat])

        is_number(node[:division]) ->
          Pattern.slow(base_pattern, node[:division])

        true ->
          base_pattern
      end

    # Apply probability if present
    apply_probability(pattern, node[:probability])
  end

  # Random choice
  defp interpret_node(%{type: :random_choice} = node) do
    children = Map.get(node, :children, [])
    patterns = Enum.map(children, &interpret_atom/1)

    # Random choice selects one pattern per cycle (using cycle as seed)
    Pattern.from_cycles(fn cycle ->
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

    # Calculate total weight as integer (weights are always integers from parsing)
    total_weight =
      processed
      |> Enum.map(&get_weight_int/1)
      |> Enum.sum()

    if total_weight == 0 do
      Pattern.silence()
    else
      # Convert to patterns with their weight fractions as rational numbers
      weighted_patterns =
        processed
        |> Enum.map(fn item ->
          weight = get_weight_int(item)
          fraction = T.new(weight, total_weight)
          pattern = interpret_item(item)
          {pattern, fraction}
        end)

      # Build a custom query that handles weighted timing
      Pattern.new(fn span ->
        # Split by cycles and process each cycle
        TimeSpan.span_cycles(span)
        |> Enum.flat_map(fn cycle_span ->
          cycle = TimeSpan.cycle_of(cycle_span)
          cycle_time = T.new(cycle)

          {haps, _} =
            Enum.reduce(weighted_patterns, {[], T.zero()}, fn {pattern, fraction}, {acc, offset} ->
              # This slot occupies [cycle + offset, cycle + offset + fraction)
              slot_begin = T.add(cycle_time, offset)
              slot_end = T.add(slot_begin, fraction)
              slot_span = %{begin: slot_begin, end: slot_end}

              # Check if query span intersects this slot
              case TimeSpan.intersection(cycle_span, slot_span) do
                nil ->
                  {acc, T.add(offset, fraction)}

                intersected_span ->
                  # Map the intersected span into the child pattern's time
                  child_span = %{
                    begin: T.add(cycle_time, T.divide(T.sub(intersected_span.begin, slot_begin), fraction)),
                    end: T.add(cycle_time, T.divide(T.sub(intersected_span.end, slot_begin), fraction))
                  }

                  # Query the pattern and rescale its haps to this slot
                  # offset for scaling = slot_begin - cycle * fraction
                  scale_offset = T.sub(slot_begin, T.mult(cycle_time, fraction))

                  pattern_haps =
                    pattern
                    |> Pattern.query_span(child_span)
                    |> Enum.map(fn hap ->
                      # Transform whole and part timespans back to output time
                      new_whole = scale_and_offset_timespan(hap.whole, fraction, scale_offset)
                      new_part = scale_and_offset_timespan(hap.part, fraction, scale_offset)
                      %{hap | whole: new_whole, part: new_part}
                    end)
                    |> Enum.filter(fn hap ->
                      # Filter to only haps that intersect the query
                      TimeSpan.intersection(hap.part, cycle_span) != nil
                    end)

                  {acc ++ pattern_haps, T.add(offset, fraction)}
              end
            end)

          haps
        end)
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

  # Integer weight functions for rational arithmetic
  defp get_weight_int(%{type: :rest}), do: 1
  defp get_weight_int(%{type: :elongation}), do: 0

  # Handle replicate (!n) - each replica has weight 1, so total weight is n
  defp get_weight_int(%{replicate: n}) when is_integer(n) and n > 0, do: n

  # Explicit weight from @ operator
  defp get_weight_int(%{weight: w}) when is_number(w), do: trunc(w)

  defp get_weight_int(_), do: 1

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
    step = T.new(1, n)

    # Create a pattern that plays only on hits
    Pattern.from_cycles(fn cycle ->
      base_haps = Pattern.query(pattern, cycle)

      rhythm
      |> Enum.with_index()
      |> Enum.flat_map(fn {hit, i} ->
        if hit == 1 do
          time = T.new(i, n)
          time_end = T.add(time, step)

          Enum.map(base_haps, fn hap ->
            set_hap_timespan(hap, time, time_end)
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

  # Polymetric without explicit steps - align all groups to first group's length
  # In Strudel: {bd sd, hh hh hh} aligns second group to first group's 2-step cycle
  defp interpret_polymetric(groups) do
    # Get item counts for each group
    group_counts =
      Enum.map(groups, fn group ->
        items = extract_sequence_items(group)
        length(items)
      end)

    # First group's count is the reference
    first_count = List.first(group_counts) || 1

    # Interpret each group, scaling to align with first group's step count
    patterns =
      groups
      |> Enum.zip(group_counts)
      |> Enum.map(fn {group, count} ->
        base_pattern = interpret_group(group)

        if count == first_count or count == 0 do
          base_pattern
        else
          # Scale pattern so `count` items align with `first_count` steps
          # If count > first_count, slow down (stretch) the pattern
          # If count < first_count, speed up (compress) the pattern
          # Scale factor = count / first_count (e.g., 3/2 for 3 items -> 2 steps)
          scale_pattern_time(base_pattern, count, first_count)
        end
      end)

    Pattern.stack(patterns)
  end

  # Scale pattern time so original_steps items fit into target_steps
  # If original has 3 items and target has 2, stretch so only 2 items fit per cycle
  # This is equivalent to slow(3/2) - multiply times by 3/2
  defp scale_pattern_time(pattern, original_steps, target_steps) do
    # scale = original/target (e.g., 3/2 means pattern takes 1.5 cycles)
    scale = T.new(original_steps, target_steps)
    inverse_scale = T.new(target_steps, original_steps)

    Pattern.from_cycles(fn cycle ->
      # For output cycle N, we need to query the portion of the stretched pattern
      # that falls in [N, N+1)
      #
      # Stretched event at time T becomes T * scale
      # So events in output [N, N+1) come from inner [N/scale, (N+1)/scale)
      inner_start = T.mult(T.new(cycle), inverse_scale)
      inner_end = T.add(inner_start, inverse_scale)

      # Query the inner cycle(s) that overlap
      start_cycle = T.floor(inner_start) |> T.to_float() |> trunc()
      end_cycle = T.floor(inner_end) |> T.to_float() |> trunc()

      start_cycle..end_cycle
      |> Enum.flat_map(fn inner_cycle ->
        pattern
        |> Pattern.query(inner_cycle)
        |> Enum.filter(fn hap ->
          # Calculate absolute time of this event
          abs_begin = T.add(hap.part.begin, T.new(inner_cycle))
          abs_end = T.add(hap.part.end, T.new(inner_cycle))
          # Filter events that intersect with [inner_start, inner_end)
          T.lt?(abs_begin, inner_end) and T.gt?(abs_end, inner_start)
        end)
        |> Enum.map(fn hap ->
          # Scale times: multiply by scale factor, shift to output cycle
          abs_begin = T.add(hap.part.begin, T.new(inner_cycle))
          abs_end = T.add(hap.part.end, T.new(inner_cycle))

          # Stretched times
          new_begin = T.mult(abs_begin, scale)
          new_end = T.mult(abs_end, scale)

          # Shift to current output cycle
          new_begin = T.sub(new_begin, T.new(cycle))
          new_end = T.sub(new_end, T.new(cycle))

          # Clip to [0, 1)
          new_begin = T.max(new_begin, T.zero())
          new_end = T.min(new_end, T.one())

          set_hap_timespan(hap, new_begin, new_end)
        end)
      end)
    end)
  end

  defp interpret_polymetric_stepped(groups, steps) do
    step_duration = T.new(1, steps)

    patterns =
      Enum.map(groups, fn group ->
        items = extract_sequence_items(group)
        token_count = length(items)

        Pattern.from_cycles(fn cycle ->
          items
          |> Enum.with_index()
          |> Enum.flat_map(fn {item, idx} ->
            time_offset = T.new(idx, token_count)
            pattern = interpret_item(item)

            pattern
            |> Pattern.query(cycle)
            |> Enum.map(fn hap ->
              set_hap_timespan(hap, time_offset, T.add(time_offset, step_duration))
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

  # Scale and offset a timespan (works for both whole and part) using rational arithmetic
  defp scale_and_offset_timespan(nil, _fraction, _offset), do: nil

  defp scale_and_offset_timespan(%{begin: b, end: e}, fraction, offset) do
    # new_begin = offset + b * fraction
    # new_end = offset + e * fraction (simplified from offset + (b + (e-b)) * fraction)
    f = T.ensure(fraction)
    o = T.ensure(offset)
    %{begin: T.add(o, T.mult(b, f)), end: T.add(o, T.mult(e, f))}
  end

  # Set a hap's timespan to specific begin/end values (accepts rational or integer times)
  defp set_hap_timespan(%Hap{} = hap, begin_time, end_time) do
    timespan = TimeSpan.new(begin_time, end_time)
    %{hap | whole: timespan, part: timespan}
  end

  # ============================================================================
  # Probability Helper
  # ============================================================================

  # Apply probability modifier to a pattern using degrade_by
  # probability of 0.5 means 50% chance to play (keep 50% of events)
  defp apply_probability(pattern, nil), do: pattern

  defp apply_probability(pattern, prob) when is_number(prob) and prob >= 0 and prob <= 1 do
    # degrade_by removes events where random <= probability
    # So to keep `prob` fraction of events, we remove (1 - prob) fraction
    Pattern.degrade_by(pattern, 1.0 - prob)
  end

  defp apply_probability(pattern, _), do: pattern
end
