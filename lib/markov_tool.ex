defmodule MarkovTool do
  def token_stats(%Markov{}=model) do
    model.links |> Enum.reduce(%{}, fn {_, possibilities}, acc ->
      possibilities |> Enum.reduce(acc, fn {tok, prob}, acc2 ->
        acc2 |> Map.put(tok, Map.get(acc2, tok, 0) + prob)
      end)
    end)
  end
end
