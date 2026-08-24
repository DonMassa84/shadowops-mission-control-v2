defmodule ShadowOpsWeb.SocialReviewLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents

  alias ShadowOps.Social.FacebookAnalytics

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, review: FacebookAnalytics.social_review())}
  end

  defp display(nil), do: "N/A"
  defp display(true), do: "YES"
  defp display(false), do: "NO"
  defp display(value), do: to_string(value)
end
