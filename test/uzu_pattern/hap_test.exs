defmodule UzuPattern.HapTest do
  use ExUnit.Case, async: true

  alias UzuPattern.Hap
  alias UzuPattern.TimeSpan
  alias UzuPattern.Time

  describe "new/3" do
    test "creates discrete hap with whole and part equal" do
      ts = TimeSpan.new(0.0, 0.5)
      hap = Hap.new(ts, %{s: "bd"})

      assert hap.whole == ts
      assert hap.part == ts
      assert hap.value == %{s: "bd"}
      assert hap.context.locations == []
      assert hap.context.tags == []
    end

    test "accepts context" do
      ts = TimeSpan.new(0.0, 1.0)
      hap = Hap.new(ts, %{s: "sd"}, %{tags: ["drums"]})

      assert hap.context.tags == ["drums"]
    end
  end

  describe "continuous/3" do
    test "creates continuous hap with nil whole" do
      part = TimeSpan.new(0.0, 1.0)
      hap = Hap.continuous(part, %{freq: 440.0})

      assert hap.whole == nil
      assert hap.part == part
      assert hap.value == %{freq: 440.0}
    end
  end

  describe "discrete?/1 and continuous?/1" do
    test "discrete hap has whole" do
      hap = Hap.new(TimeSpan.new(0.0, 1.0), %{s: "bd"})
      assert Hap.discrete?(hap)
      refute Hap.continuous?(hap)
    end

    test "continuous hap has nil whole" do
      hap = Hap.continuous(TimeSpan.new(0.0, 1.0), %{freq: 440.0})
      refute Hap.discrete?(hap)
      assert Hap.continuous?(hap)
    end
  end

  describe "onset/1" do
    test "returns whole.begin for discrete haps" do
      hap = Hap.new(TimeSpan.new(0.5, 1.0), %{s: "bd"})
      assert Time.eq?(Hap.onset(hap), Time.new(1, 2))
    end

    test "returns nil for continuous haps" do
      hap = Hap.continuous(TimeSpan.new(0.5, 1.0), %{freq: 440.0})
      assert Hap.onset(hap) == nil
    end
  end

  describe "duration/1" do
    test "returns duration of whole for discrete haps" do
      hap = Hap.new(TimeSpan.new(0.0, 0.5), %{s: "bd"})
      assert Time.eq?(Hap.duration(hap), Time.new(1, 2))
    end

    test "returns nil for continuous haps" do
      hap = Hap.continuous(TimeSpan.new(0.0, 0.5), %{freq: 440.0})
      assert Hap.duration(hap) == nil
    end
  end

  describe "get/3 and put/3" do
    test "get retrieves value from value map" do
      hap = Hap.new(TimeSpan.new(0.0, 1.0), %{s: "bd", gain: 0.8})
      assert Hap.get(hap, :s) == "bd"
      assert Hap.get(hap, :gain) == 0.8
      assert Hap.get(hap, :missing) == nil
      assert Hap.get(hap, :missing, "default") == "default"
    end

    test "put adds value to value map" do
      hap = Hap.new(TimeSpan.new(0.0, 1.0), %{s: "bd"})
      hap = Hap.put(hap, :gain, 0.5)
      assert Hap.get(hap, :gain) == 0.5
    end
  end

  describe "merge/2" do
    test "merges values into value map" do
      hap = Hap.new(TimeSpan.new(0.0, 1.0), %{s: "bd"})
      hap = Hap.merge(hap, %{gain: 0.8, pan: 0.5})
      assert hap.value == %{s: "bd", gain: 0.8, pan: 0.5}
    end
  end

  describe "with_location/3" do
    test "adds location to context" do
      hap = Hap.new(TimeSpan.new(0.0, 1.0), %{s: "bd"})
      hap = Hap.with_location(hap, 0, 5)

      assert hap.context.locations == [%{start: 0, end: 5}]
    end

    test "accumulates multiple locations" do
      hap =
        Hap.new(TimeSpan.new(0.0, 1.0), %{s: "bd"})
        |> Hap.with_location(0, 5)
        |> Hap.with_location(10, 15)

      assert length(hap.context.locations) == 2
    end
  end

  describe "location/1 and locations/1" do
    test "location returns first as tuple" do
      hap =
        Hap.new(TimeSpan.new(0.0, 1.0), %{s: "bd"})
        |> Hap.with_location(0, 5)

      assert Hap.location(hap) == {0, 5}
    end

    test "location returns nil when no locations" do
      hap = Hap.new(TimeSpan.new(0.0, 1.0), %{s: "bd"})
      assert Hap.location(hap) == nil
    end

    test "locations returns all as tuples" do
      hap =
        Hap.new(TimeSpan.new(0.0, 1.0), %{s: "bd"})
        |> Hap.with_location(0, 5)
        |> Hap.with_location(10, 15)

      assert Hap.locations(hap) == [{0, 5}, {10, 15}]
    end
  end

  describe "sound/1 and sample/1" do
    test "sound returns value.s" do
      hap = Hap.new(TimeSpan.new(0.0, 1.0), %{s: "bd"})
      assert Hap.sound(hap) == "bd"
    end

    test "sound returns nil when no s" do
      hap = Hap.new(TimeSpan.new(0.0, 1.0), %{freq: 440})
      assert Hap.sound(hap) == nil
    end

    test "sample returns value.n" do
      hap = Hap.new(TimeSpan.new(0.0, 1.0), %{s: "bd", n: 2})
      assert Hap.sample(hap) == 2
    end

    test "sample returns nil when no n" do
      hap = Hap.new(TimeSpan.new(0.0, 1.0), %{s: "bd"})
      assert Hap.sample(hap) == nil
    end
  end

  describe "with_tag/2 and has_tag?/2" do
    test "adds tag to context" do
      hap = Hap.new(TimeSpan.new(0.0, 1.0), %{s: "bd"})
      hap = Hap.with_tag(hap, "drums")

      assert Hap.has_tag?(hap, "drums")
      refute Hap.has_tag?(hap, "melody")
    end

    test "accepts atom tags" do
      hap = Hap.new(TimeSpan.new(0.0, 1.0), %{s: "bd"})
      hap = Hap.with_tag(hap, :drums)

      assert Hap.has_tag?(hap, :drums)
      assert Hap.has_tag?(hap, "drums")
    end
  end

  describe "with_part/2" do
    test "updates part for continuous hap" do
      hap = Hap.continuous(TimeSpan.new(0.0, 1.0), %{freq: 440.0})
      new_part = TimeSpan.new(0.5, 0.8)
      hap = Hap.with_part(hap, new_part)

      assert hap.part == new_part
    end

    test "clips part to whole for discrete hap" do
      # Hap spans [0.2, 0.8)
      hap = Hap.new(TimeSpan.new(0.2, 0.8), %{s: "bd"})
      # Try to set part to [0.0, 0.5) - should clip to [0.2, 0.5)
      hap = Hap.with_part(hap, TimeSpan.new(0.0, 0.5))

      assert TimeSpan.eq?(hap.part, TimeSpan.new(0.2, 0.5))
      # Whole unchanged
      assert TimeSpan.eq?(hap.whole, TimeSpan.new(0.2, 0.8))
    end

    test "returns nil if new part doesn't intersect whole" do
      hap = Hap.new(TimeSpan.new(0.0, 0.5), %{s: "bd"})
      result = Hap.with_part(hap, TimeSpan.new(0.6, 1.0))

      assert result == nil
    end
  end

  describe "shift/2" do
    test "shifts both whole and part for discrete hap" do
      hap = Hap.new(TimeSpan.new(0.0, 0.5), %{s: "bd"})
      hap = Hap.shift(hap, 1.0)

      assert TimeSpan.eq?(hap.whole, TimeSpan.new(1.0, 1.5))
      assert TimeSpan.eq?(hap.part, TimeSpan.new(1.0, 1.5))
    end

    test "shifts only part for continuous hap" do
      hap = Hap.continuous(TimeSpan.new(0.0, 0.5), %{freq: 440.0})
      hap = Hap.shift(hap, 1.0)

      assert hap.whole == nil
      assert TimeSpan.eq?(hap.part, TimeSpan.new(1.0, 1.5))
    end
  end

  describe "scale/2" do
    test "scales both whole and part for discrete hap" do
      hap = Hap.new(TimeSpan.new(0.0, 1.0), %{s: "bd"})
      hap = Hap.scale(hap, 0.5)

      assert TimeSpan.eq?(hap.whole, TimeSpan.new(0.0, 0.5))
      assert TimeSpan.eq?(hap.part, TimeSpan.new(0.0, 0.5))
    end

    test "scales only part for continuous hap" do
      hap = Hap.continuous(TimeSpan.new(0.0, 1.0), %{freq: 440.0})
      hap = Hap.scale(hap, 0.5)

      assert hap.whole == nil
      assert TimeSpan.eq?(hap.part, TimeSpan.new(0.0, 0.5))
    end
  end

  describe "whole vs part semantics" do
    test "hap represents boundary-clipped event" do
      # Event naturally spans [4/5, 6/5) = [0.8, 1.2)
      # Query is [0, 1), so part is clipped to [4/5, 1)
      hap = %Hap{
        whole: TimeSpan.new({4, 5}, {6, 5}),
        part: TimeSpan.new({4, 5}, 1),
        value: %{s: "bd"},
        context: %{locations: [], tags: []}
      }

      # Onset is at whole.begin, not part.begin
      assert Time.eq?(Hap.onset(hap), Time.new(4, 5))

      # Duration is from whole, not part (6/5 - 4/5 = 2/5)
      assert Time.eq?(Hap.duration(hap), Time.new(2, 5))

      # The scheduler should trigger at onset (4/5)
      # even though our query only covered [4/5, 1)
    end
  end
end
