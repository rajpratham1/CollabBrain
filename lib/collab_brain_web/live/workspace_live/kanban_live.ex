defmodule CollabBrainWeb.KanbanLive do
  use CollabBrainWeb, :live_view

  alias CollabBrain.Workspaces
  alias CollabBrain.Persistence

  @impl true
  def mount(%{"workspace_id" => workspace_id}, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CollabBrain.PubSub, "workspace_kanban:#{workspace_id}")
    end

    bundle = Workspaces.get_workspace_bundle!(workspace_id)
    workspace = bundle.workspace || %{"name" => "Workspace"}
    tasks = Persistence.list_tasks(workspace_id)

    # Initial demo data if nothing in DB
    tasks = if Enum.empty?(tasks) do
      [
        %{"fields" => %{"id" => "t1", "title" => "Initialize Production Rules", "status" => "done", "priority" => "urgent", "author_name" => "System", "inserted_at" => DateTime.utc_now()}},
        %{"fields" => %{"id" => "t2", "title" => "Design Kanban Interaction", "status" => "in_progress", "priority" => "high", "author_name" => "System", "inserted_at" => DateTime.utc_now()}},
        %{"fields" => %{"id" => "t3", "title" => "Integrate Firestore Sync", "status" => "todo", "priority" => "medium", "author_name" => "System", "inserted_at" => DateTime.utc_now()}}
      ]
    else
      tasks
    end

    {:ok,
     socket
     |> assign(:workspace_id, workspace_id)
     |> assign(:workspace, workspace)
     |> assign(:tasks, tasks)
     |> assign(:show_modal, false)
     |> assign(:new_task_title, "")
     |> assign(:current_user, %{
       uid: session["uid"],
       display_name: session["display_name"] || "Guest",
       email: session["email"]
     })
     |> assign(:page_title, "Kanban Board")}
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
          <div class="section-title">Board Summary</div>
          <div class="metric-card" style="padding: 12px; margin-top: 10px;">
            <strong><%= length(@tasks) %></strong>
            <span>Total Tasks</span>
          </div>
        </div>

        <button phx-click="toggle_modal" class="primary-link" style="width: 100%; margin-top: 20px;">+ Create Task</button>
      </aside>

      <main class="workspace-main">
        <header style="margin-bottom: 2rem;">
          <div class="eyebrow">Task Management</div>
          <h1 style="font-size: 2.5rem;"><%= get_in(@workspace, ["name"]) || "Workspace" %> Board</h1>
        </header>

        <div class="kanban-board">
          <%= for status <- ["todo", "in_progress", "done"] do %>
            <div class="kanban-column">
              <div class="column-header">
                <h3><%= String.capitalize(String.replace(status, "_", " ")) %></h3>
                <span class="status-pill"><%= Enum.count(@tasks, &(get_in(&1, ["fields", "status"]) == status)) %></span>
              </div>

              <div class="task-list">
                <%= for task <- Enum.filter(@tasks, &(get_in(&1, ["fields", "status"]) == status)) do %>
                  <% task_id = get_in(task, ["fields", "id"]) || "temp_#{System.unique_integer()}" %>
                  <div id={task_id} class="card task-card slide-up" phx-click="move_task" phx-value-id={task_id} phx-value-status={status}>
                    <span class={"priority-tag #{get_in(task, ["fields", "priority"]) || "medium"}"}>
                      <%= get_in(task, ["fields", "priority"]) || "Medium" %>
                    </span>
                    <h4 style="margin-top: 5px; color: var(--text);"><%= get_in(task, ["fields", "title"]) %></h4>
                    <div style="display: flex; justify-content: space-between; align-items: center; margin-top: 15px;">
                      <div class="avatar-bubble" style="width: 24px; height: 24px; font-size: 0.6rem;">
                        <%= String.first(get_in(task, ["fields", "author_name"]) || "A") %>
                      </div>
                      <span style="font-size: 0.75rem; color: var(--muted);"><%= pretty_time(get_in(task, ["fields", "inserted_at"])) %></span>
                    </div>
                  </div>
                <% end %>
              </div>
              
              <button phx-click="toggle_modal" phx-value-status={status} class="secondary-link" style="width: 100%; border-style: dashed; opacity: 0.6;">+ Add Item</button>
            </div>
          <% end %>
        </div>
      </main>

      <%= if @show_modal do %>
        <div class="modal-overlay">
          <div class="modal-content card glow-card" style="position: relative;">
            <button type="button" phx-click="toggle_modal" style="position: absolute; top: 1.5rem; right: 1.5rem; padding: 5px; background: transparent; border: none; color: var(--muted); cursor: pointer; font-size: 1.2rem;">✕</button>
            <div class="eyebrow">New Task</div>
            <h2>Create Assignment</h2>
            <form phx-change="validate_task" phx-submit="save_task" class="stack-form" style="margin-top: 1.5rem;">
              <input type="text" id="new_task_title_field" name="title" value={@new_task_title} phx-debounce="200" placeholder="Task description..." required />
              <select name="priority">
                <option value="medium">Medium Priority</option>
                <option value="high">High Priority</option>
                <option value="urgent">Urgent</option>
              </select>
              <div style="display: flex; gap: 1rem; margin-top: 1rem;">
                <button type="submit" style="flex: 1;">Deploy Task</button>
                <button type="button" phx-click="toggle_modal" class="secondary-link" style="flex: 1;">Cancel</button>
              </div>
            </form>
          </div>
        </div>
      <% end %>
    </div>

    <style>
      .modal-overlay {
        position: fixed;
        inset: 0;
        background: rgba(0,0,0,0.8);
        backdrop-filter: blur(10px);
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 1000;
        padding: 2rem;
      }
      .modal-content {
        width: 100%;
        max-width: 450px;
        padding: 2.5rem;
        background: var(--bg);
        border: 1px solid var(--brand-glow);
      }
      .task-card {
        cursor: pointer;
        transition: transform 0.2s, border-color 0.2s;
      }
      .task-card:hover {
        transform: translateY(-4px);
        border-color: var(--brand);
      }
      .task-list {
        display: flex;
        flex-direction: column;
        gap: 15px;
        min-height: 100px;
      }
    </style>
    """
  end

  @impl true
  def handle_event("toggle_modal", _, socket) do
    {:noreply, assign(socket, show_modal: !socket.assigns.show_modal)}
  end

  @impl true
  def handle_event("validate_task", %{"title" => title}, socket) do
    {:noreply, assign(socket, new_task_title: title)}
  end

  @impl true
  def handle_event("save_task", %{"title" => title, "priority" => priority}, socket) do
    task_id = "task_#{System.unique_integer([:positive])}"
    attrs = %{
      id: task_id,
      title: title,
      status: "todo",
      priority: priority,
      author_id: socket.assigns.current_user.uid,
      author_name: socket.assigns.current_user.display_name,
      inserted_at: DateTime.utc_now()
    }

    Persistence.create_task(socket.assigns.workspace_id, task_id, attrs)
    
    # Broadcast
    new_task = %{"fields" => Persistence.stringify_keys(attrs)}
    Phoenix.PubSub.broadcast(CollabBrain.PubSub, "workspace_kanban:#{socket.assigns.workspace_id}", {:task_created, new_task})

    Persistence.log_activity(socket.assigns.workspace_id, %{
      kind: "kanban",
      title: "📋 New Task Added",
      detail: "#{socket.assigns.current_user.display_name} added: #{title}",
      actor_name: socket.assigns.current_user.display_name
    })

    {:noreply, assign(socket, show_modal: false, new_task_title: "")}
  end

  @impl true
  def handle_event("move_task", %{"id" => id, "status" => current_status}, socket) do
    new_status = case current_status do
      "todo" -> "in_progress"
      "in_progress" -> "done"
      "done" -> "todo"
    end

    # Update in UI immediately for responsiveness
    updated_tasks = Enum.map(socket.assigns.tasks, fn task ->
      if get_in(task, ["fields", "id"]) == id do
        put_in(task, ["fields", "status"], new_status)
      else
        task
      end
    end)

    # Persist to DB
    Persistence.update_task(socket.assigns.workspace_id, id, %{status: new_status})

    Phoenix.PubSub.broadcast(CollabBrain.PubSub, "workspace_kanban:#{socket.assigns.workspace_id}", {:tasks_updated, updated_tasks})

    {:noreply, assign(socket, tasks: updated_tasks)}
  end

  @impl true
  def handle_info({:task_created, task}, socket) do
    {:noreply, update(socket, :tasks, &[task | &1])}
  end

  @impl true
  def handle_info({:tasks_updated, tasks}, socket) do
    {:noreply, assign(socket, tasks: tasks)}
  end

  defp pretty_time(%DateTime{} = value) do
    minutes = max(DateTime.diff(DateTime.utc_now(), value, :minute), 0)
    cond do
      minutes < 1 -> "just now"
      minutes == 1 -> "1 min ago"
      minutes < 60 -> "#{minutes} min ago"
      true -> "#{div(minutes, 60)}h ago"
    end
  end
  defp pretty_time(_), do: "just now"
end
