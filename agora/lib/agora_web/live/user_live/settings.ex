defmodule AgoraWeb.UserLive.Settings do
  use AgoraWeb, :live_view

  on_mount {AgoraWeb.UserAuth, :require_sudo_mode}

  alias Agora.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-md space-y-6 py-2">
        <div class="flex items-center gap-3 border-b border-base-content/10 pb-4 rise-in">
          <div class="flex items-center justify-center size-10 rounded-xl bg-gradient-to-br from-primary to-rose-600 text-white depth-glow">
            <.icon name="hero-cog-6-tooth" class="size-5" />
          </div>
          <div>
            <h1 class="font-display text-xl font-extrabold text-base-content tracking-wide">
              Account Settings
            </h1>
            <p class="text-xs text-base-content/60">Manage your email and security preferences</p>
          </div>
        </div>

        <!-- Change Email Form Card -->
        <div class="rounded-2xl glass depth-card p-6 rise-in border border-base-content/10 space-y-4">
          <h3 class="font-display text-sm font-bold text-base-content flex items-center gap-2">
            <.icon name="hero-envelope" class="size-4 text-primary" /> Email Address
          </h3>
          <.form
            for={@email_form}
            id="email_form"
            phx-submit="update_email"
            phx-change="validate_email"
            class="space-y-4"
          >
            <.input
              field={@email_form[:email]}
              type="email"
              label="Email Address"
              autocomplete="username"
              spellcheck="false"
              required
            />
            <.button
              variant="primary"
              phx-disable-with="Changing..."
              class="btn btn-primary font-bold text-xs depth-glow active:scale-95 transition-all"
            >
              Change Email
            </.button>
          </.form>
        </div>

        <!-- Change Password Form Card -->
        <div
          class="rounded-2xl glass depth-card p-6 rise-in border border-base-content/10 space-y-4"
          style="animation-delay: 60ms"
        >
          <h3 class="font-display text-sm font-bold text-base-content flex items-center gap-2">
            <.icon name="hero-lock-closed" class="size-4 text-primary" /> Security & Password
          </h3>
          <.form
            for={@password_form}
            id="password_form"
            action={~p"/users/update-password"}
            method="post"
            phx-change="validate_password"
            phx-submit="update_password"
            phx-trigger-action={@trigger_submit}
            class="space-y-4"
          >
            <input
              name={@password_form[:email].name}
              type="hidden"
              id="hidden_user_email"
              spellcheck="false"
              value={@current_email}
            />
            <.input
              field={@password_form[:password]}
              type="password"
              label="New Password"
              autocomplete="new-password"
              spellcheck="false"
              required
            />
            <.input
              field={@password_form[:password_confirmation]}
              type="password"
              label="Confirm New Password"
              autocomplete="new-password"
              spellcheck="false"
            />
            <.button
              variant="primary"
              phx-disable-with="Saving..."
              class="btn btn-primary font-bold text-xs depth-glow active:scale-95 transition-all"
            >
              Save Password
            </.button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
