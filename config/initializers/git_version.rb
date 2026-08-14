# Identify the commit this build was made from.
#
# Production images have no .git directory, so the Dockerfile stamps the SHA
# into a REVISION file at image build time. REVISION wins over SOURCE_COMMIT
# because it cannot drift: SOURCE_COMMIT is set by hand on platforms that inject
# it and goes stale the moment it is forgotten. Shelling out to git is the last
# resort and only works in a development checkout.
run_git = ->(command) do
  output = `#{command} 2>/dev/null`.strip
  $?&.success? && output.present? ? output : nil
rescue StandardError
  nil
end

revision_file = Rails.root.join("REVISION")
revision = revision_file.exist? ? revision_file.read.strip.presence : nil
revision = nil if revision == "unknown"

git_hash = revision || ENV["SOURCE_COMMIT"].presence || run_git.call("git rev-parse HEAD")

short_hash = git_hash ? git_hash[0..7] : "unknown"

# The repository the deployed code lives in, so the version links to our own
# commits rather than the upstream project this is forked from.
repo = ENV.fetch("GITHUB_REPOSITORY", "KiwiHacksNZ/auth")
commit_link = git_hash ? "https://github.com/#{repo}/commit/#{git_hash}" : nil

commit_count = run_git.call("git rev-list --count HEAD").to_i

# Check for uncommitted changes; a container has no working tree to inspect.
is_dirty = run_git.call("git status --porcelain").present?

# Append "-dirty" if there are uncommitted changes
version = is_dirty ? "#{short_hash}-dirty" : short_hash

# Store server start time
Rails.application.config.server_start_time = Time.current

# Store the version
Rails.application.config.git_version = version
Rails.application.config.git_commit_count = commit_count
Rails.application.config.commit_link = commit_link
