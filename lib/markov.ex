defmodule Markov do
  defstruct links: %{[:start, :start] => %{end: 1}, end: %{}}

  require Logger

  @spec train(%Markov{}, String.t()) :: %Markov{}
  def train(%Markov{}=chain, text) when is_binary(text) do
    tokens = String.split(text)
    tokens = [:start, :start] ++ tokens ++ [:end] # add start and end tokens

    # adjust link weights
    new_links = Enum.reduce ListUtil.ttuples(tokens), chain.links, fn {first, second, third}, acc ->
      from = [first, second]
      to = third
      links_from = acc[from]
      links_from = if links_from == nil do %{} else links_from end
      if links_from[to] == nil do
        Map.put(acc, from, Map.put(links_from, to, 1))
      else
        Map.put(acc, from, Map.put(links_from, to, links_from[to] + 1))
      end
    end
    # forcefully break the start -> end link
    new_links = Map.put(new_links, [:start, :start], Map.delete(new_links[[:start, :start]], :end))
    chain = %{chain | links: new_links}

    chain
  end

  @spec next_state(%Markov{}, any()) :: any()
  def next_state(%Markov{}=chain, current) do
    # get links from current state
    # (enforce constant order by converting to proplist)
    links = chain.links[current] |> Enum.into([])
    # do the magic
    sum = Enum.unzip(links)
        |> Tuple.to_list
        |> List.last
        |> Enum.sum
    :rand.uniform(sum + 1) - 1 |> probabilistic_select(links, sum)
  end

  @spec generate_text(%Markov{}, acc :: String.t(), any()) :: String.t()
  def generate_text(%Markov{}=chain, acc \\ "", state \\ [:start, :start]) do
    new_state = next_state(chain, state)
    unless new_state == :end do
      acc = acc <> new_state <> " "
      generate_text(chain, acc, [Enum.at(state, 1), new_state])
    else
      str = String.trim(acc)
      if str == "" do
        ":x: **I haven't seen any messages yet**"
      else
        str
      end
    end
  end

  defp probabilistic_select(number, [{name, add} | tail], sum, acc \\ 0) do
    if (number >= acc) and (number <= acc + add) do
      name
    else
      probabilistic_select(number, tail, sum, acc + add)
    end
  end
end
