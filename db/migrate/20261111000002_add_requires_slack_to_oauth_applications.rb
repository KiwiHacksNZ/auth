class AddRequiresSlackToOAuthApplications < ActiveRecord::Migration[8.0]
  def change
    add_column :oauth_applications, :requires_slack, :boolean, default: false, null: false
  end
end
