defmodule ShadowOpsWeb.LiveHelpers do
  def format_timestamp(timestamp) do
    if is_nil(timestamp) or timestamp == 0 do
      "N/A"
    else
      {:ok, datetime} = DateTime.from_unix(timestamp)
      DateTime.to_string(datetime)
    end
  end
end
