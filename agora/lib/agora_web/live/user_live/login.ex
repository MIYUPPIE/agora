defmodule AgoraWeb.UserLive.Login do
  use AgoraWeb, :live_view

  alias Agora.Accounts

  @input_class "w-full input border-none bg-primary text-black/80 placeholder:text-black/50 h-14 text-base focus:outline-none focus:ring-2 focus:ring-primary-content/40"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-sm">
        <.auth_logo />

        <div
          :if={@current_scope}
          class="mb-4 text-center text-sm text-base-content/70"
        >
          Reauthenticate to perform sensitive actions on your account.
        </div>

        <div :if={local_mail_adapter?()} class="alert alert-info mb-4 text-sm">
          <.icon name="hero-information-circle" class="size-5 shrink-0" />
          <span>
            Local mail adapter — view sent emails at <.link href="/dev/mailbox" class="underline">/dev/mailbox</.link>.
          </span>
        </div>

        <.form
          :let={f}
          :if={@mode == :password}
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
          class="space-y-4"
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            placeholder="Email"
            autocomplete="username"
            spellcheck="false"
            required
            class={@input_class}
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:password]}
            type="password"
            placeholder="Password"
            autocomplete="current-password"
            spellcheck="false"
            required
            class={@input_class}
          />
          <input type="hidden" name={@form[:remember_me].name} value="true" />
          <.button class="btn btn-neutral w-full h-12 text-base">Login</.button>
        </.form>

        <.form
          :let={f}
          :if={@mode == :magic}
          for={@form}
          id="login_form_magic"
          phx-submit="submit_magic"
          class="space-y-4"
        >
          <.input
            field={f[:email]}
            type="email"
            placeholder="Email"
            autocomplete="username"
            spellcheck="false"
            required
            class={@input_class}
            phx-mounted={JS.focus()}
          />
          <.button class="btn btn-neutral w-full h-12 text-base">
            Email me a login link
          </.button>
        </.form>

        <div class="mt-6 flex flex-col items-center gap-2 text-sm">
          <button
            type="button"
            phx-click="toggle_mode"
            class="text-base-content/60 hover:text-base-content underline-offset-4 hover:underline"
          >
            <%= if @mode == :password do %>
              Log in with an emailed link instead
            <% else %>
              Log in with a password instead
            <% end %>
          </button>

          <.link
            :if={!@current_scope}
            navigate={~p"/users/register"}
            class="font-semibold text-base-content hover:underline"
          >
            Sign Up
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok,
     socket
     |> assign(form: form, trigger_submit: false, mode: :password)
     |> assign(:input_class, @input_class)}
  end

  @impl true
  def handle_event("toggle_mode", _params, socket) do
    {:noreply,
     assign(socket, :mode, if(socket.assigns.mode == :password, do: :magic, else: :password))}
  end

  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:agora, Agora.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
