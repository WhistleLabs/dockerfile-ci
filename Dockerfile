# TODO - all security checking of downloaded binaries has been removed
ARG ALPINE_VERSION
ARG RUBY_VERSION

# Golang Build stage for lookup hiera tool
FROM golang:alpine AS hiera-build
ENV HIERA_VERSION 0.4.6
ENV HIERA_SHA 04c8819

RUN apk --no-cache add build-base git mercurial gcc && \
GO111MODULE=on && \
mkdir -p /tmp/build && \
  cd /tmp/build && \
  \
  # install hiera lookup
  go mod init local/build && \
  go get -d -v github.com/lyraproj/hiera@v${HIERA_VERSION} && \
  go get -d -v github.com/lyraproj/hiera/config && \
  go get -d -v github.com/lyraproj/hiera/api && \
  go get -d -v github.com/lyraproj/hiera/session && \
  go get -d -v github.com/lyraproj/hiera/hiera && \
  go get -d -v github.com/lyraproj/hiera/cli && \
  export BuildTime="$(date "+%m-%d-%Y_%H_%M_%S_%Z")" && \
  export BuildTag=$HIERA_VERSION && \
  export BuildSHA=$HIERA_SHA && \
  go build -ldflags "-X 'github.com/lyraproj/hiera/cli.BuildTag=$BuildTag' -X 'github.com/lyraproj/hiera/cli.BuildSHA=$BuildSHA' -X 'github.com/lyraproj/hiera/cli.BuildTime=$BuildTime'" -o bin/lookup github.com/lyraproj/hiera/lookup && \
  bin/lookup --version

FROM alpine:3.7 AS build
LABEL maintainer="WhistleLabs, Inc. <devops@whistle.com>"

RUN set -exv \
 && apk add --no-cache --update \
        ca-certificates curl unzip zsh \
 && :

WORKDIR /build
ENV PATH=$PATH:/build/bin

COPY install-zipped-bin ./bin/
RUN mkdir -pv terraform-providers

# To set these set them in `.circleci/config.yml`
ARG PACKER_VERSION
ARG TERRAFORM_VERSION

# @hashicorp releases
RUN set -exv \
 && export uri_template='https://releases.hashicorp.com/${name}/${ver}/${name}_${ver}_${arch}.zip' \
 # terraform providers
 && install-zipped-bin ./terraform-providers \
    terraform-provider-archive:1.2.2 \
    terraform-provider-aws:4.67.0  \
    terraform-provider-aws:2.70.4  \
    terraform-provider-github:2.3.1 \
    terraform-provider-google:2.7.0 \
    terraform-provider-kubernetes:1.11.1 \
    terraform-provider-newrelic:3.20.2 \
    terraform-provider-null:2.1.2 \
    terraform-provider-template:2.1.2 \
    terraform-provider-cloudamqp:1.26.2 \
    terraform-provider-cloudamqp:1.9.4 \
    terraform-provider-pagerduty:2.15.0 \
 && :
# @lmars releases
RUN set -exv \
 && export uri_template='https://github.com/lmars/${name}/releases/download/${full_ver}/${name}-${ver}-${arch}.zip' \
 # packer plugins
 && arch=linux-amd64 install-zipped-bin ./bin \
    packer-post-processor-vagrant-s3:1.4.0 \
 && :
# @WhistleLabs github releases
RUN set -exv \
 && export uri_template='https://github.com/WhistleLabs/${name}/releases/download/v${full_ver}/${name}_${ver}_${arch}.zip' \
 # packer plugins
 && install-zipped-bin ./bin \
    packer-provisioner-serverspec:0.1.1-whistle0 \
 # terraform providers
 && install-zipped-bin ./terraform-providers \
    terraform-provider-datadog:1.9.0-whistle0-tf012 \
    terraform-provider-logentries:1.0.2-whistle0-tf012 \
    terraform-provider-pagerduty:1.2.1-whistle0-tf012 \
    terraform-provider-rabbitmq:1.0.0-whistle0-tf012 \
 && :
# @jianyuan github releases sentry
RUN set -exv \
 && export uri_template='https://github.com/jianyuan/${name}/releases/download/v${full_ver}/${name}_${ver}_${arch}.zip' \
 # terraform providers
 && install-zipped-bin ./terraform-providers \
    terraform-provider-sentry:0.10.0 \
 && :
FROM ruby:${RUBY_VERSION}-alpine${ALPINE_VERSION} as covbuild
ARG COVALENCE_VERSION
ARG DUMBINIT_VERSION
ARG GOSU_VERSION
ARG GOSU_KEY
ARG SOPS_VERSION
ARG YQ_VERSION
ARG HCLEDIT_VERSION
ARG HCL2JSON_VERSION
ENV COVALENCE_VERSION $COVALENCE_VERSION
ENV DUMBINIT_VERSION $DUMBINIT_VERSION
ENV GOSU_VERSION $GOSU_VERSION
ENV GOSU_KEY B42F6819007F00F88E364FD4036A9C25BF357DD4
ENV SOPS_VERSION $SOPS_VERSION
ENV YQ_VERSION $YQ_VERSION
ENV HCLEDIT_VERSION $HCLEDIT_VERSION
ENV HCL2JSON_VERSION $HCL2JSON_VERSION

RUN set -ex; \
  \
  fetchDeps=' \
    build-base \
    ca-certificates \
    curl-dev \
    gnupg \
    openssl \
    python-dev \
    ruby-dev \
    unzip \
    wget \
    git \
  '; \
  apk add --no-cache --update $fetchDeps && \
  \
  mkdir -p /tmp/build && \
  cd /tmp/build && \
  \
  # Gosu
  wget -O /tmp/build/gosu "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-amd64"; \
  wget -O /tmp/build/gosu.asc "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-amd64.asc"; \
  \
  ( gpg --keyserver keys.openpgp.org --receive-keys "$GOSU_KEY" \
  || gpg --keyserver hkp://keyserver.ubuntu.com:80 --receive-keys "$GOSU_KEY" ); \
  gpg --batch --verify gosu.asc gosu; \
  chmod +x gosu; \
  \
  # Dumb-init
  wget -O /tmp/build/dumb-init "https://github.com/Yelp/dumb-init/releases/download/v${DUMBINIT_VERSION}/dumb-init_${DUMBINIT_VERSION}_amd64"; \
  chmod +x dumb-init; \
  \
  # Sops
  wget -O /tmp/build/sops "https://github.com/mozilla/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux"; \
  chmod +x sops; \
  \
  # yq
  wget -O /tmp/build/yq https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64; \
  chmod +x yq; \
  # hcledit
  wget -c https://github.com/minamijoyo/hcledit/releases/download/v${HCLEDIT_VERSION}/hcledit_${HCLEDIT_VERSION}_linux_amd64.tar.gz -O - | tar -xz -C /tmp/build/ hcledit; \
  chmod +x hcledit; \
  # json2hcl2
  wget -c https://github.com/disaac/json2hcl2/releases/download/v0.1.0/json2hcl2_Linux_x86_64.tar.gz -O - | tar -xz -C /tmp/build json2hcl2; \
  chmod +x json2hcl2; \
  # hcl2json
  wget -O /tmp/build/hcl2json https://github.com/tmccombs/hcl2json/releases/download/v${HCL2JSON_VERSION}/hcl2json_linux_amd64; \
  chmod +x hcl2json; \
  # tfenv
  git clone --depth=1 https://github.com/tfutils/tfenv.git ./tfenv; \
  # tgenv
  git clone https://github.com/tgenv/tgenv.git ./tgenv; \
  # pkenv
  git clone https://github.com/iamhsa/pkenv.git ./pkenv;
COPY tools/covalence/Gemfile /tmp/build
COPY tools/covalence/.gemrc /tmp/build

RUN set -ex; \
  \
  cd /tmp/build && \
  \
  # Ruby Gems
  # DEVOPS-2520 Output Covalence SHA to prevent stale cache
  echo "**** install bundles and covalence ${COVALENCE_VERSION} ****" && \
  bundle install --path=/opt/gems --binstubs=/opt/bin --jobs=4 --retry=3

FROM ruby:${RUBY_VERSION}-alpine${ALPINE_VERSION}
ARG COVALENCE_VERSION
ARG TERRAGRUNT_VERSION
ARG PACKER_VERSION
ARG TERRAFORM_VERSION
ARG TERRAFORM_LATEST
ARG TERRAGRUNT_LATEST
ARG PACKER_LATEST
LABEL packer_version="${PACKER_VERSION}"
LABEL terraform_version="${TERRAFORM_VERSION}"
LABEL terragrunt_version="${TERRAGRUNT_VERSION}"
LABEL packer_latest="${PACKER_LATEST}"
LABEL terraform_latest="${TERRAFORM_LATEST}"
LABEL terragrunt_latest="${TERRAGRUNT_LATEST}"
LABEL maintainer="WhistleLabs, Inc. <devops@whistle.com>"
ENV TERRAGRUNT_VERSION $TERRAGRUNT_VERSION
ENV TERRAFORM_VERSION $TERRAFORM_VERSION
ENV PACKER_LATEST $PACKER_LATEST
ENV TERRAGRUNT_LATEST $TERRAGRUNT_LATEST
ENV TERRAFORM_LATEST $TERRAFORM_LATEST
ENV PACKER_VERSION $PACKER_VERSION
ENV COVALENCE_VERSION $COVALENCE_VERSION
ENV BUNDLE_GEMFILE /opt/Gemfile
ENV BUNDLE_PATH /opt/gems
ENV PATH /opt/bin:/usr/local/tfenv/bin:/usr/local/tgenv/bin:/usr/local/pkenv/bin:$PATH

COPY --from=covbuild /tmp/build/gosu /usr/local/bin/
COPY --from=covbuild /tmp/build/dumb-init /usr/local/bin/
COPY --from=covbuild /tmp/build/sops /usr/local/bin/
COPY --from=covbuild /tmp/build/tfenv /usr/local/tfenv
COPY --from=covbuild /tmp/build/tgenv /usr/local/tgenv
COPY --from=covbuild /tmp/build/pkenv /usr/local/pkenv
COPY --from=covbuild /tmp/build/yq /usr/local/bin/
COPY --from=covbuild /tmp/build/hcledit /usr/local/bin/hcledit
COPY --from=covbuild /tmp/build/json2hcl2 /usr/local/bin/json2hcl2
COPY --from=covbuild /tmp/build/hcl2json /usr/local/bin/hcl2json
COPY --from=covbuild /tmp/build/Gemfile /opt/
COPY --from=covbuild /tmp/build/Gemfile.lock /opt/
COPY --from=covbuild /tmp/build/.gemrc /opt/
COPY --from=covbuild /opt/gems /opt/gems
COPY --from=covbuild /opt/bin /opt/bin
# TODO - postgresql-client is hopefully temporary, see DEVOPS-1844
RUN set -exv; \
  \
  fetchDeps=' \
    ca-certificates \
    curl \
    unzip \
    zsh \
    bash \
    fzf \
    curl-dev \
    jq \
    python-dev \
    python3-dev \
    git \
    postgresql-client \
    gnupg \
    openssh \
    openssl \
    unzip \
  '; \
  apk add --no-cache --update $fetchDeps && \
  # pip
  echo "**** install pip ****" && \
  python3 -m ensurepip && \
  rm -r /usr/lib/python*/ensurepip && \
  pip3 install --no-cache --upgrade pip setuptools wheel && \
  pip3 install --no-cache --upgrade --ignore-installed awscli

ENV SHELL=zsh

RUN mkdir -p /usr/local/bin && \
    mkdir -p /tmp/build && \
    cd /tmp/build && \
    # Install glibc
    wget -q -O /etc/apk/keys/sgerrand.rsa.pub "https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub" && \
    wget -q "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/2.29-r0/glibc-2.29-r0.apk" && \
    apk add glibc-2.29-r0.apk && \
    apk add postgresql-client && \
    # Install gem packages and covalence if not already present
    echo "**** install bundles and covalence ${COVALENCE_VERSION} ****" && \
    bundle check --gemfile=/opt/Gemfile --path=/opt/gems || bundle install --binstubs=/opt/bin --gemfile=/opt/Gemfile --path=/opt/gems --jobs=4 --retry=3 && \
    tfenv install ${TERRAFORM_VERSION} && \
    tgenv install ${TERRAGRUNT_VERSION} && \
    pkenv install ${PACKER_VERSION} && \
    tfenv install ${TERRAFORM_LATEST} && \
    tgenv install ${TERRAGRUNT_LATEST} && \
    pkenv install ${PACKER_LATEST} && \
    # Use the versions specified by default
    tfenv use ${TERRAFORM_VERSION} && \
    tgenv use ${TERRAGRUNT_VERSION} && \
    pkenv use ${PACKER_VERSION} && \
    tfenv list && \
    tgenv list && \
    pkenv list && \
    # Cleanup
    cd / && \
    rm -rf /tmp/build
# Copy required binaries from previous build stages
COPY --from=build /build/bin/* /usr/local/bin/
COPY --from=hiera-build /tmp/build/bin/lookup /usr/local/bin/
# Provider dir needs write permissions by everyone in case additional providers need to be installed at runtime
# TODO Move these to ~/.teraform.d/plugins instead, avoiding all the magic required for this (and the 777)
COPY --from=build /build/terraform-providers/* /usr/local/bin/terraform-providers/linux_amd64/
RUN chmod 777 /usr/local/bin/terraform-providers/linux_amd64
# Create sumbolic links to packer providers in all versions
RUN  for i in /usr/local/pkenv/versions/[0-9]*; do for b in /usr/local/bin/packer-*;do ln -s "${b}" "${i}"/$(basename "${b}");done; done
COPY .build_ts .
COPY tools/covalence/entrypoint.sh /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
