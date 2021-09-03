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
    chain = %{chain | links: new_links}

    chain
  end

  # debugging only
  def prettify_node(str) when is_binary(str) do
    str
  end
  def prettify_node(atom) when is_atom(atom) do
    "<" <> Atom.to_string(atom) <> ">"
  end

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
