class AddDiscordIdToIdentities < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :identities, :discord_id, :string
    add_index :identities, :discord_id, algorithm: :concurrently
  end
end
