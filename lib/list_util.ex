defmodule ListUtil do
  @moduledoc """
  Collection handling utilities
  """

  @spec ttuples(list()) :: list()
  def ttuples(list) do
    first_elements = list |> Enum.reverse |> tl() |> tl() |> Enum.reverse
    second_elements = list |> tl() |> Enum.reverse |> tl() |> Enum.reverse
    third_elements = list |> tl() |> tl()
    Enum.zip([first_elements, second_elements, third_elements])
  end

  def sum_maps(one, two) do
    one = one |> Enum.into([])
    two = two |> Enum.into([])
    Enum.zip([one, two]) |> Enum.reduce([], fn {{k, v1}, {_, v2}}, acc ->
      [{k, v1 + v2} | acc]
    end) |> Enum.into(%{})
  end
end
