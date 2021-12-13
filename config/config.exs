use Mix.Config

config :uplink, Uplink.Packages.Deployment.Secret, 
  secret: System.get_env("UPLINK_DEPLOYMENT_SECRET")

config :uplink, ecto_repos: [Uplink.Repo]

config :uplink, Uplink.Repo,
  database: System.get_env("UPLINK_DB_NAME"),
  username: System.get_env("UPLINK_DB_USERNAME"),
  password: System.get_env("UPLINK_DB_PASSWORD"),
  hostname: System.get_env("UPLINK_DB_HOST")