defmodule Markov do
  defstruct nodes: [:start, :end], links: %{start: %{end: 1}, end: %{}}

  require Logger

  @spec train(%Markov{}, String.t()) :: %Markov{}
  def train(%Markov{}=chain, text) when is_binary(text) do
    tokens = String.split(text)
    tokens = [:start | tokens ++ [:end]] # add start and end states

    # add new nodes to the chain
    new_tokens = tokens -- chain.nodes
    chain = %{chain | nodes: chain.nodes ++ new_tokens}
    # initialize links too
    links = Enum.reduce new_tokens, chain.links, fn token, acc ->
       Map.put(acc, token, %{})
    end
    chain = %{chain | links: links}

    # adjust link weights
    new_links = Enum.reduce ListUtil.pairs(tokens), chain.links, fn {first, second}, acc ->
      links_from_first = acc[first]
      if links_from_first[second] == nil do
        Map.put(acc, first, Map.put(links_from_first, second, 1))
      else
        Map.put(acc, first, Map.put(links_from_first, second, links_from_first[second] + 1))
      end
    end
    # forcefully break the start -> end link
    new_links = Map.put(new_links, :start, Map.delete(new_links.start, :end))
    chain = %{chain | links: new_links}

    chain
  end

  defp probabilistic_select(number, [{name, add} | tail], sum, acc \\ 0) do
    if (number >= acc) and (number <= acc + add) do
      name
    else
      probabilistic_select(number, tail, sum, acc + add)
    end
  end

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

  def generate_text(%Markov{}=chain, acc \\ "", state \\ :start) do
    state = next_state(chain, state)
    unless state == :end do
      acc = acc <> state <> " "
      generate_text(chain, acc, state)
    else
      str = String.trim(acc)
      if str == "" do
        ":x: **I haven't seen any messages yet**"
      else
        str
      end
    end
  end

  defp prettify_node(str) when is_binary(str) do str end
  defp prettify_node(atom) when is_atom(atom) do "<" <> Atom.to_string(atom) <> ">" end

  @spec print(%Markov{}) :: nil
  def print(%Markov{}=chain) do
    IO.puts("chain")
    for node <- chain.nodes do
      IO.puts("|-- node: #{prettify_node(node)}")
      links = chain.links[node]
      for {link, weight} <- links do
        IO.puts("|   |-- link: to #{prettify_node(link)} (rel. probability: #{weight})")
      end
    end
    nil
  end
end
