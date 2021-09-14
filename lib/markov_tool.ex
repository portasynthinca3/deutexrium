defmodule MarkovTool do
  def token_stats(%Markov{}=model) do
    model.links |> Enum.reduce(%{}, fn {_, possibilities}, acc ->
      possibilities |> Enum.reduce(acc, fn {tok, prob}, acc2 ->
        acc2 |> Map.put(tok, Map.get(acc2, tok, 0) + prob)
      end)
    end)
  end

  def forget_token(%Markov{}=model, token) do
    # removelinks that point to the token
    %{model | links: model.links |> Enum.map(fn
      {[_, _]=k, v} ->
        {k, Enum.filter(v, fn {k, _} -> k != token end) |> Enum.into(%{})}
      {k, v} -> {k, v}
    end) |> Enum.into(%{})
    # terminate states that point nowhere
    |> Enum.map(fn
      {k, %{}=map} when map_size(map) == 0 ->
        {k, %{end: 1}}
      {k, v} -> {k, v}
    end) |> Enum.into(%{})}
  end
end
