defmodule ShadowOpsCore.PrivacyGateTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.PrivacyGate

  test "blocks value-bearing secret material" do
    blocked = [
      "api_key=synthetic-placeholder",
      "access_token=synthetic-placeholder",
      "bearer_token=synthetic-placeholder",
      "password=synthetic-placeholder",
      "-----BEGIN PRIVATE KEY-----\nSYNTHETIC\n-----END PRIVATE KEY-----"
    ]

    Enum.each(blocked, fn sample ->
      assert {:error, :blocked, _reason} = PrivacyGate.check(sample)
    end)

    assert {:error, :blocked, _reason} = PrivacyGate.check(%{"API_KEY" => "placeholder"})

    assert {:error, :blocked, _reason} =
             PrivacyGate.check(%{
               "public_key" => "-----BEGIN PRIVATE KEY-----\nSYNTHETIC\n-----END PRIVATE KEY-----"
             })
  end

  test "allows non-secret documentation and public-key material" do
    allowed = [
      "the password was reset",
      "authentication token accepted",
      "documentation about JWT",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISYNTHETICPUBLICKEY user@example.invalid",
      "secret management policy"
    ]

    Enum.each(allowed, fn sample ->
      assert {:ok, :allowed} = PrivacyGate.check(sample)
    end)

    assert {:ok, :allowed} =
             PrivacyGate.check(%{
               "public_key" =>
                 "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISYNTHETICPUBLICKEY user@example.invalid"
             })
  end
end
