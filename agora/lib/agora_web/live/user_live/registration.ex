defmodule AgoraWeb.UserLive.Registration do
  use AgoraWeb, :live_view

  alias Agora.Accounts
  alias Agora.Accounts.User

  @input_class "w-full input border border-base-content/10 bg-base-100/80 text-base-content placeholder:text-base-content/40 h-12 text-sm rounded-xl focus:outline-none focus:border-primary focus:ring-1 focus:ring-primary transition-all"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-sm py-4">
        <.auth_logo />

        <div
          id="registration-card"
          phx-hook="Tilt"
          class="tilt glass depth-card rounded-2xl p-6 rise-in border border-base-content/10"
          style="animation-delay: 80ms"
        >
          <p class="mb-4 text-center text-xs text-base-content/70 leading-relaxed">
            We'll email you a link to confirm your account — no password needed yet.
          </p>

          <.form
            for={@form}
            id="registration_form"
            phx-submit="save"
            phx-change="validate"
            class="space-y-4"
          >
            <.input
              field={@form[:email]}
              type="email"
              placeholder="Email address"
              autocomplete="username"
              spellcheck="false"
              required
              class={@input_class}
              phx-mounted={JS.focus()}
            />

            <.button
              phx-disable-with="Creating account..."
              class="btn btn-primary w-full h-12 text-sm font-bold text-white depth-glow active:scale-[0.97] transition-all"
            >
              Create Account
            </.button>
          </.form>

          <div class="mt-6 text-center text-xs">
            <.link
              navigate={~p"/users/log-in"}
              class="font-bold text-base-content hover:text-primary transition-colors"
            >
              Already have an account? Log in
            </.link>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: AgoraWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_email(%User{}, %{}, validate_unique: false)

    {:ok, socket |> assign(:input_class, @input_class) |> assign_form(changeset),
     temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "An email was sent to #{user.email}, please access it to confirm your account."
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_email(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
