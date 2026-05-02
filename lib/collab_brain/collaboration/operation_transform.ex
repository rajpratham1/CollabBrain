defmodule CollabBrain.Collaboration.OperationTransform do
  @moduledoc """
  Minimal linear-text operational transform for insert/delete operations.
  """

  def rebase(operation, []), do: operation

  def rebase(operation, [op | rest]) do
    operation
    |> transform_against(op)
    |> rebase(rest)
  end

  def apply_operation(body, %{"type" => "insert", "offset" => offset, "text" => text}) do
    {left, right} = String.split_at(body, offset)
    left <> text <> right
  end

  def apply_operation(body, %{"type" => "delete", "offset" => offset, "length" => length}) do
    {left, rest} = String.split_at(body, offset)
    {_removed, right} = String.split_at(rest, length)
    left <> right
  end

  def transform_against(%{"type" => "insert"} = candidate, %{"type" => "insert"} = applied) do
    if applied["offset"] <= candidate["offset"] do
      Map.update!(candidate, "offset", &(&1 + String.length(applied["text"])))
    else
      candidate
    end
  end

  def transform_against(%{"type" => "insert"} = candidate, %{"type" => "delete"} = applied) do
    if applied["offset"] < candidate["offset"] do
      shift = min(applied["length"], candidate["offset"] - applied["offset"])
      Map.update!(candidate, "offset", &max(0, &1 - shift))
    else
      candidate
    end
  end

  def transform_against(%{"type" => "delete"} = candidate, %{"type" => "insert"} = applied) do
    if applied["offset"] < candidate["offset"] do
      Map.update!(candidate, "offset", &(&1 + String.length(applied["text"])))
    else
      candidate
    end
  end

  def transform_against(%{"type" => "delete"} = candidate, %{"type" => "delete"} = applied) do
    cond do
      applied["offset"] >= candidate["offset"] + candidate["length"] ->
        candidate

      applied["offset"] + applied["length"] <= candidate["offset"] ->
        Map.update!(candidate, "offset", &max(0, &1 - applied["length"]))

      true ->
        overlap_start = max(candidate["offset"], applied["offset"])
        overlap_end = min(candidate["offset"] + candidate["length"], applied["offset"] + applied["length"])
        overlap = max(0, overlap_end - overlap_start)

        candidate
        |> Map.update!("length", &max(0, &1 - overlap))
        |> Map.update!("offset", fn current ->
          if applied["offset"] < current do
            max(0, current - min(applied["length"], current - applied["offset"]))
          else
            current
          end
        end)
    end
  end
end
