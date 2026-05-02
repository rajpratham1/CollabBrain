defmodule CollabBrain.Collaboration.DocumentSession do
  use GenServer

  alias CollabBrain.Collaboration.OperationTransform
  alias CollabBrain.Persistence

  def ensure_started(workspace_id, document_id) do
    name = via(workspace_id, document_id)

    case GenServer.whereis(name) do
      nil ->
        {:ok, pid} =
          DynamicSupervisor.start_child(
            CollabBrain.DocumentSupervisor,
            {__MODULE__, {workspace_id, document_id}}
          )

        pid

      pid ->
        pid
    end
  end

  def start_link({workspace_id, document_id}) do
    GenServer.start_link(__MODULE__, {workspace_id, document_id}, name: via(workspace_id, document_id))
  end

  def submit_operation(workspace_id, document_id, operation) do
    workspace_id
    |> ensure_started(document_id)
    |> GenServer.call({:submit_operation, operation}, 15_000)
  end

  def fetch_snapshot(workspace_id, document_id) do
    workspace_id
    |> ensure_started(document_id)
    |> GenServer.call(:fetch_snapshot)
  end

  @impl true
  def init({workspace_id, document_id}) do
    {:ok, bootstrap_state(workspace_id, document_id)}
  end

  @impl true
  def handle_call(:fetch_snapshot, _from, state) do
    {:reply, {:ok, %{body: state.body, revision: state.revision}}, state}
  end

  @impl true
  def handle_call({:submit_operation, operation}, _from, state) do
    unapplied_history = Enum.filter(state.history, &(&1["applied_revision"] > operation["base_revision"]))
    rebased = OperationTransform.rebase(operation, unapplied_history)
    new_body = OperationTransform.apply_operation(state.body, rebased)
    new_revision = state.revision + 1

    persisted_op =
      rebased
      |> Map.put("applied_revision", new_revision)
      |> Map.put("inserted_at", DateTime.utc_now())

    persist_snapshot(state.workspace_id, state.document_id, new_body, new_revision)
    persist_operation(state.workspace_id, state.document_id, persisted_op)

    broadcast_payload = %{
      body: new_body,
      revision: new_revision,
      operation: persisted_op
    }

    Phoenix.PubSub.broadcast(
      CollabBrain.PubSub,
      topic(state.workspace_id, state.document_id),
      {:document_updated, broadcast_payload}
    )

    next_state = %{
      state
      | body: new_body,
        revision: new_revision,
        history: Enum.take(state.history ++ [persisted_op], -100)
    }

    {:reply, {:ok, broadcast_payload}, next_state}
  end

  defp bootstrap_state(workspace_id, document_id) do
    {:ok, decoded} = Persistence.get_document(workspace_id, document_id)
    fields = decoded["fields"]

    %{
      workspace_id: workspace_id,
      document_id: document_id,
      body: fields["body"],
      revision: fields["revision"],
      history: []
    }
  end

  defp persist_snapshot(workspace_id, document_id, body, revision) do
    Persistence.update_document(
      workspace_id,
      document_id,
      %{body: body, revision: revision, updated_at: DateTime.utc_now()},
      ["body", "revision", "updated_at"]
    )
  end

  defp persist_operation(workspace_id, document_id, operation) do
    operation_id = "op_" <> Integer.to_string(System.unique_integer([:positive]))
    Persistence.create_operation(workspace_id, document_id, operation_id, operation)
  end

  def topic(workspace_id, document_id), do: "workspace:#{workspace_id}:document:#{document_id}"

  defp via(workspace_id, document_id) do
    {:via, Registry, {CollabBrain.Registry, {:document, workspace_id, document_id}}}
  end
end
