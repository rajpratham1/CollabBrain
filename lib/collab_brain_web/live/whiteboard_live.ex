defmodule CollabBrainWeb.WhiteboardLive do
  use CollabBrainWeb, :live_view

  alias CollabBrain.Workspaces

  @impl true
  def mount(%{"workspace_id" => workspace_id}, session, socket) do
    bundle = Workspaces.get_workspace_bundle!(workspace_id)
    
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CollabBrain.PubSub, "whiteboard:#{workspace_id}")
    end

    {:ok,
     socket
     |> assign(:workspace_id, workspace_id)
     |> assign(:workspace, bundle.workspace)
     |> assign(:presence, bundle.presence)
     |> assign(:current_user, %{uid: session["uid"], display_name: session["display_name"]})}
  end

  @impl true
  def handle_event("set_color", %{"color" => color}, socket) do
    {:noreply, push_event(socket, "set_color", %{color: color})}
  end

  @impl true
  def handle_event("clear_board", _, socket) do
    {:noreply, push_event(socket, "clear_board", %{})}
  end

  @impl true
  def handle_event("draw_start", %{"x" => x, "y" => y, "color" => color}, socket) do
    broadcast_draw(socket.assigns.workspace_id, %{type: "start", x: x, y: y, color: color, uid: socket.assigns.current_user.uid})
    {:noreply, socket}
  end

  @impl true
  def handle_event("draw_move", %{"x" => x, "y" => y}, socket) do
    broadcast_draw(socket.assigns.workspace_id, %{type: "move", x: x, y: y, uid: socket.assigns.current_user.uid})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:draw_event, event}, socket) do
    # Push the event to the client to draw on canvas
    {:noreply, push_event(socket, "remote_draw", event)}
  end

  defp broadcast_draw(workspace_id, event) do
    Phoenix.PubSub.broadcast(CollabBrain.PubSub, "whiteboard:#{workspace_id}", {:draw_event, event})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="workspace-shell">
      <aside class="workspace-sidebar">
        <.link navigate={~p"/workspaces/#{@workspace_id}"} class="nav-pill">
          ← Back to Workspace
        </.link>

        <div class="sidebar-section">
          <div class="section-title">Tools</div>
          <div style="display: flex; gap: 10px; margin-top: 10px;">
            <button class="status-pill" phx-click="set_color" phx-value-color="#38bdf8">Blue</button>
            <button class="status-pill" phx-click="set_color" phx-value-color="#f43f5e">Red</button>
            <button class="status-pill" phx-click="set_color" phx-value-color="#2dd4bf">Green</button>
          </div>
          <button class="secondary-link" style="width: 100%; margin-top: 20px;" phx-click="clear_board">🗑️ Clear Board</button>
        </div>

        <section class="sidebar-section">
          <div class="section-title">Active Artists</div>
          <div class="presence-list">
            <%= for person <- @presence do %>
              <div class="presence-item">
                <div class="avatar-bubble" style="width: 28px; height: 28px;"><%= String.first(person["display_name"]) %></div>
                <span style="font-size: 0.85rem;"><%= person["display_name"] %></span>
              </div>
            <% end %>
          </div>
        </section>
      </aside>

      <main class="workspace-main" style="padding: 0; background: #0f172a; overflow: hidden; position: relative;">
        <div style="position: absolute; inset: 0; background-image: radial-gradient(rgba(56, 189, 248, 0.15) 1.5px, transparent 1.5px); background-size: 40px 40px; pointer-events: none;"></div>
        <canvas 
          id="whiteboard-canvas" 
          phx-hook="Whiteboard" 
          style="width: 100%; height: 100%; cursor: crosshair; display: block; position: relative; z-index: 10;"
        ></canvas>
      </main>
    </div>
    """
  end
end
