defmodule ListUtil do
  @spec ttuples(list()) :: list()
  def ttuples(list) do
    first_elements = list |> Enum.reverse |> tl() |> tl() |> Enum.reverse
    second_elements = list |> tl() |> Enum.reverse |> tl() |> Enum.reverse
    third_elements = list |> tl() |> tl()
    Enum.zip([first_elements, second_elements, third_elements])
  end
end
