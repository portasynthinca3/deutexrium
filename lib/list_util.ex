defmodule ListUtil do
  @spec pairs(list()) :: list()
  def pairs(list) do
    first_elements = Enum.reverse(list)
        |> tl
        |> Enum.reverse
    second_elements = tl(list)
    Enum.zip(first_elements, second_elements)
  end
end
