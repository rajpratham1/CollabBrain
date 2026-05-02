defmodule CollabBrainWeb.ResetPasswordLive do
  use CollabBrainWeb, :live_view

  alias CollabBrain.Accounts.Session

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, email: "", sent: false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="auth-grid">
      <div class="auth-card card">
        <div class="auth-logo-wrap">
          <img src="/favicon.svg" class="auth-logo" alt="CollabBrain" />
        </div>
        <div class="eyebrow">Account Recovery</div>
        <h2>Reset your password</h2>
        
        <%= if @sent do %>
          <div class="success-message">
            <p>If an account exists for <strong><%= @email %></strong>, you will receive a password reset link shortly.</p>
            <.link navigate={~p"/"} class="primary-link">Return to Sign In</.link>
          </div>
        <% else %>
          <p>Enter your email address and we'll send you a link to reset your password.</p>
          <form phx-submit="send_reset_link" class="stack-form">
            <input type="email" name="email" value={@email} placeholder="Work email" required />
            <div class="form-footer">
              <button type="submit" phx-disable-with="Sending...">Send Reset Link</button>
              <.link navigate={~p"/"} class="text-link">Back to login</.link>
            </div>
          </form>
        <% end %>
      </div>
    </section>
    """
  end

  @impl true
  def handle_event("send_reset_link", %{"email" => email}, socket) do
    case Session.send_password_reset(email) do
      :ok ->
        {:noreply, assign(socket, email: email, sent: true)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not process request.")}
    end
  end
end
