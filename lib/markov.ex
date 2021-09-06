defmodule Markov do
  @moduledoc """
  Markov-chain-based trained text generator implementation.
  Next token prediction uses two previous tokens.
  """

  defstruct links: %{[:start, :start] => %{end: 1}, end: %{}}

  require Logger

  @doc """
  Trains `chain` using `text`.

  Returns the modified chain.

  ## Example
      chain = %Markov{}
          |> Markov.train("hello, world!")
          |> Markov.train("example string number two")
          |> Markov.train("hello, Elixir!")
          |> Markov.train("fourth string")
  """
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

  @doc """
  Predicts the next state of a `chain` assuming `current` state.

  Note: current state conists of two tokens.

  Returns the next predicted state.

  ## Example
      iex> %Markov{} |> Markov.train("1 2 3 4 5") |> Markov.next(["2", "3"])
      "4"

      iex> %Markov{} |> Markov.train("1 2") |> Markov.next([:start, :start])
      "1"
  """
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

  @doc """
  Generates a string of text using the `chain`

  Optionally prepends `acc` to it and assumes the previous
  two states were `[state1, state2]=state`.

  Returns the generated text.

  ## Example
      iex> %Markov{} |> Markov.train("hello, world!") |> Markov.generate_text()
      "hello, world!"

      iex> %Markov{} |> Markov.train("hello, world!")
      ...> |> Markov.generate_text("", [:start, "hello,"])
      "world!"
  """
  @spec generate_text(%Markov{}, acc :: String.t(), any()) :: String.t()
  def generate_text(%Markov{}=chain, acc \\ "", state \\ [:start, :start]) do
    # iterate through states until :end
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

  @spec probabilistic_select(integer(), list({any(), integer()}), integer(), integer()) :: any()
  defp probabilistic_select(number, [{name, add} | tail]=_choices, sum, acc \\ 0) do
    if (number >= acc) and (number <= acc + add) do
      name
    else
      probabilistic_select(number, tail, sum, acc + add)
    end
  end
end
