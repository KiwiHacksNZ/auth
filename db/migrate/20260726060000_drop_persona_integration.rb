class DropPersonaIntegration < ActiveRecord::Migration[8.0]
  def up
    remove_foreign_key :verifications, column: :persona_record_id
    remove_index :verifications, name: "index_verifications_on_persona_inquiry_id"
    remove_index :verifications, name: "index_verifications_on_persona_record_id"
    remove_column :verifications, :persona_inquiry_id
    remove_column :verifications, :persona_session_token
    remove_column :verifications, :persona_record_id

    remove_index :identities, name: "index_identities_on_persona_account_id"
    remove_column :identities, :persona_account_id

    drop_table :identity_persona_records
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Persona integration was removed; restore from the pre-removal schema if needed."
  end
end
