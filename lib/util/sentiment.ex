defmodule Sentiment do
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
end
