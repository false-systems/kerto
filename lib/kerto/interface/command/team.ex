defmodule Kerto.Interface.Command.Team do
  @moduledoc """
  Team PKI management — init CA, join (create CSR), sign CSR, list members.

  Subcommands via --action flag:
    init  — create a new team CA in .kerto/
    join  — generate a node key + CSR for joining a team
    sign  — sign a CSR with the team CA
    list  — list team members (signed certificates)
  """

  alias Kerto.Interface.Response
  alias Kerto.Mesh.{Authority, Identity}

  @kerto_dir ".kerto"

  @spec execute(atom(), map()) :: Response.t()
  def execute(_engine, args) do
    case Map.get(args, :action) do
      "init" -> init_ca(args)
      "join" -> join_team(args)
      "sign" -> sign_csr(args)
      "list" -> list_members()
      nil -> Response.error("specify --action: init, join, sign, or list")
      other -> Response.error("unknown team action: #{other}")
    end
  end

  defp init_ca(args) do
    team_name = Map.get(args, :name, "kerto-team")
    ca_key_path = Path.join(@kerto_dir, "ca.key")
    ca_cert_path = Path.join(@kerto_dir, "ca.crt")

    if File.exists?(ca_cert_path) do
      Response.error("team CA already exists at #{ca_cert_path}")
    else
      File.mkdir_p!(@kerto_dir)
      {ca_key, ca_cert} = Authority.init_ca(team_name)
      File.write!(ca_key_path, Identity.key_to_pem(ca_key))
      File.write!(ca_cert_path, Identity.cert_to_pem(ca_cert))
      fingerprint = Identity.short_fingerprint(ca_cert)
      Response.success("Team CA created: #{team_name} (#{fingerprint})")
    end
  end

  defp join_team(args) do
    node_name = Map.get(args, :name, to_string(Node.self()))
    key_path = Path.join(@kerto_dir, "node.key")
    csr_path = Path.join(@kerto_dir, "node.csr")

    File.mkdir_p!(@kerto_dir)
    key = Identity.generate_key()
    csr = Authority.create_csr(key, node_name)
    File.write!(key_path, Identity.key_to_pem(key))
    File.write!(csr_path, X509.CSR.to_pem(csr))
    Response.success("CSR created at #{csr_path} — send to team admin for signing")
  end

  defp sign_csr(args) do
    csr_path = Map.get(args, :csr)

    if is_nil(csr_path) do
      Response.error("specify --csr <path> to the CSR file to sign")
    else
      ca_key_path = Path.join(@kerto_dir, "ca.key")
      ca_cert_path = Path.join(@kerto_dir, "ca.crt")

      with {:ok, ca_key_pem} <- File.read(ca_key_path),
           {:ok, ca_cert_pem} <- File.read(ca_cert_path),
           {:ok, csr_pem} <- File.read(csr_path) do
        ca_key = Identity.key_from_pem(ca_key_pem)
        ca_cert = Identity.cert_from_pem(ca_cert_pem)
        csr = X509.CSR.from_pem!(csr_pem)
        validity = Map.get(args, :validity, 365)
        cert = Authority.sign_csr(ca_key, ca_cert, csr, validity)

        cert_path = String.replace(csr_path, ~r/\.csr$/, ".crt")
        File.write!(cert_path, Identity.cert_to_pem(cert))
        Response.success("Signed certificate written to #{cert_path}")
      else
        {:error, _} ->
          Response.error("missing CA files or CSR — run 'kerto team --action init' first")
      end
    end
  end

  defp list_members do
    ca_cert_path = Path.join(@kerto_dir, "ca.crt")

    if File.exists?(ca_cert_path) do
      {:ok, ca_cert_pem} = File.read(ca_cert_path)
      ca_cert = Identity.cert_from_pem(ca_cert_pem)
      fingerprint = Identity.fingerprint(ca_cert)

      # Look for .crt files in .kerto/
      certs =
        Path.join(@kerto_dir, "*.crt")
        |> Path.wildcard()
        |> Enum.reject(&(&1 == ca_cert_path))

      header = "Team: #{Identity.short_fingerprint(ca_cert)} (#{fingerprint})\n"

      members =
        if certs == [] do
          "No signed members yet."
        else
          Enum.map_join(certs, "\n", fn path ->
            "  #{Path.basename(path)}"
          end)
        end

      Response.success(header <> members)
    else
      Response.error("no team CA found — run 'kerto team --action init' first")
    end
  end
end
