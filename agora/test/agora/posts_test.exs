defmodule Agora.PostsTest do
  use Agora.DataCase, async: true

  import Agora.AccountsFixtures

  alias Agora.{Notifications, Posts, Social}

  describe "create_tiding/2" do
    test "creates a tiding post and fans out to clingers" do
      author = user_fixture()
      follower = user_fixture()
      {:ok, _} = Social.cling(follower.id, author.id)

      Phoenix.PubSub.subscribe(Agora.PubSub, "feed:#{follower.id}")

      assert {:ok, post} = Posts.create_tiding(author.id, %{"body" => "Gospel on the radio"})
      assert post.kind == :tiding
      assert post.body == "Gospel on the radio"

      assert_receive {:new_post, post_id}
      assert post_id == post.id
    end

    test "requires a body" do
      author = user_fixture()
      assert {:error, changeset} = Posts.create_tiding(author.id, %{"body" => ""})
      assert %{body: ["can't be blank"]} = errors_on(changeset)
    end

    test "does not broadcast to people who don't cling to the author" do
      author = user_fixture()
      stranger = user_fixture()

      Phoenix.PubSub.subscribe(Agora.PubSub, "feed:#{stranger.id}")
      {:ok, _post} = Posts.create_tiding(author.id, %{"body" => "hello"})

      refute_receive {:new_post, _}, 50
    end
  end

  describe "create_image_post/3" do
    test "creates a post with ordered media rows" do
      author = user_fixture()

      images = [
        %{url: "/uploads/a.jpg", byte_size: 100},
        %{url: "/uploads/b.jpg", byte_size: 200}
      ]

      assert {:ok, post} = Posts.create_image_post(author.id, %{"title" => "A day out"}, images)
      assert post.kind == :image_set
      assert post.title == "A day out"

      post = Posts.get_post!(post.id)
      assert Enum.map(post.media, & &1.url) == ["/uploads/a.jpg", "/uploads/b.jpg"]
      assert Enum.map(post.media, & &1.position) == [0, 1]
      assert Enum.all?(post.media, &(&1.kind == :image))
    end
  end

  describe "create_audio_post/3" do
    test "creates a post with one audio media row" do
      author = user_fixture()

      assert {:ok, post} =
               Posts.create_audio_post(
                 author.id,
                 %{
                   "title" => "Sounds of mystery",
                   "duration_ms" => 180_000,
                   "waveform" => [1, 5, 3]
                 },
                 %{url: "/uploads/clip.m4a", byte_size: 4096}
               )

      post = Posts.get_post!(post.id)
      assert post.kind == :audio
      assert post.duration_ms == 180_000
      assert [media] = post.media
      assert media.kind == :audio
      assert media.url == "/uploads/clip.m4a"
    end
  end

  describe "count_for_user/1" do
    test "counts only that user's own posts" do
      alice = user_fixture()
      bob = user_fixture()
      {:ok, _} = Posts.create_tiding(alice.id, %{"body" => "one"})
      {:ok, _} = Posts.create_tiding(alice.id, %{"body" => "two"})
      {:ok, _} = Posts.create_tiding(bob.id, %{"body" => "not alice's"})

      assert Posts.count_for_user(alice.id) == 2
      assert Posts.count_for_user(bob.id) == 1
    end
  end

  describe "list_for_user/1 and list_feed_for/1" do
    test "list_for_user returns only that user's posts, newest first" do
      alice = user_fixture()
      bob = user_fixture()
      {:ok, older} = Posts.create_tiding(alice.id, %{"body" => "first"})
      # utc_datetime (second precision) + a non-monotonic UUID tie-break
      # means the ordering test needs a real second between inserts.
      Process.sleep(1100)
      {:ok, newer} = Posts.create_tiding(alice.id, %{"body" => "second"})
      {:ok, _bobs} = Posts.create_tiding(bob.id, %{"body" => "not alice's"})

      assert Enum.map(Posts.list_for_user(alice.id), & &1.id) == [newer.id, older.id]
    end

    test "list_feed_for returns posts only from people the viewer clings to" do
      viewer = user_fixture()
      clinged = user_fixture()
      stranger = user_fixture()
      {:ok, _} = Social.cling(viewer.id, clinged.id)

      {:ok, post} = Posts.create_tiding(clinged.id, %{"body" => "from clinged"})
      {:ok, _} = Posts.create_tiding(stranger.id, %{"body" => "from stranger"})

      assert [only] = Posts.list_feed_for(viewer.id)
      assert only.id == post.id
    end
  end

  describe "reactions" do
    test "toggle_reaction adds then removes, updating counts" do
      author = user_fixture()
      reactor = user_fixture()
      {:ok, post} = Posts.create_tiding(author.id, %{"body" => "react to me"})

      assert Posts.reaction_counts(post.id) == %{heart: 0, torch: 0}
      refute Posts.reacted?(reactor.id, post.id, :heart)

      :ok = Posts.toggle_reaction(reactor.id, post.id, :heart)
      assert Posts.reaction_counts(post.id) == %{heart: 1, torch: 0}
      assert Posts.reacted?(reactor.id, post.id, :heart)

      :ok = Posts.toggle_reaction(reactor.id, post.id, :heart)
      assert Posts.reaction_counts(post.id) == %{heart: 0, torch: 0}
      refute Posts.reacted?(reactor.id, post.id, :heart)
    end

    test "heart and torch are independent reactions on the same post" do
      author = user_fixture()
      reactor = user_fixture()
      {:ok, post} = Posts.create_tiding(author.id, %{"body" => "react to me"})

      :ok = Posts.toggle_reaction(reactor.id, post.id, :heart)
      :ok = Posts.toggle_reaction(reactor.id, post.id, :torch)

      assert Posts.reaction_counts(post.id) == %{heart: 1, torch: 1}
    end

    test "toggle_reaction broadcasts on the post's topic" do
      author = user_fixture()
      reactor = user_fixture()
      {:ok, post} = Posts.create_tiding(author.id, %{"body" => "react to me"})

      Phoenix.PubSub.subscribe(Agora.PubSub, "post:#{post.id}")
      :ok = Posts.toggle_reaction(reactor.id, post.id, :heart)

      assert_receive {:reaction_updated, post_id}
      assert post_id == post.id
    end

    test "reaction_summary_for/2 batches counts and the viewer's own reactions for many posts" do
      author = user_fixture()
      viewer = user_fixture()
      other = user_fixture()
      {:ok, hearted_post} = Posts.create_tiding(author.id, %{"body" => "one"})
      {:ok, untouched_post} = Posts.create_tiding(author.id, %{"body" => "two"})

      :ok = Posts.toggle_reaction(viewer.id, hearted_post.id, :heart)
      :ok = Posts.toggle_reaction(other.id, hearted_post.id, :heart)
      :ok = Posts.toggle_reaction(other.id, hearted_post.id, :torch)

      summary =
        Posts.reaction_summary_for([hearted_post.id, untouched_post.id], viewer.id)

      assert summary[hearted_post.id] == %{
               heart_count: 2,
               torch_count: 1,
               hearted?: true,
               torched?: false
             }

      assert summary[untouched_post.id] == %{
               heart_count: 0,
               torch_count: 0,
               hearted?: false,
               torched?: false
             }
    end

    test "reaction_summary_for/2 marks nothing as the viewer's own when viewer_id is nil" do
      author = user_fixture()
      other = user_fixture()
      {:ok, post} = Posts.create_tiding(author.id, %{"body" => "anon viewer"})
      :ok = Posts.toggle_reaction(other.id, post.id, :heart)

      summary = Posts.reaction_summary_for([post.id], nil)

      assert summary[post.id] == %{
               heart_count: 1,
               torch_count: 0,
               hearted?: false,
               torched?: false
             }
    end

    test "toggle_reaction notifies the post's author when a reaction is added" do
      author = user_fixture()
      reactor = user_fixture()
      {:ok, post} = Posts.create_tiding(author.id, %{"body" => "react to me"})

      :ok = Posts.toggle_reaction(reactor.id, post.id, :torch)

      assert [notification] = Notifications.list_for_user(author.id)
      assert notification.type == :reaction
      assert notification.reaction_kind == :torch
      assert notification.actor_id == reactor.id
      assert notification.post_id == post.id
    end

    test "toggle_reaction does not notify again when a reaction is removed" do
      author = user_fixture()
      reactor = user_fixture()
      {:ok, post} = Posts.create_tiding(author.id, %{"body" => "react to me"})

      :ok = Posts.toggle_reaction(reactor.id, post.id, :heart)
      :ok = Posts.toggle_reaction(reactor.id, post.id, :heart)

      assert length(Notifications.list_for_user(author.id)) == 1
    end

    test "reacting to your own post does not notify you" do
      author = user_fixture()
      {:ok, post} = Posts.create_tiding(author.id, %{"body" => "my own post"})

      :ok = Posts.toggle_reaction(author.id, post.id, :heart)

      assert Notifications.list_for_user(author.id) == []
    end
  end

  describe "comments" do
    test "add_comment and list_comments" do
      author = user_fixture()
      commenter = user_fixture()
      {:ok, post} = Posts.create_tiding(author.id, %{"body" => "comment on me"})

      assert {:ok, _comment} = Posts.add_comment(commenter.id, post.id, "Amen!")
      assert [comment] = Posts.list_comments(post.id)
      assert comment.body == "Amen!"
    end

    test "add_comment broadcasts on the post's topic" do
      author = user_fixture()
      commenter = user_fixture()
      {:ok, post} = Posts.create_tiding(author.id, %{"body" => "comment on me"})

      Phoenix.PubSub.subscribe(Agora.PubSub, "post:#{post.id}")
      assert {:ok, _comment} = Posts.add_comment(commenter.id, post.id, "Amen!")

      assert_receive {:comment_added, post_id}
      assert post_id == post.id
    end

    test "comment_count/1 counts comments on a single post" do
      author = user_fixture()
      commenter = user_fixture()
      {:ok, post} = Posts.create_tiding(author.id, %{"body" => "comment on me"})

      assert Posts.comment_count(post.id) == 0
      {:ok, _} = Posts.add_comment(commenter.id, post.id, "one")
      {:ok, _} = Posts.add_comment(commenter.id, post.id, "two")
      assert Posts.comment_count(post.id) == 2
    end

    test "comment_counts_for/1 batches counts for many posts in one query" do
      author = user_fixture()
      commenter = user_fixture()
      {:ok, commented_post} = Posts.create_tiding(author.id, %{"body" => "one"})
      {:ok, untouched_post} = Posts.create_tiding(author.id, %{"body" => "two"})

      {:ok, _} = Posts.add_comment(commenter.id, commented_post.id, "Amen!")
      {:ok, _} = Posts.add_comment(commenter.id, commented_post.id, "Preach!")

      counts = Posts.comment_counts_for([commented_post.id, untouched_post.id])

      assert counts[commented_post.id] == 2
      assert counts[untouched_post.id] == 0
    end

    test "add_comment notifies the post's author" do
      author = user_fixture()
      commenter = user_fixture()
      {:ok, post} = Posts.create_tiding(author.id, %{"body" => "comment on me"})

      {:ok, _comment} = Posts.add_comment(commenter.id, post.id, "Amen!")

      assert [notification] = Notifications.list_for_user(author.id)
      assert notification.type == :comment
      assert notification.actor_id == commenter.id
      assert notification.post_id == post.id
    end

    test "commenting on your own post does not notify you" do
      author = user_fixture()
      {:ok, post} = Posts.create_tiding(author.id, %{"body" => "my own post"})

      {:ok, _comment} = Posts.add_comment(author.id, post.id, "talking to myself")

      assert Notifications.list_for_user(author.id) == []
    end
  end
end
