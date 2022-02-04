defmodule Sentiment do
  @moduledoc """
  Veritaserum wrapper for fitting sentiments into 5 major categories
  """

  @type sentiment() :: :nosentiment | :strongly_negative | :negative | :neutral | :positive | :strongly_positive
  defguard is_sentiment(atom) when atom == :nosentiment
    or atom == :strongly_negative
    or atom == :negative
    or atom == :neutral
    or atom == :positive
    or atom == :strongly_positive

  @spec detect(String.t()) :: sentiment()
  def detect(text) do
    try do
      case text |> Veritaserum.analyze do
        i when i <= -3 -> :strongly_negative
        i when i >= -2 and i <= -1 -> :negative
        0 -> :neutral
        i when i >= 1 and i <= 2 -> :positive
        i when i >= 3 -> :strongly_positive
      end
    rescue
      _ -> :neutral
    end
  end

  @spec name(sentiment()) :: String.t()
  def name(sent) do
    case sent do
      :strongly_positive -> "strongly positive"
      :positive -> "positive"
      :neutral -> "neutral"
      :negative -> "negative"
      :strongly_negative -> "strongly negative"
    end
  end
end
