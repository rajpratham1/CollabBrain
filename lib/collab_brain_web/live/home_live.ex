defmodule CollabBrainWeb.HomeLive do
  use CollabBrainWeb, :live_view

  alias CollabBrain.AppConfig
  alias CollabBrain.Persistence
  alias CollabBrain.Workspaces

  @impl true
  def mount(_params, session, socket) do
    current_user =
      case session["uid"] do
        nil ->
          nil

        uid ->
          %{
            uid: uid,
            display_name: session["display_name"] || "Guest",
            email: session["email"],
            client_id: session["client_id"]
          }
      end

    featured_workspace =
      Workspaces.list_workspaces()
      |> List.first()

    default_workspace_id =
      case featured_workspace do
        %{"id" => id} -> id
        _ -> AppConfig.default_workspace_id()
      end

    {:ok,
     socket
     |> assign(:firebase_enabled?, Persistence.firebase_enabled?())
     |> assign(:current_user, current_user)
     |> assign(:featured_workspace, featured_workspace)
     |> assign(:default_workspace_id, default_workspace_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="landing-shell card glow-card slide-up" style="max-width: 1200px; margin: 2rem auto;">
      <div style="text-align: center; margin-bottom: 4rem;">
        <div class="auth-logo-wrap">
          <img src="/favicon.svg" class="auth-logo" alt="CollabBrain" />
        </div>
        <div class="eyebrow">The Evolution of Teamwork</div>
        <h1 style="font-size: clamp(3rem, 8vw, 5rem); line-height: 1; margin-bottom: 1.5rem;">CollabBrain Elite</h1>
        <p style="font-size: 1.25rem; max-width: 800px; margin: 0 auto; color: var(--muted);">
          A production-grade collaboration OS designed for high-stakes environments. 
          Real-time state synchronization, shared canvases, and advanced presence awareness 
          packaged in a stunning glassmorphic interface.
        </p>

        <div class="hero-stat-grid" style="margin-top: 3rem;">
          <div class="metric-card">
            <strong>&lt; 50ms</strong>
            <span>Sync Latency</span>
          </div>
          <div class="metric-card">
            <strong>∞</strong>
            <span>Scalability</span>
          </div>
          <div class="metric-card">
            <strong>OTP</strong>
            <span>Reliability</span>
          </div>
        </div>

        <div style="margin-top: 3rem; display: flex; gap: 1rem; justify-content: center;">
          <%= if @current_user do %>
            <.link class="primary-link" navigate={~p"/workspaces/#{@default_workspace_id}"}>Enter Command Center</.link>
          <% else %>
            <a class="primary-link" href="#auth-panels">Get Started Now</a>
            <a class="secondary-link" href="#mission">Our Mission</a>
          <% end %>
        </div>
      </div>
    </section>

    <section id="mission" style="max-width: 1000px; margin: 6rem auto; padding: 0 2rem;">
      <div class="eyebrow" style="text-align: center;">Purpose</div>
      <h2 style="text-align: center; font-size: 2.5rem; margin-bottom: 2rem;">Why CollabBrain?</h2>
      <p style="text-align: center; font-size: 1.2rem; color: var(--muted); line-height: 1.8;">
        In a world of fragmented tools, CollabBrain serves as the single source of truth for your team. 
        We eliminate the "lag" between thought and action by providing a unified environment where 
        documents, sketches, and conversations live in perfect synchronicity. Our goal is to make 
        remote work feel more "present" than being in the same office.
      </p>
    </section>

    <section style="max-width: 1200px; margin: 6rem auto; padding: 0 2rem;">
      <div class="eyebrow" style="text-align: center;">Workflow</div>
      <h2 style="text-align: center; font-size: 2.5rem; margin-bottom: 4rem;">How It Works</h2>
      
      <div class="auth-grid" style="grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));">
        <div class="card slide-up">
          <div class="avatar-bubble" style="margin-bottom: 1.5rem; background: var(--brand);">1</div>
          <h3>Deploy & Sync</h3>
          <p>Connect your Firebase instance for production-grade persistence or use our optimized local store for rapid prototyping.</p>
        </div>
        <div class="card slide-up delay-1">
          <div class="avatar-bubble" style="margin-bottom: 1.5rem; background: var(--accent);">2</div>
          <h3>Initialize Workspace</h3>
          <p>Create dedicated rooms for specific projects. Each room acts as a siloed environment with its own tools and logs.</p>
        </div>
        <div class="card slide-up delay-2">
          <div class="avatar-bubble" style="margin-bottom: 1.5rem; background: var(--brand-glow);">3</div>
          <h3>Collaborate Live</h3>
          <p>Draw on the shared whiteboard, edit documents with paragraph-level locking, and stay synced with the Nerve Center.</p>
        </div>
      </div>
    </section>

    <section id="auth-panels" class="auth-grid">
      <div class="card slide-up">
        <div class="eyebrow">Elite Access</div>
        <h2>Create Account</h2>
        <p>Join the next generation of collaborative intelligence.</p>
        
        <form action={~p"/register"} method="post" class="stack-form">
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <input type="text" name="user[display_name]" placeholder="Full Name" required />
          <input type="email" name="user[email]" placeholder="Work Email" required />
          <input type="password" name="user[password]" placeholder="Secure Password" minlength="6" required />
          <button type="submit">Initialize Identity</button>
        </form>

        <div class="auth-divider"><span>OR</span></div>
        <button type="button" class="google-btn" onclick="signInWithGoogle()">
          <img src="https://www.gstatic.com/firebasejs/ui/2.0.0/images/pjax/google.png" width="18" alt="G" />
          Continue with Google
        </button>
      </div>

      <div class="card slide-up delay-1">
        <div class="eyebrow">Authentication</div>
        <h2>Secure Sign In</h2>
        <p>Verify your credentials to re-enter the workspace.</p>
        
        <form action={~p"/sign-in"} method="post" class="stack-form">
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <input type="email" name="user[email]" placeholder="Work Email" required />
          <input type="password" name="user[password]" placeholder="Password" required />
          <div class="form-footer">
            <button type="submit">Enter Workspace</button>
            <.link href={~p"/reset-password"} class="text-link">Forgot password?</.link>
          </div>
        </form>

        <div class="auth-divider"><span>OR</span></div>
        <button type="button" class="google-btn" onclick="signInWithGoogle()">
          <img src="https://www.gstatic.com/firebasejs/ui/2.0.0/images/pjax/google.png" width="18" alt="G" />
          Continue with Google
        </button>
      </div>
      
      <%# Hidden form for Google callback %>
      <form id="google-auth-form" action={~p"/auth/google"} method="post" style="display:none">
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <input type="hidden" name="uid" id="google-uid" />
        <input type="hidden" name="email" id="google-email" />
        <input type="hidden" name="display_name" id="google-display-name" />
      </form>
    </section>
    """
  end
end
