defmodule AgoraWeb.UserLive.Confirmation do
  use AgoraWeb, :live_view

  alias Agora.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm py-4">
        <.auth_logo />

        <div class="glass depth-card rounded-2xl p-6 rise-in border border-base-content/10 space-y-4">
          <div class="text-center">
            <h2 class="font-display text-lg font-bold text-base-content">Welcome, {@user.email}</h2>
            <p class="text-xs text-base-content/60 mt-1">Confirm your session to enter AGORA</p>
          </div>

          <.form
            :if={!@user.confirmed_at}
            for={@form}
            id="confirmation_form"
            phx-mounted={JS.focus_first()}
            phx-submit="submit"
            action={~p"/users/log-in?_action=confirmed"}
            phx-trigger-action={@trigger_submit}
            class="space-y-2.5"
          >
            <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
            <input type="hidden" name={@form[:return_to].name} value={@form[:return_to].value} />
            <.button
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with="Confirming..."
              class="btn btn-primary w-full h-12 text-xs font-bold text-white depth-glow active:scale-[0.97] transition-all"
            >
              Confirm and stay logged in
            </.button>
            <.button
              phx-disable-with="Confirming..."
              class="btn btn-outline w-full h-11 text-xs font-bold border-base-content/20 hover:bg-base-content/10 active:scale-[0.97] transition-all"
            >
              Confirm and log in only this time
            </.button>
          </.form>

          <.form
            :if={@user.confirmed_at}
            for={@form}
            id="login_form"
            phx-submit="submit"
            phx-mounted={JS.focus_first()}
            action={~p"/users/log-in"}
            phx-trigger-action={@trigger_submit}
            class="space-y-2.5"
          >
            <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
            <input type="hidden" name={@form[:return_to].name} value={@form[:return_to].value} />
            <%= if @current_scope do %>
              <.button
                phx-disable-with="Logging in..."
                class="btn btn-primary w-full h-12 text-xs font-bold text-white depth-glow active:scale-[0.97] transition-all"
              >
                Log in
              </.button>
            <% else %>
              <.button
                name={@form[:remember_me].name}
                value="true"
                phx-disable-with="Logging in..."
                class="btn btn-primary w-full h-12 text-xs font-bold text-white depth-glow active:scale-[0.97] transition-all"
              >
                Keep me logged in on this device
              </.button>
              <.button
                phx-disable-with="Logging in..."
                class="btn btn-outline w-full h-11 text-xs font-bold border-base-content/20 hover:bg-base-content/10 active:scale-[0.97] transition-all"
              >
                Log me in only this time
              </.button>
            <% end %>
          </.form>

          <div
            :if={!@user.confirmed_at}
            class="p-3 rounded-xl bg-base-content/5 border border-base-content/5 text-[11px] text-base-content/70"
          >
            Tip: You can enable password login anytime in your account settings.
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token} = params, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      return_to = if params["return_to"] == "/users/settings", do: "/users/settings"
      form = to_form(%{"token" => token, "return_to" => return_to}, as: "user")

      {:ok, assign(socket, user: user, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "Magic link is invalid or it has expired.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
