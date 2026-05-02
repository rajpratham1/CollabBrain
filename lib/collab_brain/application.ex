defmodule CollabBrain.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: CollabBrain.Registry},
      {Phoenix.PubSub, name: CollabBrain.PubSub},
      {Finch, name: CollabBrain.Finch},
      CollabBrain.LocalStore,
      CollabBrain.Firebase.TokenProvider,
      {DynamicSupervisor, strategy: :one_for_one, name: CollabBrain.RoomSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: CollabBrain.DocumentSupervisor},
      CollabBrainWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: CollabBrain.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    CollabBrainWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
