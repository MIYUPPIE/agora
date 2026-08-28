defmodule AgoraWeb.UserSessionController do
  use AgoraWeb, :controller

  alias Agora.Accounts
  alias AgoraWeb.UserAuth

  # magic link login requested from the "Forgot password?" link: send the user
  # straight to Settings to set a new password instead of the default landing page.
  def create(conn, %{"user" => %{"return_to" => "/users/settings"}} = params) do
    create(conn, params, "You're in — set a new password below.")
  end

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "User confirmed successfully.")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> maybe_put_return_to(user_params["return_to"])
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      _ ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # email + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, {_user, expired_tokens}} = Accounts.update_user_password(user, user_params)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  # Only ever trust an allowlisted internal path here — this value rides in an
  # emailed link, so an unvalidated value would be an open-redirect vector.
  @safe_return_to_paths ~w(/users/settings)

  defp maybe_put_return_to(conn, return_to) when return_to in @safe_return_to_paths do
    put_session(conn, :user_return_to, return_to)
  end

  defp maybe_put_return_to(conn, _return_to), do: conn

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
