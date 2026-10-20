defmodule SpriteTriage.Stubs do
  @moduledoc """
  Req.Test stubs for the Sprites API. A scenario maps a route to a response; `:hang`
  sleeps past every test deadline, `:timeout` is a transport timeout. Every call is
  counted, so tests can assert that something was called only once, or not at all.
  """

  import Plug.Conn

  def api(scenario) do
    {:ok, counter} = Agent.start_link(fn -> %{} end)

    Req.Test.stub(SpriteTriage.ApiStub, fn conn ->
      route = route(conn)
      Agent.update(counter, &Map.update(&1, route, 1, fn n -> n + 1 end))
      respond(conn, Map.get(scenario, route, {404, %{"error" => "not stubbed"}}))
    end)

    counter
  end

  def calls(counter, route), do: Agent.get(counter, &Map.get(&1, route, 0))

  def sprite(status \\ "cold"),
    do: %{
      "id" => "sprite-00000000-test",
      "name" => "box",
      "organization" => "acme",
      "status" => status
    }

  # The body a real Sprite returned on its first /check after 15 quiet minutes.
  def suspended,
    do: %{
      "status" => "needs_repair",
      "reason" => "machine in suspended state",
      "elapsed" => 100,
      "sprite_name" => "box"
    }

  defp route(%{method: "GET", request_path: "/v1/sprites"}), do: :list

  defp route(%{method: "GET", request_path: "/v1/sprites/" <> rest}),
    do: if(String.ends_with?(rest, "/check"), do: :check, else: :sprite)

  defp route(_), do: :other

  defp respond(conn, :hang) do
    Process.sleep(2_000)
    send_resp(conn, 200, "late")
  end

  defp respond(conn, :timeout), do: Req.Test.transport_error(conn, :timeout)
  defp respond(conn, :refused), do: Req.Test.transport_error(conn, :econnrefused)

  defp respond(conn, {status, body, headers}) do
    conn = Enum.reduce(headers, conn, fn {k, v}, c -> put_resp_header(c, k, v) end)
    respond(conn, {status, body})
  end

  defp respond(conn, {status, body}) when is_map(body) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
  end

  defp respond(conn, {status, body}) when is_binary(body), do: send_resp(conn, status, body)
end
