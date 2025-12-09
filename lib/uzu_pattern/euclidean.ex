defmodule UzuPattern.Euclidean do
  @moduledoc """
  Bjorklund's algorithm for generating Euclidean rhythms.

  Euclidean rhythms distribute k pulses over n steps as evenly as possible,
  producing patterns found in traditional music from around the world.

  ## Examples

      iex> UzuPattern.Euclidean.rhythm(3, 8)
      [1, 0, 0, 1, 0, 0, 1, 0]

      iex> UzuPattern.Euclidean.rhythm(5, 8)
      [1, 0, 1, 1, 0, 1, 1, 0]

      # With rotation offset
      iex> UzuPattern.Euclidean.rhythm(3, 8, 2)
      [0, 1, 0, 0, 1, 0, 1, 0]
  """

  @doc """
  Generate a Euclidean rhythm pattern.

  ## Parameters
    - `k` - Number of pulses (hits)
    - `n` - Number of steps (total length)
    - `offset` - Rotation offset (default 0)

  ## Returns
    List of 1s (hits) and 0s (rests)
  """
  def rhythm(k, n, offset \\ 0) do
    k
    |> bjorklund(n)
    |> rotate_list(offset)
  end

  # Bjorklund's algorithm for generating euclidean rhythms
  # Distributes k pulses over n steps as evenly as possible
  # Returns a list of 1s (hits) and 0s (rests)
  defp bjorklund(k, n) when k == n do
    List.duplicate(1, n)
  end

  defp bjorklund(k, n) when k == 0 do
    List.duplicate(0, n)
  end

  defp bjorklund(k, n) do
    # Initialize: k groups of [1] and (n-k) groups of [0]
    ones = List.duplicate([1], k)
    zeros = List.duplicate([0], n - k)
    bjorklund_iterate(ones, zeros)
  end

  # Recursive step of Bjorklund's algorithm
  defp bjorklund_iterate(left, []) do
    List.flatten(left)
  end

  defp bjorklund_iterate(left, right) when length(right) == 1 do
    List.flatten(left ++ right)
  end

  defp bjorklund_iterate(left, right) do
    # Distribute right elements among left elements
    min_len = min(length(left), length(right))
    {left_take, left_rest} = Enum.split(left, min_len)
    {right_take, right_rest} = Enum.split(right, min_len)

    # Combine pairs
    combined = Enum.zip_with(left_take, right_take, fn l, r -> l ++ r end)

    # Continue with combined as left, and remainder as right
    bjorklund_iterate(combined, left_rest ++ right_rest)
  end

  # Rotate a list by offset positions to the left
  defp rotate_list(list, 0), do: list
  defp rotate_list([], _offset), do: []

  defp rotate_list(list, offset) do
    len = length(list)
    normalized_offset = rem(offset, len)
    {front, back} = Enum.split(list, normalized_offset)
    back ++ front
  end
end
