class AddRequiresDiscordToOAuthApplications < ActiveRecord::Migration[8.0]
  def up
    add_column :oauth_applications, :requires_discord, :boolean, default: false, null: false

    # Until now every app requesting discord_id required Discord to be linked.
    # Keep that for existing apps; their owners can switch it off.
    execute <<~SQL
      UPDATE oauth_applications SET requires_discord = TRUE
      WHERE ' ' || scopes || ' ' LIKE '% discord_id %'
    SQL
  end

  def down
    remove_column :oauth_applications, :requires_discord
  end
end
