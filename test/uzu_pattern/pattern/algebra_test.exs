defmodule UzuPattern.Pattern.AlgebraTest do
  use ExUnit.Case, async: true

  alias UzuPattern.Pattern
  alias UzuPattern.Pattern.Algebra
  alias UzuPattern.Time
  alias UzuPattern.TimeSpan

  # Sort haps by part begin time using exact rational comparison
  defp sort_by_time(haps) do
    Enum.sort(haps, fn a, b -> Time.lt?(a.part.begin, b.part.begin) end)
  end

  describe "fmap/2" do
    test "transforms hap values" do
      p = Pattern.pure("bd")
      p = Algebra.fmap(p, fn value -> Map.put(value, :gain, 0.5) end)

      [hap] = Pattern.query(p, 0)
      assert hap.value.gain == 0.5
      assert hap.value.s == "bd"
    end

    test "replaces entire value map" do
      p = Pattern.pure("60")
      p = Algebra.fmap(p, fn %{s: s} -> %{note: String.to_integer(s)} end)

      [hap] = Pattern.query(p, 0)
      assert hap.value == %{note: 60}
    end

    test "works with fastcat" do
      p = Pattern.fastcat([Pattern.pure("a"), Pattern.pure("b")])
      p = Algebra.fmap(p, fn %{s: s} -> %{s: String.upcase(s)} end)

      haps = Pattern.query(p, 0)
      sounds = Enum.map(haps, & &1.value.s)
      assert sounds == ["A", "B"]
    end

    test "preserves timing" do
      p = Pattern.fastcat([Pattern.pure("a"), Pattern.pure("b")])
      p = Algebra.fmap(p, fn v -> Map.put(v, :x, 1) end)

      [h1, h2] = sort_by_time(Pattern.query(p, 0))
      assert Time.eq?(h1.part.begin, Time.zero())
      assert Time.eq?(h2.part.begin, Time.half())
    end

    test "is accessible via Pattern.fmap" do
      p = Pattern.pure("bd")
      p = Pattern.fmap(p, fn v -> Map.put(v, :test, true) end)

      [hap] = Pattern.query(p, 0)
      assert hap.value.test == true
    end
  end

  describe "app_both/2" do
    test "applies function pattern to value pattern" do
      # Pattern of functions
      funcs =
        Pattern.pure("_")
        |> Algebra.fmap(fn _ -> fn v -> Map.put(v, :modified, true) end end)

      # Pattern of values
      vals = Pattern.pure("bd")

      result = Algebra.app_both(funcs, vals)
      [hap] = Pattern.query(result, 0)

      assert hap.value.s == "bd"
      assert hap.value.modified == true
    end

    test "intersects wholes when both have wholes" do
      # Two patterns that fully overlap
      funcs =
        Pattern.pure("_")
        |> Algebra.fmap(fn _ -> fn v -> v end end)

      vals = Pattern.pure("bd")

      result = Algebra.app_both(funcs, vals)
      [hap] = Pattern.query(result, 0)

      # Both wholes are [0, 1), intersection is [0, 1)
      assert Time.eq?(hap.whole.begin, Time.zero())
      assert Time.eq?(hap.whole.end, Time.one())
    end

    test "only produces output when parts intersect" do
      # Two patterns that don't overlap in time
      funcs =
        Pattern.fastcat([
          Pattern.pure("_") |> Algebra.fmap(fn _ -> fn v -> v end end),
          Pattern.silence()
        ])

      vals =
        Pattern.fastcat([
          Pattern.silence(),
          Pattern.pure("bd")
        ])

      result = Algebra.app_both(funcs, vals)
      haps = Pattern.query(result, 0)

      # No intersection - funcs at [0, 0.5), vals at [0.5, 1)
      assert haps == []
    end

    test "produces output when parts do intersect" do
      # Both patterns have events in the same time slot
      funcs =
        Pattern.pure("_")
        |> Algebra.fmap(fn _ -> fn v -> Map.put(v, :f, 1) end end)

      vals = Pattern.pure("bd")

      result = Algebra.app_both(funcs, vals)
      [hap] = Pattern.query(result, 0)

      assert hap.value.s == "bd"
      assert hap.value.f == 1
    end

    test "combines multiple functions with multiple values" do
      # Two functions
      funcs =
        Pattern.fastcat([
          Pattern.pure("_") |> Algebra.fmap(fn _ -> fn v -> Map.put(v, :x, 1) end end),
          Pattern.pure("_") |> Algebra.fmap(fn _ -> fn v -> Map.put(v, :x, 2) end end)
        ])

      # One value spanning whole cycle
      vals = Pattern.pure("bd")

      result = Algebra.app_both(funcs, vals)
      haps = Pattern.query(result, 0)

      # Should get 2 haps - each function applied to the value
      assert length(haps) == 2
      xs = Enum.map(haps, & &1.value.x) |> Enum.sort()
      assert xs == [1, 2]
    end
  end

  describe "app_left/2" do
    test "structure comes from function pattern" do
      # Two-event function pattern
      funcs =
        Pattern.fastcat([
          Pattern.pure("_") |> Algebra.fmap(fn _ -> fn v -> Map.put(v, :slot, 0) end end),
          Pattern.pure("_") |> Algebra.fmap(fn _ -> fn v -> Map.put(v, :slot, 1) end end)
        ])

      # Single-event value pattern
      vals = Pattern.pure("bd")

      result = Algebra.app_left(funcs, vals)
      haps = Pattern.query(result, 0)

      # Should get 2 haps with timing from funcs
      assert length(haps) == 2

      [h1, h2] = sort_by_time(haps)
      assert TimeSpan.eq?(h1.part, TimeSpan.new(0, {1, 2}))
      assert TimeSpan.eq?(h2.part, TimeSpan.new({1, 2}, 1))
    end

    test "wholes come from function pattern" do
      funcs =
        Pattern.fastcat([
          Pattern.pure("_") |> Algebra.fmap(fn _ -> fn v -> v end end),
          Pattern.pure("_") |> Algebra.fmap(fn _ -> fn v -> v end end)
        ])

      vals = Pattern.pure("bd")

      result = Algebra.app_left(funcs, vals)
      haps = Pattern.query(result, 0)

      [h1, h2] = sort_by_time(haps)
      # Wholes should be [0, 0.5) and [0.5, 1)
      assert TimeSpan.eq?(h1.whole, TimeSpan.new(0, {1, 2}))
      assert TimeSpan.eq?(h2.whole, TimeSpan.new({1, 2}, 1))
    end
  end

  describe "app_right/2" do
    test "structure comes from value pattern" do
      # Single-event function pattern
      funcs =
        Pattern.pure("_")
        |> Algebra.fmap(fn _ -> fn v -> Map.put(v, :modified, true) end end)

      # Two-event value pattern
      vals = Pattern.fastcat([Pattern.pure("a"), Pattern.pure("b")])

      result = Algebra.app_right(funcs, vals)
      haps = Pattern.query(result, 0)

      # Should get 2 haps with timing from vals
      assert length(haps) == 2

      [h1, h2] = sort_by_time(haps)
      assert h1.value.s == "a"
      assert h2.value.s == "b"
      assert Time.eq?(h1.part.begin, Time.zero())
      assert Time.eq?(h2.part.begin, Time.half())
    end

    test "wholes come from value pattern" do
      funcs =
        Pattern.pure("_")
        |> Algebra.fmap(fn _ -> fn v -> v end end)

      vals = Pattern.fastcat([Pattern.pure("a"), Pattern.pure("b")])

      result = Algebra.app_right(funcs, vals)
      haps = Pattern.query(result, 0)

      [h1, h2] = sort_by_time(haps)
      # Wholes should be [0, 0.5) and [0.5, 1)
      assert TimeSpan.eq?(h1.whole, TimeSpan.new(0, {1, 2}))
      assert TimeSpan.eq?(h2.whole, TimeSpan.new({1, 2}, 1))
    end
  end

  describe "multi-cycle queries" do
    test "fmap works across cycles" do
      p = Pattern.slowcat([Pattern.pure("a"), Pattern.pure("b")])
      p = Algebra.fmap(p, fn %{s: s} -> %{s: String.upcase(s)} end)

      span = TimeSpan.new(0, 2)
      haps = Pattern.query_span(p, span)

      assert length(haps) == 2
      sounds = Enum.map(haps, & &1.value.s) |> Enum.sort()
      assert sounds == ["A", "B"]
    end

    test "app_left works across cycles" do
      funcs =
        Pattern.slowcat([
          Pattern.pure("_") |> Algebra.fmap(fn _ -> fn v -> Map.put(v, :cycle, 0) end end),
          Pattern.pure("_") |> Algebra.fmap(fn _ -> fn v -> Map.put(v, :cycle, 1) end end)
        ])

      vals = Pattern.pure("bd")

      result = Algebra.app_left(funcs, vals)
      span = TimeSpan.new(0, 2)
      haps = Pattern.query_span(result, span)

      assert length(haps) == 2
      cycles = Enum.map(haps, & &1.value.cycle) |> Enum.sort()
      assert cycles == [0, 1]
    end
  end

  describe "context preservation" do
    test "fmap preserves context" do
      p = Pattern.pure("bd", start: 0, end: 2)
      p = Algebra.fmap(p, fn v -> Map.put(v, :x, 1) end)

      [hap] = Pattern.query(p, 0)
      assert hap.context.locations == [%{start: 0, end: 2}]
    end

    test "app_both combines contexts" do
      funcs =
        Pattern.pure("_", start: 0, end: 1)
        |> Algebra.fmap(fn _ -> fn v -> v end end)

      vals = Pattern.pure("bd", start: 5, end: 7)

      result = Algebra.app_both(funcs, vals)
      [hap] = Pattern.query(result, 0)

      # Should have both locations
      assert length(hap.context.locations) == 2
    end
  end

  # ============================================================================
  # Monadic Operations
  # ============================================================================

  describe "bind/2" do
    test "flattens pattern of patterns" do
      # Outer pattern with value that will become inner pattern
      outer = Pattern.pure("bd")

      # Function that returns an inner pattern for each value
      result =
        Algebra.bind(outer, fn %{s: _sound} ->
          Pattern.fastcat([Pattern.pure("a"), Pattern.pure("b")])
        end)

      haps = Pattern.query(result, 0)
      assert length(haps) == 2
      sounds = Enum.map(haps, & &1.value.s) |> Enum.sort()
      assert sounds == ["a", "b"]
    end

    test "intersects wholes from outer and inner" do
      outer = Pattern.pure("x")

      result =
        Algebra.bind(outer, fn _ ->
          # Inner pattern with whole [0, 1)
          Pattern.pure("y")
        end)

      [hap] = Pattern.query(result, 0)
      # Both outer and inner have whole [0, 1), intersection is [0, 1)
      assert TimeSpan.eq?(hap.whole, TimeSpan.new(0, 1))
    end

    test "works with varying inner patterns based on outer value" do
      # slowcat alternates which value we get
      outer = Pattern.slowcat([Pattern.pure("1"), Pattern.pure("2")])

      result =
        Algebra.bind(outer, fn %{s: s} ->
          n = String.to_integer(s)
          # Create n events
          patterns = for _ <- 1..n, do: Pattern.pure("hit")
          Pattern.fastcat(patterns)
        end)

      # Cycle 0: outer is "1", so inner is 1 event
      haps0 = Pattern.query(result, 0)
      assert length(haps0) == 1

      # Cycle 1: outer is "2", so inner is 2 events
      haps1 = Pattern.query(result, 1)
      assert length(haps1) == 2
    end
  end

  describe "inner_bind/2 and inner_join/1" do
    test "inner_bind keeps wholes from inner pattern" do
      outer = Pattern.pure("x")

      result =
        Algebra.inner_bind(outer, fn _ ->
          # Inner pattern with fastcat has wholes at [0, 0.5) and [0.5, 1)
          Pattern.fastcat([Pattern.pure("a"), Pattern.pure("b")])
        end)

      haps = Pattern.query(result, 0)
      [h1, h2] = sort_by_time(haps)

      # Wholes should come from inner pattern
      assert TimeSpan.eq?(h1.whole, TimeSpan.new(0, {1, 2}))
      assert TimeSpan.eq?(h2.whole, TimeSpan.new({1, 2}, 1))
    end

    test "inner_join flattens pattern of patterns keeping inner wholes" do
      # Create a pattern where values are patterns themselves
      inner_pat = Pattern.fastcat([Pattern.pure("a"), Pattern.pure("b")])
      outer = Pattern.pure("_") |> Algebra.fmap(fn _ -> inner_pat end)

      result = Algebra.inner_join(outer)
      haps = Pattern.query(result, 0)

      assert length(haps) == 2
      sounds = Enum.map(haps, & &1.value.s) |> Enum.sort()
      assert sounds == ["a", "b"]
    end
  end

  describe "outer_bind/2 and outer_join/1" do
    test "outer_bind keeps wholes from outer pattern" do
      # Outer pattern with 2 events
      outer = Pattern.fastcat([Pattern.pure("x"), Pattern.pure("y")])

      result =
        Algebra.outer_bind(outer, fn _ ->
          # Inner pattern - its wholes should be ignored
          Pattern.pure("inner")
        end)

      haps = Pattern.query(result, 0)
      [h1, h2] = sort_by_time(haps)

      # Wholes should come from outer pattern
      assert TimeSpan.eq?(h1.whole, TimeSpan.new(0, {1, 2}))
      assert TimeSpan.eq?(h2.whole, TimeSpan.new({1, 2}, 1))
    end

    test "outer_join flattens pattern of patterns keeping outer wholes" do
      inner_pat = Pattern.pure("inner")
      # Outer has 2 events
      outer =
        Pattern.fastcat([
          Pattern.pure("_") |> Algebra.fmap(fn _ -> inner_pat end),
          Pattern.pure("_") |> Algebra.fmap(fn _ -> inner_pat end)
        ])

      result = Algebra.outer_join(outer)
      haps = Pattern.query(result, 0)

      assert length(haps) == 2
      # All should have value from inner
      assert Enum.all?(haps, fn h -> h.value.s == "inner" end)
    end
  end

  describe "squeeze_join/1" do
    test "squeezes inner pattern into outer hap duration" do
      # Outer pattern with one event spanning [0, 1)
      # Inner pattern (as value) with 4 events
      inner =
        Pattern.fastcat([
          Pattern.pure("a"),
          Pattern.pure("b"),
          Pattern.pure("c"),
          Pattern.pure("d")
        ])

      outer = Pattern.pure("_") |> Algebra.fmap(fn _ -> inner end)

      result = Algebra.squeeze_join(outer)
      haps = Pattern.query(result, 0)

      # Should get 4 events squeezed into [0, 1)
      assert length(haps) == 4
      sounds = Enum.map(haps, & &1.value.s)
      assert sounds == ["a", "b", "c", "d"]

      # Check timing - each should be 1/4 duration
      sorted = sort_by_time(haps)
      assert Time.eq?(Enum.at(sorted, 0).part.begin, Time.zero())
      assert Time.eq?(Enum.at(sorted, 1).part.begin, Time.new(1, 4))
      assert Time.eq?(Enum.at(sorted, 2).part.begin, Time.half())
      assert Time.eq?(Enum.at(sorted, 3).part.begin, Time.new(3, 4))
    end

    test "squeeze_join with alternating outer gives different inner counts" do
      # This is the key test for pattern arguments like fast("<2 4>", pat)

      # Slowcat alternates: cycle 0 gets 2-event inner, cycle 1 gets 4-event inner
      inner2 = Pattern.fastcat([Pattern.pure("a"), Pattern.pure("b")])
      inner4 = Pattern.fastcat([Pattern.pure("w"), Pattern.pure("x"), Pattern.pure("y"), Pattern.pure("z")])

      outer =
        Pattern.slowcat([
          Pattern.pure("_") |> Algebra.fmap(fn _ -> inner2 end),
          Pattern.pure("_") |> Algebra.fmap(fn _ -> inner4 end)
        ])

      result = Algebra.squeeze_join(outer)

      # Cycle 0: should have 2 events
      haps0 = Pattern.query(result, 0)
      assert length(haps0) == 2
      sounds0 = Enum.map(haps0, & &1.value.s) |> Enum.sort()
      assert sounds0 == ["a", "b"]

      # Cycle 1: should have 4 events
      haps1 = Pattern.query(result, 1)
      assert length(haps1) == 4
      sounds1 = Enum.map(haps1, & &1.value.s) |> Enum.sort()
      assert sounds1 == ["w", "x", "y", "z"]
    end

    test "squeeze_join with partial outer haps" do
      # Outer pattern with 2 events, each gets its own inner pattern squeezed
      inner = Pattern.fastcat([Pattern.pure("a"), Pattern.pure("b")])

      outer =
        Pattern.fastcat([
          Pattern.pure("_") |> Algebra.fmap(fn _ -> inner end),
          Pattern.pure("_") |> Algebra.fmap(fn _ -> inner end)
        ])

      result = Algebra.squeeze_join(outer)
      haps = Pattern.query(result, 0)

      # Each outer hap (0.5 duration) should have 2 inner events squeezed into it
      # Total: 4 events
      assert length(haps) == 4

      # Check timing - first pair in [0, 0.5), second pair in [0.5, 1)
      sorted = sort_by_time(haps)
      assert Time.eq?(Enum.at(sorted, 0).part.begin, Time.zero())
      assert Time.eq?(Enum.at(sorted, 1).part.begin, Time.new(1, 4))
      assert Time.eq?(Enum.at(sorted, 2).part.begin, Time.half())
      assert Time.eq?(Enum.at(sorted, 3).part.begin, Time.new(3, 4))
    end
  end

  describe "squeeze_bind/2" do
    test "is equivalent to fmap then squeeze_join" do
      base = Pattern.pure("bd")

      # Using squeeze_bind
      result1 =
        Algebra.squeeze_bind(base, fn _ ->
          Pattern.fastcat([Pattern.pure("a"), Pattern.pure("b")])
        end)

      # Using fmap + squeeze_join
      result2 =
        base
        |> Algebra.fmap(fn _ -> Pattern.fastcat([Pattern.pure("a"), Pattern.pure("b")]) end)
        |> Algebra.squeeze_join()

      haps1 = Pattern.query(result1, 0)
      haps2 = Pattern.query(result2, 0)

      assert length(haps1) == length(haps2)
      sounds1 = Enum.map(haps1, & &1.value.s) |> Enum.sort()
      sounds2 = Enum.map(haps2, & &1.value.s) |> Enum.sort()
      assert sounds1 == sounds2
    end
  end

  describe "focus_span/2" do
    test "focuses pattern so cycle fits within span" do
      # Pattern with 4 events per cycle
      p =
        Pattern.fastcat([
          Pattern.pure("a"),
          Pattern.pure("b"),
          Pattern.pure("c"),
          Pattern.pure("d")
        ])

      # Focus it so one cycle fits into [0, 0.5)
      focused = Algebra.focus_span(p, TimeSpan.new(0, {1, 2}))

      # Query the focused span - this should return all 4 events scaled to fit [0, 0.5)
      haps = Pattern.query_span(focused, TimeSpan.new(0, {1, 2}))

      # Should get all 4 events within [0, 0.5)
      assert length(haps) == 4

      sorted = sort_by_time(haps)
      # Each event should be 1/8 duration (1/2 / 4)
      assert Time.eq?(Enum.at(sorted, 0).part.begin, Time.zero())
      assert Time.eq?(Enum.at(sorted, 1).part.begin, Time.new(1, 8))
      assert Time.eq?(Enum.at(sorted, 2).part.begin, Time.new(1, 4))
      assert Time.eq?(Enum.at(sorted, 3).part.begin, Time.new(3, 8))
    end

    test "focus_span at different offset" do
      p = Pattern.fastcat([Pattern.pure("a"), Pattern.pure("b")])

      # Focus into [0.5, 1.0)
      focused = Algebra.focus_span(p, TimeSpan.new({1, 2}, 1))

      # Query the focused span
      haps = Pattern.query_span(focused, TimeSpan.new({1, 2}, 1))
      assert length(haps) == 2

      sorted = sort_by_time(haps)
      assert Time.eq?(Enum.at(sorted, 0).part.begin, Time.half())
      assert Time.eq?(Enum.at(sorted, 1).part.begin, Time.new(3, 4))
    end

    test "querying full cycle after focus gives scaled events" do
      # Pattern with 2 events per cycle
      p = Pattern.fastcat([Pattern.pure("a"), Pattern.pure("b")])

      # Focus it so one cycle fits into [0, 0.5)
      focused = Algebra.focus_span(p, TimeSpan.new(0, {1, 2}))

      # Query full cycle [0, 1) - this queries 2 cycles of original pattern
      haps = Pattern.query(focused, 0)

      # Should get 4 events: 2 from [0, 0.5) and 2 from [0.5, 1)
      assert length(haps) == 4
    end
  end

  describe "Pattern module delegations" do
    test "bind is accessible via Pattern.bind" do
      outer = Pattern.pure("x")
      result = Pattern.bind(outer, fn _ -> Pattern.pure("y") end)
      [hap] = Pattern.query(result, 0)
      assert hap.value.s == "y"
    end

    test "inner_join is accessible via Pattern.inner_join" do
      inner = Pattern.pure("inner")
      outer = Pattern.pure("_") |> Algebra.fmap(fn _ -> inner end)
      result = Pattern.inner_join(outer)
      [hap] = Pattern.query(result, 0)
      assert hap.value.s == "inner"
    end

    test "squeeze_join is accessible via Pattern.squeeze_join" do
      inner = Pattern.fastcat([Pattern.pure("a"), Pattern.pure("b")])
      outer = Pattern.pure("_") |> Algebra.fmap(fn _ -> inner end)
      result = Pattern.squeeze_join(outer)
      haps = Pattern.query(result, 0)
      assert length(haps) == 2
    end
  end
end
