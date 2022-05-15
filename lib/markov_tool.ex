defmodule MarkovTool do
  @moduledoc """
  Functions for manipulating Markov models not provided by the library
  """

  def token_stats(%Markov{} = model) do
    model.links |> Enum.reduce(%{}, fn {_, probabilities}, acc ->
      probabilities |> Enum.reduce(acc, fn {tok, prob}, acc2 ->
        acc2 |> Map.put(tok, Map.get(acc2, tok, 0) + prob)
      end)
    end)
  end
end
