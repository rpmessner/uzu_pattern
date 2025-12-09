defmodule UzuPattern.EuclideanTest do
  use ExUnit.Case, async: true

  alias UzuPattern.Euclidean

  describe "rhythm/2" do
    test "generates simple pattern (1,4)" do
      assert [1, 0, 0, 0] = Euclidean.rhythm(1, 4)
    end

    test "generates pattern with all hits (4,4)" do
      assert [1, 1, 1, 1] = Euclidean.rhythm(4, 4)
    end

    test "generates pattern with no hits (0,4)" do
      assert [0, 0, 0, 0] = Euclidean.rhythm(0, 4)
    end

    test "generates tresillo (3,8)" do
      pattern = Euclidean.rhythm(3, 8)
      assert length(pattern) == 8
      assert Enum.sum(pattern) == 3
      assert pattern == [1, 0, 0, 1, 0, 0, 1, 0]
    end

    test "generates cinquillo (5,8)" do
      pattern = Euclidean.rhythm(5, 8)
      assert length(pattern) == 8
      assert Enum.sum(pattern) == 5
      assert pattern == [1, 0, 1, 1, 0, 1, 1, 0]
    end

    test "generates bembe (7,12)" do
      pattern = Euclidean.rhythm(7, 12)
      assert length(pattern) == 12
      assert Enum.sum(pattern) == 7
    end

    test "generates pattern (2,5)" do
      pattern = Euclidean.rhythm(2, 5)
      assert length(pattern) == 5
      assert Enum.sum(pattern) == 2
      assert pattern == [1, 0, 1, 0, 0]
    end

    test "generates pattern (3,5)" do
      pattern = Euclidean.rhythm(3, 5)
      assert length(pattern) == 5
      assert Enum.sum(pattern) == 3
    end

    test "generates pattern (2,3)" do
      pattern = Euclidean.rhythm(2, 3)
      assert length(pattern) == 3
      assert Enum.sum(pattern) == 2
      assert pattern == [1, 1, 0]
    end

    test "generates pattern (5,12)" do
      pattern = Euclidean.rhythm(5, 12)
      assert length(pattern) == 12
      assert Enum.sum(pattern) == 5
    end

    test "distributes hits evenly" do
      pattern = Euclidean.rhythm(4, 8)
      assert pattern == [1, 0, 1, 0, 1, 0, 1, 0]
    end
  end

  describe "rhythm/3 with offset" do
    test "rotates pattern by offset" do
      original = Euclidean.rhythm(3, 8)
      rotated = Euclidean.rhythm(3, 8, 2)

      assert length(rotated) == 8
      assert Enum.sum(rotated) == 3

      {front, back} = Enum.split(original, 2)
      assert rotated == back ++ front
    end

    test "handles offset of 0" do
      assert Euclidean.rhythm(3, 8, 0) == Euclidean.rhythm(3, 8)
    end

    test "handles offset equal to length" do
      assert Euclidean.rhythm(3, 8, 8) == Euclidean.rhythm(3, 8)
    end

    test "handles offset greater than length" do
      assert Euclidean.rhythm(3, 8, 10) == Euclidean.rhythm(3, 8, 2)
    end

    test "offset 1 rotates by one position" do
      original = Euclidean.rhythm(3, 8)
      rotated = Euclidean.rhythm(3, 8, 1)

      [first | rest] = original
      assert rotated == rest ++ [first]
    end

    test "offset with all zeros pattern" do
      assert Euclidean.rhythm(0, 4, 2) == [0, 0, 0, 0]
    end

    test "offset with all ones pattern" do
      assert Euclidean.rhythm(4, 4, 2) == [1, 1, 1, 1]
    end
  end

  describe "known world music patterns" do
    test "Cuban tresillo (3,8)" do
      assert Euclidean.rhythm(3, 8) == [1, 0, 0, 1, 0, 0, 1, 0]
    end

    test "Cuban cinquillo (5,8)" do
      assert Euclidean.rhythm(5, 8) == [1, 0, 1, 1, 0, 1, 1, 0]
    end

    test "West African standard pattern (5,12)" do
      pattern = Euclidean.rhythm(5, 12)
      assert Enum.sum(pattern) == 5
      assert length(pattern) == 12
    end

    test "Khafif-e-ramal (2,5)" do
      assert Euclidean.rhythm(2, 5) == [1, 0, 1, 0, 0]
    end

    test "Agsag-Samai (2,7)" do
      pattern = Euclidean.rhythm(2, 7)
      assert Enum.sum(pattern) == 2
      assert length(pattern) == 7
    end
  end

  describe "edge cases" do
    test "single step pattern" do
      assert Euclidean.rhythm(1, 1) == [1]
    end

    test "single step no hit" do
      assert Euclidean.rhythm(0, 1) == [0]
    end

    test "large pattern" do
      pattern = Euclidean.rhythm(7, 16)
      assert length(pattern) == 16
      assert Enum.sum(pattern) == 7
    end

    test "empty pattern" do
      assert Euclidean.rhythm(0, 0) == []
    end
  end
end
