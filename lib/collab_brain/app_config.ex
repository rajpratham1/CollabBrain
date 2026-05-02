defmodule CollabBrain.AppConfig do
  def default_workspace_id do
    Application.get_env(:collab_brain, :default_workspace_id, "demo-space")
  end
end

