defmodule AgoraWeb.UserLive.LoginTest do
  use AgoraWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Agora.AccountsFixtures
  import Swoosh.TestAssertions

  describe "login page" do
    test "renders login page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "AGORA"
      assert html =~ "Sign Up"
      assert html =~ "Login"
      assert html =~ "Log in with an emailed link instead"
    end
  end

  describe "user login - magic link" do
    test "sends magic link email when user exists", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")
      lv |> element("button", "Log in with an emailed link instead") |> render_click()

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "If your email is in our system"

      assert Agora.Repo.get_by!(Agora.Accounts.UserToken, user_id: user.id).context ==
               "login"
    end

    test "does not disclose if user is registered", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")
      lv |> element("button", "Log in with an emailed link instead") |> render_click()

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", user: %{email: "idonotexist@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "If your email is in our system"
    end
  end

  describe "user login - password" do
    test "redirects if user logs in with valid credentials", %{conn: conn} do
      user = user_fixture() |> set_password()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password",
          user: %{email: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to login page with a flash error if credentials are invalid", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password", user: %{email: "test@email.com", password: "123456"})

      render_submit(form, %{user: %{remember_me: true}})

      conn = follow_trigger_action(form, conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "user login - forgot password" do
    test "shows a forgot password link in password mode", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Forgot password?"
    end

    test "clicking it switches to the magic-link form with reset copy", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      html = lv |> element("button", "Forgot password?") |> render_click()

      assert html =~ "Email Me a Password Reset Link"
      assert html =~ "set a new password from Settings"
      assert html =~ "Back to password login"
    end

    test "toggling back to password login clears the reset copy", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      lv |> element("button", "Forgot password?") |> render_click()
      html = lv |> element("button", "Back to password login") |> render_click()

      refute html =~ "Email Me a Password Reset Link"
      assert html =~ ~s(id="login_form_password")
    end

    test "emails a magic link that routes the user to Settings after log-in", %{conn: conn} do
      user = user_fixture()
      # drain the confirmation email that user_fixture/1 sends during setup
      assert_email_sent()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")
      lv |> element("button", "Forgot password?") |> render_click()

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "If your email is in our system"

      assert Agora.Repo.get_by!(Agora.Accounts.UserToken, user_id: user.id).context ==
               "login"

      assert_email_sent(fn email -> email.text_body =~ "return_to=%2Fusers%2Fsettings" end)
    end
  end

  describe "login navigation" do
    test "redirects to registration page when the Sign Up link is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _registration_live, registration_html} =
        lv
        |> element("main a", "Sign Up")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/register")

      assert registration_html =~ "Sign Up"
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "shows login page with email filled in", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Reauthenticate to perform sensitive actions"
      refute html =~ "Sign Up"
      assert html =~ "Login"

      assert html =~
               ~s(<input type="email" name="user[email]" id="login_form_password_email" value="#{user.email}")
    end
  end
end
