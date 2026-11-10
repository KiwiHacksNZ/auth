# check=error=true;skip=SecretsUsedInArgOrEnv

# Production image for both the web server and the GoodJob worker (the worker
# overrides the command). Build'n'run by hand:
# docker build -t identity_vault .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name identity_vault identity_vault
#
# No "# syntax=" line on purpose: the Dockerfile frontend built into Docker
# supports everything used here, and pinning one makes every build fetch it
# from Docker Hub first.
#
# Build speed: libheif, the gems and the JS packages build in separate stages,
# which BuildKit runs at the same time, and each uses every CPU (make -j, bundle
# --jobs). apt, Bundler and Yarn downloads live in cache mounts, so a rebuild
# after the cache is invalidated doesn't download them again.

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.4
FROM docker.io/library/ruby:3.4.4-slim@sha256:4020c2d289c1266fe4a2ea1d0018c22c17435905c514c66f8437555da57723ad AS base

# Rails app lives here
WORKDIR /rails

# Keep downloaded .debs so the apt cache mounts below are actually reused, and
# stop dpkg fsyncing every file it unpacks: on a slow disk that alone took
# minutes, and a half-written image layer is thrown away anyway.
RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
    echo 'force-unsafe-io' > /etc/dpkg/dpkg.cfg.d/unsafe-io

# Install base packages with runtime libraries for libheif
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips imagemagick postgresql-client libffi-dev \
    libjpeg62-turbo libaom3 libx265-199 libde265-0 libpng16-16 wget libxmlsec1 libxmlsec1-openssl

ARG NODE_VERSION=24.14.1
ARG YARN_VERSION=1.22.22
ENV PATH=/usr/local/node/bin:$PATH
ARG NODE_BUILD_VERSION=v5.4.33
RUN curl -sL "https://github.com/nodenv/node-build/archive/refs/tags/${NODE_BUILD_VERSION}.tar.gz" \
      -o /tmp/node-build.tar.gz && \
    echo "e07b8e6d6859537e07a6d3caf690c530f233812704b71f900029f2d8c43dd6e8  /tmp/node-build.tar.gz" | sha256sum -c - && \
    tar xz -C /tmp/ -f /tmp/node-build.tar.gz && \
    /tmp/node-build-*/bin/node-build "${NODE_VERSION}" /usr/local/node && \
    rm -rf /tmp/node-build* && \
    corepack enable && corepack prepare yarn@1.22.22+sha256.c17d3797fb9a9115bf375e31bfd30058cac6bc9c3b8807a3d8cb2094794b51ca


ENV BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_LIBRARY_PATH="/usr/local/lib" \
    RAILS_ENV="production"

# Packages needed to compile libheif and native gems.
FROM base AS build-deps
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config \
    cmake libjpeg-dev libpng-dev libaom-dev libx265-dev libde265-dev libxmlsec1-dev

# libheif, built from source for a newer version than Debian ships.
FROM build-deps AS libheif
ARG LIBHEIF_VERSION=1.23.2
ARG LIBHEIF_SHA256=1405ed070421459b569ff49deab109b7f1a30a447e72a9b20a4154f774634a44
RUN cd /tmp && \
    curl -sL "https://github.com/strukturag/libheif/archive/refs/tags/v${LIBHEIF_VERSION}.tar.gz" -o /tmp/libheif.tar.gz && \
    echo "${LIBHEIF_SHA256} /tmp/libheif.tar.gz" | sha256sum -c - && \
    tar xz -C /tmp/ -f /tmp/libheif.tar.gz && \
    cd /tmp/libheif-${LIBHEIF_VERSION} && \
    mkdir build && cd build && \
    cmake --preset=release -DWITH_EXAMPLES=ON -DENABLE_PLUGIN_LOADING=NO .. && \
    make -j"$(nproc)" && \
    make install && \
    cd / && rm -rf /tmp/libheif*

# Application gems. No gem links against libheif, so this runs alongside it.
FROM build-deps AS gems
COPY Gemfile Gemfile.lock ./
RUN --mount=type=cache,target=/root/.cache/gem-downloads,sharing=locked \
    mkdir -p "${BUNDLE_PATH}/ruby/3.4.0" && \
    ln -s /root/.cache/gem-downloads "${BUNDLE_PATH}/ruby/3.4.0/cache" && \
    MAKEFLAGS="-j$(nproc)" bundle install --jobs "$(nproc)" && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile && \
    chown -R 1000:1000 tmp

# JS packages, also alongside the gems.
FROM base AS node-modules
COPY package.json yarn.lock ./
RUN --mount=type=cache,target=/usr/local/share/.cache/yarn,sharing=locked \
    yarn install --frozen-lockfile --network-concurrency "$(nproc)"

# Application code and compiled assets.
FROM gems AS build
COPY . .

# Record the commit being built so the running app can report its version, then
# drop the git directory so it never reaches the final image.
ARG SOURCE_COMMIT=""
RUN if [ -n "$SOURCE_COMMIT" ]; then \
      echo "$SOURCE_COMMIT" > REVISION; \
    else \
      git config --global --add safe.directory /rails; \
      git rev-parse HEAD > REVISION 2>/dev/null || echo unknown > REVISION; \
    fi && \
    rm -rf .git

# Precompile bootsnap code and assets. node_modules is mounted for this step
# rather than copied in and deleted, which on a slow disk cost about two minutes.
# AWS_EC2_METADATA_DISABLED stops the AWS SDK waiting on an instance metadata
# endpoint that doesn't exist during a build.
RUN --mount=type=bind,from=node-modules,source=/rails/node_modules,target=/rails/node_modules,rw \
    bundle exec bootsnap precompile -j "$(nproc)" app/ lib/ && \
    mv config/credentials config/credentials.bak && \
    mkdir config/credentials && \
    mv config/credentials.yml.enc config/credentials.yml.enc.bak && \
    SECRET_KEY_BASE_DUMMY=1 \
    ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=precompile \
    ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=precompile \
    ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=precompile \
    AWS_EC2_METADATA_DISABLED=true \
    ./bin/rails assets:precompile ; \
    STATUS=$? && \
    rm -rf config/credentials && \
    mv config/credentials.bak config/credentials && \
    mv config/credentials.yml.enc.bak config/credentials.yml.enc && \
    find db log storage tmp ! -uid 1000 -exec chown 1000:1000 {} + && \
    exit $STATUS

# Final stage for app image
FROM base

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails
# Copy libheif libraries and examples from its build stage
COPY --from=libheif /usr/local/lib/libheif* /usr/local/lib/
COPY --from=libheif /usr/local/bin/heif-* /usr/local/bin/
COPY --from=libheif /usr/local/include/libheif /usr/local/include/libheif
RUN ldconfig

# Restrictive ImageMagick policy: only allow JPEG, PNG, HEIC, WEBP, PDF
COPY config/imagemagick-policy.xml /etc/ImageMagick-6/policy.xml

# Run as a non-root user for security. It owns only db, log, storage and tmp,
# which the earlier stages chown to uid 1000 (COPY keeps ownership). Each file is
# chowned in the stage that creates it: changing the owner of a file from an
# earlier layer copies the whole file into a new one, which for the 116 MB
# bootsnap cache took about 90 seconds.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
