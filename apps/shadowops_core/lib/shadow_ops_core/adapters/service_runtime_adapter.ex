defmodule ShadowOpsCore.Adapters.ServiceRuntimeAdapter do
  @moduledoc """
  Behaviour for service runtime adapters that discover, identify and
  probe systemd/Docker/container services.

  Each adapter provides:
  - services/0: discover all services
  - service/1: get exact service by identity
  - runtime_identity/1: prove canonical runtime identity
  """

  @type service_identity :: %{
          scope: String.t(),
          name: String.t(),
          identity: String.t(),
          load_state: String.t() | nil,
          active_state: String.t(),
          sub_state: String.t(),
          fragment_path: String.t() | nil,
          source_path: String.t() | nil,
          pid: non_neg_integer() | nil,
          restart_count: non_neg_integer() | nil,
          last_error: String.t() | nil,
          status: String.t(),
          reachable: boolean(),
          real_data: boolean(),
          synthetic: boolean(),
          runtime_verified: boolean(),
          connected: boolean(),
          live: boolean(),
          source: String.t(),
          updated_at: String.t()
        }

  @callback services() :: {:ok, [service_identity()]} | {:error, term()}

  @callback service(String.t()) ::
              {:ok, service_identity()} | {:error, :not_found | term()}

  @callback runtime_identity(String.t()) ::
              {:ok, service_identity()}
              | {:error, :not_found | :ambiguous | :conflict | term()}
end
